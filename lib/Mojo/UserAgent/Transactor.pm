package Mojo::UserAgent::Transactor;
use Mojo::Base -base;

use File::Basename 'basename';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::JSON 'encode_json';
use Mojo::Parameters;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::Util qw(encode url_escape);

has generators => sub { {form => \&_form, json => \&_json} };
has name => 'Mojolicious (Perl)';

sub add_generator {
  my ($self, $name, $cb) = @_;
  $self->generators->{$name} = $cb;
  return $self;
}

sub endpoint {
  my ($self, $tx) = @_;

  # Basic endpoint
  my $req   = $tx->req;
  my $url   = $req->url;
  my $proto = $url->protocol || 'http';
  my $host  = $url->ihost;
  my $port  = $url->port || ($proto eq 'https' ? 443 : 80);

  # Proxy for normal HTTP requests
  return $self->_proxy($tx, $proto, $host, $port)
    if $proto eq 'http' && !$req->is_handshake;

  return $proto, $host, $port;
}

sub peer {
  my ($self, $tx) = @_;
  return $self->_proxy($tx, $self->endpoint($tx));
}

sub proxy_connect {
  my ($self, $old) = @_;

  # Already a CONNECT request
  my $req = $old->req;
  return undef if uc $req->method eq 'CONNECT';

  # No proxy
  return undef unless my $proxy = $req->proxy;

  # WebSocket and/or HTTPS
  my $url = $req->url;
  return undef unless $req->is_handshake || $url->protocol eq 'https';

  # CONNECT request (expect a bad response)
  my $new = $self->tx(CONNECT => $url->clone->userinfo(undef));
  $new->req->proxy($proxy);
  $new->res->content->auto_relax(0)->headers->connection('keep-alive');

  return $new;
}

sub redirect {
  my ($self, $old) = @_;

  # Commonly used codes
  my $res = $old->res;
  my $code = $res->code // 0;
  return undef unless grep { $_ == $code } 301, 302, 303, 307, 308;

  # Fix location without authority and/or scheme
  return unless my $location = $res->headers->location;
  $location = Mojo::URL->new($location);
  $location = $location->base($old->req->url)->to_abs unless $location->is_abs;

  # Clone request if necessary
  my $new = Mojo::Transaction::HTTP->new;
  my $req = $old->req;
  if ($code == 307 || $code == 308) {
    return undef unless my $clone = $req->clone;
    $new->req($clone);
  }
  else {
    my $method = uc $req->method;
    my $headers = $new->req->method($method eq 'POST' ? 'GET' : $method)
      ->content->headers($req->headers->clone)->headers;
    $headers->remove($_) for grep {/^content-/i} @{$headers->names};
  }
  my $headers = $new->req->url($location)->headers;
  $headers->remove($_) for qw(Authorization Cookie Host Referer);
  return $new->previous($old);
}

sub tx {
  my $self = shift;

  # Method and URL
  my $tx  = Mojo::Transaction::HTTP->new;
  my $req = $tx->req->method(shift);
  my $url = shift;
  $url = "http://$url" unless $url =~ m!^/|://!;
  ref $url ? $req->url($url) : $req->url->parse($url);

  # Headers (we identify ourselves and accept gzip compression)
  my $headers = $req->headers;
  $headers->from_hash(shift) if ref $_[0] eq 'HASH';
  $headers->user_agent($self->name) unless $headers->user_agent;
  $headers->accept_encoding('gzip') unless $headers->accept_encoding;

  # Generator
  if (@_ > 1) {
    return $tx unless my $generator = $self->generators->{shift()};
    $self->$generator($tx, @_);
  }

  # Body
  elsif (@_) { $req->body(shift) }

  return $tx;
}

sub upgrade {
  my ($self, $tx) = @_;
  my $code = $tx->res->code // 0;
  return undef unless $tx->req->is_handshake && $code == 101;
  my $ws = Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1);
  return $ws->client_challenge ? $ws : undef;
}

sub websocket {
  my $self = shift;

  # New WebSocket transaction
  my $sub = ref $_[-1] eq 'ARRAY' ? pop : [];
  my $tx = $self->tx(GET => @_);
  my $req = $tx->req;
  $req->headers->sec_websocket_protocol(join ', ', @$sub) if @$sub;
  my $url   = $req->url;
  my $proto = $url->protocol;
  $url->scheme($proto eq 'wss' ? 'https' : 'http') if $proto;

  # Handshake
  Mojo::Transaction::WebSocket->new(handshake => $tx)->client_handshake;

  return $tx;
}

