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
use Mojo::WebSocket qw(challenge client_handshake);

has generators => sub { {form => \&_form, json => \&_json} };
has name => 'Mojolicious (Perl)';

sub add_generator { $_[0]->generators->{$_[1]} = $_[2] and return $_[0] }

sub endpoint {
  my ($self, $tx) = @_;

  # Basic endpoint
  my $req   = $tx->req;
  my $url   = $req->url;
  my $proto = $url->protocol || 'http';
  my $host  = $url->ihost;
  my $port  = $url->port || ($proto eq 'https' ? 443 : 80);

  # Proxy for normal HTTP requests
  my $socks;
  if (my $proxy = $req->proxy) { $socks = $proxy->protocol eq 'socks' }
  return $self->_proxy($tx, $proto, $host, $port)
    if $proto eq 'http' && !$req->is_handshake && !$socks;

  return $proto, $host, $port;
}

sub peer { $_[0]->_proxy($_[1], $_[0]->endpoint($_[1])) }

sub proxy_connect {
  my ($self, $old) = @_;

  # Already a CONNECT request
  my $req = $old->req;
  return undef if uc $req->method eq 'CONNECT';

  # No proxy
  return undef unless (my $proxy = $req->proxy) && $req->via_proxy;
  return undef if $proxy->protocol eq 'socks';

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

  # CONNECT requests cannot be redirected
  my $req = $old->req;
  return undef if uc $req->method eq 'CONNECT';

  # Fix location without authority and/or scheme
  return undef
    unless my $location = $res->headers->every_header('Location')->[0];
  $location = Mojo::URL->new($location);
  $location = $location->base($req->url)->to_abs unless $location->is_abs;
  my $proto = $location->protocol;
  return undef if ($proto ne 'http' && $proto ne 'https') || !$location->host;

  # Clone request if necessary
  my $new = Mojo::Transaction::HTTP->new;
  if ($code == 307 || $code == 308) {
    return undef unless my $clone = $req->clone;
    $new->req($clone);
  }
  else {
    my $m = uc $req->method;
    my $headers = $new->req->method($code == 303 || $m eq 'POST' ? 'GET' : $m)
      ->content->headers($req->headers->clone)->headers;
    $headers->remove($_) for grep {/^content-/i} @{$headers->names};
  }
  my $headers = $new->req->url($location)->headers;
  $headers->remove($_) for qw(Authorization Cookie Host Referer);
  return $new->previous($old);
}