sub _form {
  my ($self, $tx, $form, %options) = @_;

  # Check for uploads and force multipart if necessary
  my $multipart;
  for my $value (map { ref $_ eq 'ARRAY' ? @$_ : $_ } values %$form) {
    ++$multipart and last if ref $value eq 'HASH';
  }
  my $req     = $tx->req;
  my $headers = $req->headers;
  $headers->content_type('multipart/form-data') if $multipart;

  # Multipart
  if (($headers->content_type // '') eq 'multipart/form-data') {
    my $parts = $self->_multipart($options{charset}, $form);
    $req->content(
      Mojo::Content::MultiPart->new(headers => $headers, parts => $parts));
    return $tx;
  }

  # Query parameters or urlencoded
  my $p = Mojo::Parameters->new(map { $_ => $form->{$_} } sort keys %$form);
  $p->charset($options{charset}) if defined $options{charset};
  my $method = uc $req->method;
  if ($method eq 'GET' || $method eq 'HEAD') { $req->url->query->merge($p) }
  else {
    $req->body($p->to_string);
    $headers->content_type('application/x-www-form-urlencoded');
  }
  return $tx;
}

sub _json {
  my ($self, $tx, $data) = @_;
  my $headers = $tx->req->body(encode_json($data))->headers;
  $headers->content_type('application/json') unless $headers->content_type;
  return $tx;
}

sub _multipart {
  my ($self, $charset, $form) = @_;

  my @parts;
  for my $name (sort keys %$form) {
    my $values = $form->{$name};
    for my $value (ref $values eq 'ARRAY' ? @$values : ($values)) {
      push @parts, my $part = Mojo::Content::Single->new;

      # Upload
      my $filename;
      my $headers = $part->headers;
      if (ref $value eq 'HASH') {

        # File
        if (my $file = delete $value->{file}) {
          $file = Mojo::Asset::File->new(path => $file) unless ref $file;
          $part->asset($file);
          $value->{filename} //= basename $file->path
            if $file->isa('Mojo::Asset::File');
        }

        # Memory
        elsif (defined(my $content = delete $value->{content})) {
          $part->asset(Mojo::Asset::Memory->new->add_chunk($content));
        }

        # Filename and headers
        $filename = url_escape delete $value->{filename} // $name, '"';
        $filename = encode $charset, $filename if $charset;
        $headers->from_hash($value);
      }

      # Field
      else {
        $value = encode $charset, $value if $charset;
        $part->asset(Mojo::Asset::Memory->new->add_chunk($value));
      }

      # Content-Disposition
      $name = url_escape $name, '"';
      $name = encode $charset, $name if $charset;
      my $disposition = qq{form-data; name="$name"};
      $disposition .= qq{; filename="$filename"} if defined $filename;
      $headers->content_disposition($disposition);
    }
  }

  return \@parts;
}

sub _proxy {
  my ($self, $tx, $proto, $host, $port) = @_;

  # Update with proxy information
  if (my $proxy = $tx->req->proxy) {
    $proto = $proxy->protocol;
    $host  = $proxy->ihost;
    $port  = $proxy->port || ($proto eq 'https' ? 443 : 80);
  }

  return $proto, $host, $port;
}

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent::Transactor - User agent transactor

=head1 SYNOPSIS

  use Mojo::UserAgent::Transactor;

  # Simple GET request
  my $t = Mojo::UserAgent::Transactor->new;
  say $t->tx(GET => 'http://example.com')->req->to_string;

  # PATCH request with "Do Not Track" header and content
  say $t->tx(PATCH => 'example.com' => {DNT => 1} => 'Hi!')->req->to_string;

  # POST request with form-data
  say $t->tx(POST => 'example.com' => form => {a => 'b'})->req->to_string;

  # PUT request with JSON data
  say $t->tx(PUT => 'example.com' => json => {a => 'b'})->req->to_string;

=head1 DESCRIPTION

L<Mojo::UserAgent::Transactor> is the transaction building and manipulation
framework used by L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojo::UserAgent::Transactor> implements the following attributes.

=head2 generators

  my $generators = $t->generators;
  $t             = $t->generators({foo => sub {...}});

Registered content generators, by default only C<form> and C<json> are already
defined.

=head2 name

  my $name = $t->name;
  $t       = $t->name('Mojolicious');

Value for C<User-Agent> request header of generated transactions, defaults to
C<Mojolicious (Perl)>.

=head1 METHODS

L<Mojo::UserAgent::Transactor> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add_generator

  $t = $t->add_generator(foo => sub {...});

Register a new content generator.

=head2 endpoint

  my ($proto, $host, $port) = $t->endpoint(Mojo::Transaction::HTTP->new);

Actual endpoint for transaction.

=head2 peer

  my ($proto, $host, $port) = $t->peer(Mojo::Transaction::HTTP->new);

Actual peer for transaction.

=head2 proxy_connect

  my $tx = $t->proxy_connect(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::HTTP> proxy C<CONNECT> request for transaction if
possible.

=head2 redirect

  my $tx = $t->redirect(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::HTTP> followup request for C<301>, C<302>, C<303>,
C<307> or C<308> redirect response if possible.

=head2 tx

  my $tx = $t->tx(GET  => 'example.com');
  my $tx = $t->tx(POST => 'http://example.com');
  my $tx = $t->tx(GET  => 'http://example.com' => {DNT => 1});
  my $tx = $t->tx(PUT  => 'http://example.com' => 'Hi!');
  my $tx = $t->tx(PUT  => 'http://example.com' => form => {a => 'b'});
  my $tx = $t->tx(PUT  => 'http://example.com' => json => {a => 'b'});
  my $tx = $t->tx(POST => 'http://example.com' => {DNT => 1} => 'Hi!');
  my $tx = $t->tx(
    PUT  => 'http://example.com' => {DNT => 1} => form => {a => 'b'});
  my $tx = $t->tx(
    PUT  => 'http://example.com' => {DNT => 1} => json => {a => 'b'});

Versatile general purpose L<Mojo::Transaction::HTTP> transaction builder for
requests, with support for content generators.

  # Generate and inspect custom GET request with DNT header and content
  say $t->tx(GET => 'example.com' => {DNT => 1} => 'Bye!')->req->to_string;

  # Use a custom socket for processing this transaction
  my $tx = $t->tx(GET => 'http://example.com');
  $tx->connection($sock);

  # Stream response content to STDOUT
  my $tx = $t->tx(GET => 'http://example.com');
  $tx->res->content->unsubscribe('read')->on(read => sub { say $_[1] });

  # PUT request with content streamed from file
  my $tx = $t->tx(PUT => 'http://example.com');
  $tx->req->content->asset(Mojo::Asset::File->new(path => '/foo.txt'));

  # GET request with query parameters
  my $tx = $t->tx(GET => 'http://example.com' => form => {a => 'b'});

  # POST request with "application/json" content
  my $tx = $t->tx(
    POST => 'http://example.com' => json => {a => 'b', c => [1, 2, 3]});

  # POST request with "application/x-www-form-urlencoded" content
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {a => 'b', c => 'd'});

  # PUT request with Shift_JIS encoded form values
  my $tx = $t->tx(
    PUT => 'example.com' => form => {a => 'b'} => charset => 'Shift_JIS');

  # POST request with form values sharing the same name
  my $tx = $t->tx(POST => 'http://example.com' => form => {a => [qw(b c d)]});

  # POST request with "multipart/form-data" content
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {mytext => {content => 'lala'}});

  # POST request with upload streamed from file
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {mytext => {file => '/foo.txt'}});

  # POST request with upload streamed from asset
  my $asset = Mojo::Asset::Memory->new->add_chunk('lalala');
  my $tx    = $t->tx(
    POST => 'http://example.com' => form => {mytext => {file => $asset}});

  # POST request with multiple files sharing the same name
  my $tx = $t->tx(POST => 'http://example.com' =>
    form => {mytext => [{content => 'first'}, {content => 'second'}]});

  # POST request with form values and customized upload (filename and header)
  my $tx = $t->tx(POST => 'http://example.com' => form => {
    a      => 'b',
    c      => 'd',
    mytext => {
      content        => 'lalala',
      filename       => 'foo.txt',
      'Content-Type' => 'text/plain'
    }
  });

The C<form> content generator will automatically use query parameters for
C<GET>/C<HEAD> requests and the C<application/x-www-form-urlencoded> content
type for everything else. Both get upgraded automatically to using the
C<multipart/form-data> content type when necessary or when the header has been
set manually.

  # Force "multipart/form-data"
  my $headers = {'Content-Type' => 'multipart/form-data'};
  my $tx = $t->tx(POST => 'example.com' => $headers => form => {a => 'b'});

=head2 upgrade

  my $tx = $t->upgrade(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::WebSocket> followup transaction for WebSocket
handshake if possible.

=head2 websocket

  my $tx = $t->websocket('ws://example.com');
  my $tx = $t->websocket('ws://example.com' => {DNT => 1} => ['v1.proto']);

Versatile L<Mojo::Transaction::HTTP> transaction builder for WebSocket
handshake requests.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