sub tx {
  my ($self, $method, $url) = (shift, shift, shift);

  # Method and URL
  my $tx  = Mojo::Transaction::HTTP->new;
  my $req = $tx->req->method($method);
  if   (ref $url) { $req->url($url) }
  else            { $req->url->parse($url =~ m!^/|://! ? $url : "http://$url") }

  # Headers (we identify ourselves and accept gzip compression)
  my $headers = $req->headers;
  $headers->from_hash(shift) if ref $_[0] eq 'HASH';
  $headers->user_agent($self->name) unless $headers->user_agent;
  $headers->accept_encoding('gzip') unless $headers->accept_encoding;

  # Generator
  if (@_ > 1) {
    my $cb = $self->generators->{shift()};
    $self->$cb($tx, @_);
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
  return challenge($ws) ? $ws->established(1) : undef;
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
  return client_handshake $tx;
}

sub _form {
  my ($self, $tx, $form, %options) = @_;
  $options{charset} = 'UTF-8' unless exists $options{charset};

  # Check for uploads and force multipart if necessary
  my $req       = $tx->req;
  my $headers   = $req->headers;
  my $multipart = ($headers->content_type // '') =~ m!multipart/form-data!i;
  for my $value (map { ref $_ eq 'ARRAY' ? @$_ : $_ } values %$form) {
    ++$multipart and last if ref $value eq 'HASH';
  }

  # Multipart
  if ($multipart) {
    my $parts = $self->_multipart($options{charset}, $form);
    $req->content(
      Mojo::Content::MultiPart->new(headers => $headers, parts => $parts));
    _type($headers, 'multipart/form-data');
    return $tx;
  }

  # Query parameters or urlencoded
  my $method = uc $req->method;
  my @form = map { $_ => $form->{$_} } sort keys %$form;
  if ($method eq 'GET' || $method eq 'HEAD') { $req->url->query->merge(@form) }
  else {
    $req->body(
      Mojo::Parameters->new(@form)->charset($options{charset})->to_string);
    _type($headers, 'application/x-www-form-urlencoded');
  }
  return $tx;
}

sub _json {
  my ($self, $tx, $data) = @_;
  _type($tx->req->body(encode_json $data)->headers, 'application/json');
  return $tx;
}

sub _multipart {
  my ($self, $charset, $form) = @_;

  my @parts;
  for my $name (sort keys %$form) {
    next unless defined(my $values = $form->{$name});
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

  my $req = $tx->req;
  if ($req->via_proxy && (my $proxy = $req->proxy)) {
    return $proxy->protocol, $proxy->ihost,
      $proxy->port || ($proto eq 'https' ? 443 : 80);
  }

  return $proto, $host, $port;
}

sub _type { $_[0]->content_type($_[1]) unless $_[0]->content_type }

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent::Transactor - User agent transactor

=head1 SYNOPSIS

  use Mojo::UserAgent::Transactor;

  # GET request with Accept header
  my $t = Mojo::UserAgent::Transactor->new;
  say $t->tx(GET => 'http://example.com' => {Accept => '*/*'})->req->to_string;

  # POST request with form-data
  say $t->tx(POST => 'example.com' => form => {a => 'b'})->req->to_string;

  # PUT request with JSON data
  say $t->tx(PUT => 'example.com' => json => {a => 'b'})->req->to_string;

=head1 DESCRIPTION

L<Mojo::UserAgent::Transactor> is the transaction building and manipulation
framework used by L<Mojo::UserAgent>.

=head1 GENERATORS

These content generators are available by default.

=head2 form

  $t->tx(POST => 'http://example.com' => form => {a => 'b'});

Generate query string, C<application/x-www-form-urlencoded> or
C<multipart/form-data> content.

=head2 json

  $t->tx(PATCH => 'http://example.com' => json => {a => 'b'});

Generate JSON content with L<Mojo::JSON>.

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

Register a content generator.

  $t->add_generator(foo => sub {
    my ($t, $tx, @args) = @_;
    ...
  });

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

Build L<Mojo::Transaction::HTTP> follow-up request for C<301>, C<302>, C<303>,
C<307> or C<308> redirect response if possible.

=head2 tx

  my $tx = $t->tx(GET  => 'example.com');
  my $tx = $t->tx(POST => 'http://example.com');
  my $tx = $t->tx(GET  => 'http://example.com' => {Accept => '*/*'});
  my $tx = $t->tx(PUT  => 'http://example.com' => 'Hi!');
  my $tx = $t->tx(PUT  => 'http://example.com' => form => {a => 'b'});
  my $tx = $t->tx(PUT  => 'http://example.com' => json => {a => 'b'});
  my $tx = $t->tx(POST => 'http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $tx = $t->tx(
    PUT => 'http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $tx = $t->tx(
    PUT => 'http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Versatile general purpose L<Mojo::Transaction::HTTP> transaction builder for
requests, with support for L</"GENERATORS">.

  # Generate and inspect custom GET request with DNT header and content
  say $t->tx(GET => 'example.com' => {DNT => 1} => 'Bye!')->req->to_string;

  # Stream response content to STDOUT
  my $tx = $t->tx(GET => 'http://example.com');
  $tx->res->content->unsubscribe('read')->on(read => sub { say $_[1] });

  # PUT request with content streamed from file
  my $tx = $t->tx(PUT => 'http://example.com');
  $tx->req->content->asset(Mojo::Asset::File->new(path => '/foo.txt'));

The C<json> content generator uses L<Mojo::JSON> for encoding and sets the
content type to C<application/json>.

  # POST request with "application/json" content
  my $tx = $t->tx(
    POST => 'http://example.com' => json => {a => 'b', c => [1, 2, 3]});

The C<form> content generator will automatically use query parameters for
C<GET> and C<HEAD> requests.

  # GET request with query parameters
  my $tx = $t->tx(GET => 'http://example.com' => form => {a => 'b'});

For all other request methods the C<application/x-www-form-urlencoded> content
type is used.

  # POST request with "application/x-www-form-urlencoded" content
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {a => 'b', c => 'd'});

Parameters may be encoded with the C<charset> option.

  # PUT request with Shift_JIS encoded form values
  my $tx = $t->tx(
    PUT => 'example.com' => form => {a => 'b'} => charset => 'Shift_JIS');

An array reference can be used for multiple form values sharing the same name.

  # POST request with form values sharing the same name
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {a => ['b', 'c', 'd']});

A hash reference with a C<content> or C<file> value can be used to switch to
the C<multipart/form-data> content type for file uploads.

  # POST request with "multipart/form-data" content
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {mytext => {content => 'lala'}});

  # POST request with multiple files sharing the same name
  my $tx = $t->tx(POST => 'http://example.com' =>
    form => {mytext => [{content => 'first'}, {content => 'second'}]});

The C<file> value should contain the path to the file you want to upload or an
asset object, like L<Mojo::Asset::File> or L<Mojo::Asset::Memory>.

  # POST request with upload streamed from file
  my $tx = $t->tx(
    POST => 'http://example.com' => form => {mytext => {file => '/foo.txt'}});

  # POST request with upload streamed from asset
  my $asset = Mojo::Asset::Memory->new->add_chunk('lalala');
  my $tx    = $t->tx(
    POST => 'http://example.com' => form => {mytext => {file => $asset}});

A C<filename> value will be generated automatically, but can also be set
manually if necessary. All remaining values in the hash reference get merged
into the C<multipart/form-data> content as headers.

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

The C<multipart/form-data> content type can also be enforced by setting the
C<Content-Type> header manually.

  # Force "multipart/form-data"
  my $headers = {'Content-Type' => 'multipart/form-data'};
  my $tx = $t->tx(POST => 'example.com' => $headers => form => {a => 'b'});

=head2 upgrade

  my $tx = $t->upgrade(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::WebSocket> follow-up transaction for WebSocket
handshake if possible.

=head2 websocket

  my $tx = $t->websocket('ws://example.com');
  my $tx = $t->websocket('ws://example.com' => {DNT => 1} => ['v1.proto']);

Versatile L<Mojo::Transaction::HTTP> transaction builder for WebSocket
handshake requests.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
