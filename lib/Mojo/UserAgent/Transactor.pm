package Mojo::UserAgent::Transactor;
use Mojo::Base -base;

use File::Spec::Functions 'splitpath';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::JSON;
use Mojo::Parameters;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::Util qw(encode url_escape);

sub endpoint {
  my ($self, $tx) = @_;

  # Basic endpoint
  my $req    = $tx->req;
  my $url    = $req->url;
  my $scheme = $url->scheme || 'http';
  my $host   = $url->ihost;
  my $port   = $url->port || ($scheme eq 'https' ? 443 : 80);

  # Proxy for normal HTTP requests
  return $self->_proxy($tx, $scheme, $host, $port)
    if $scheme eq 'http' && lc($req->headers->upgrade || '') ne 'websocket';

  return $scheme, $host, $port;
}

sub form {
  my ($self, $url) = (shift, shift);

  # Form
  my $encoding = shift;
  my $form = ref $encoding ? $encoding : shift;
  $encoding = undef if ref $encoding;

  # Parameters
  my $p = Mojo::Parameters->new;
  $p->charset($encoding) if defined $encoding;
  my $multipart;
  for my $name (sort keys %$form) {
    my $value = $form->{$name};

    # Array
    if (ref $value eq 'ARRAY') { $p->append($name, $_) for @$value }

    # Hash
    elsif (ref $value eq 'HASH') {

      # Enforce "multipart/form-data"
      $multipart++;

      # File
      if (my $file = $value->{file}) {
        $value->{file} = Mojo::Asset::File->new(path => $file) if !ref $file;
        $value->{filename} ||= (splitpath($value->{file}->path))[2]
          if $value->{file}->isa('Mojo::Asset::File');
      }

      # Memory
      elsif (defined(my $content = delete $value->{content})) {
        $value->{file} = Mojo::Asset::Memory->new->add_chunk($content);
      }

      push @{$p->params}, $name, $value;
    }

    # Single value
    else { $p->append($name, $value) }
  }

  # New transaction
  my $tx = $self->tx(POST => $url, @_);

  # Multipart
  my $req     = $tx->req;
  my $headers = $req->headers;
  $headers->content_type('multipart/form-data') if $multipart;
  if (($headers->content_type // '') eq 'multipart/form-data') {
    my $parts = $self->_multipart($encoding, $p->to_hash);
    $req->content(
      Mojo::Content::MultiPart->new(headers => $headers, parts => $parts));
  }

  # Urlencoded
  else {
    $headers->content_type('application/x-www-form-urlencoded');
    $req->body($p->to_string);
  }

  return $tx;
}

sub json {
  my ($self, $url, $data) = (shift, shift, shift);
  my $tx = $self->tx(POST => $url, @_, Mojo::JSON->new->encode($data));
  my $headers = $tx->req->headers;
  $headers->content_type('application/json') unless $headers->content_type;
  return $tx;
}

sub peer {
  my ($self, $tx) = @_;
  return $self->_proxy($tx, $self->endpoint($tx));
}

sub proxy_connect {
  my ($self, $old) = @_;

  # No proxy
  my $req = $old->req;
  return undef unless my $proxy = $req->proxy;

  # WebSocket and/or HTTPS
  my $url     = $req->url;
  my $upgrade = lc($req->headers->upgrade || '');
  my $scheme  = $url->scheme;
  return undef unless $upgrade eq 'websocket' || $scheme eq 'https';

  # CONNECT request
  my $new = $self->tx(CONNECT => $url->clone->userinfo(undef));
  $new->req->proxy($proxy);

  return $new;
}

sub redirect {
  my ($self, $old) = @_;

  # Commonly used codes
  my $res = $old->res;
  my $code = $res->code // '';
  return undef unless grep { $_ eq $code } 301, 302, 303, 307, 308;

  # Fix broken location without authority and/or scheme
  return unless my $location = $res->headers->location;
  $location = Mojo::URL->new($location);
  $location = $location->base($old->req->url)->to_abs unless $location->scheme;

  # Clone request if necessary
  my $new    = Mojo::Transaction::HTTP->new;
  my $req    = $old->req;
  my $method = $req->method;
  if (grep { $_ eq $code } 301, 307, 308) {
    return undef unless my $req = $req->clone;
    $new->req($req);
    $req->headers->remove('Host')->remove('Cookie')->remove('Referer');
  }
  elsif ($method ne 'HEAD') { $method = 'GET' }
  $new->req->method($method)->url($location);
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

  # Headers
  $req->headers->from_hash(shift) if ref $_[0] eq 'HASH';

  # Body
  $req->body(shift) if @_;

  return $tx;
}

sub websocket {
  my $self = shift;

  # New WebSocket transaction
  my $tx     = $self->tx(GET => @_);
  my $req    = $tx->req;
  my $abs    = $req->url->to_abs;
  my $scheme = $abs->scheme;
  $req->url($abs->scheme($scheme eq 'wss' ? 'https' : 'http')) if $scheme;

  # Handshake
  Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1)
    ->client_handshake;

  return $tx;
}

sub _multipart {
  my ($self, $encoding, $form) = @_;

  # Parts
  my @parts;
  for my $name (sort keys %$form) {
    my $values = $form->{$name};
    my $part   = Mojo::Content::Single->new;

    # File
    my $filename;
    my $headers = $part->headers;
    if (ref $values eq 'HASH') {
      $filename = delete $values->{filename} || $name;
      $filename = encode $encoding, $filename if $encoding;
      $filename = url_escape $filename, '^A-Za-z0-9\-._~';
      push @parts, $part->asset(delete $values->{file});
      $headers->from_hash($values);
    }

    # Fields
    else {
      for my $value (ref $values ? @$values : ($values)) {
        push @parts, $part = Mojo::Content::Single->new(headers => $headers);
        $value = encode $encoding, $value if $encoding;
        $part->asset->add_chunk($value);
      }
    }

    # Content-Disposition
    $name = encode $encoding, $name if $encoding;
    $name = url_escape $name, '^A-Za-z0-9\-._~';
    my $disposition = qq{form-data; name="$name"};
    $disposition .= qq{; filename="$filename"} if $filename;
    $headers->content_disposition($disposition);
  }

  return \@parts;
}

sub _proxy {
  my ($self, $tx, $scheme, $host, $port) = @_;

  # Update with proxy information
  if (my $proxy = $tx->req->proxy) {
    $scheme = $proxy->scheme;
    $host   = $proxy->ihost;
    $port   = $proxy->port || ($scheme eq 'https' ? 443 : 80);
  }

  return $scheme, $host, $port;
}

1;

=head1 NAME

Mojo::UserAgent::Transactor - User agent transactor

=head1 SYNOPSIS

  use Mojo::UserAgent::Transactor;

  # Simple GET request
  my $t = Mojo::UserAgent::Transactor->new;
  say $t->tx(GET => 'http://mojolicio.us')->req->to_string;

  # PATCH request with "Do Not Track" header and content
  say $t->tx(PATCH => 'mojolicio.us' => {DNT => 1} => 'Hi!')->req->to_string;

  # POST request with form data
  say $t->form('http://kraih.com' => {a => [1, 2], b => 3})->req->to_string;

  # POST request with JSON data
  say $t->json('http://kraih.com' => {a => [1, 2], b => 3})->req->to_string;

=head1 DESCRIPTION

L<Mojo::UserAgent::Transactor> is the transaction building and manipulation
framework used by L<Mojo::UserAgent>.

=head1 METHODS

L<Mojo::UserAgent::Transactor> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<endpoint>

  my ($scheme, $host, $port) = $t->endpoint(Mojo::Transaction::HTTP->new);

Actual endpoint for transaction.

=head2 C<form>

  my $tx = $t->form('kraih.com' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => [qw(b c d)]});
  my $tx = $t->form('http://kraih.com' => {mytext => {file => '/foo.txt'}});
  my $tx = $t->form('http://kraih.com' => {mytext => {content => 'lalala'}});
  my $tx = $t->form('http://kraih.com' => {
    myzip => {
      file     => Mojo::Asset::Memory->new->add_chunk('lalala'),
      filename => 'foo.zip',
      DNT      => 1
    }
  });
  my $tx = $t->form('http://kraih.com' => 'UTF-8' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => 'b'} => {DNT => 1});
  my $tx = $t->form('http://kraih.com', 'UTF-8', {a => 'b'}, {DNT => 1});

Versatile L<Mojo::Transaction::HTTP> builder for C<POST> requests with form
data.

  # Multipart upload with filename
  my $tx = $t->form(
    'mojolicio.us' => {fun => {content => 'Hello!', filename => 'test.txt'}});

  # Multipart upload streamed from file
  my $tx = $t->form('mojolicio.us' => {fun => {file => '/etc/passwd'}});

While the "multipart/form-data" content type will be automatically used
instead of "application/x-www-form-urlencoded" when necessary, you can also
enforce it by setting the header manually.

  # Force multipart
  my $tx = $t->form(
    'http://kraih.com/foo',
    {a => 'b'},
    {'Content-Type' => 'multipart/form-data'}
  );

=head2 C<json>

  my $tx = $t->json('kraih.com' => {a => 'b'});
  my $tx = $t->json('http://kraih.com' => [1, 2, 3]);
  my $tx = $t->json('http://kraih.com' => {a => 'b'} => {DNT => 1});
  my $tx = $t->json('http://kraih.com' => [1, 2, 3] => {DNT => 1});

Versatile L<Mojo::Transaction::HTTP> builder for C<POST> requests with JSON
data.

  # Change method
  my $tx = $t->json('mojolicio.us/hello', {hello => 'world'});
  $tx->req->method('PATCH');

=head2 C<peer>

  my ($scheme, $host, $port) = $t->peer(Mojo::Transaction::HTTP->new);

Actual peer for transaction.

=head2 C<proxy_connect>

  my $tx = $t->proxy_connect(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::HTTP> proxy connect request for transaction if
possible.

=head2 C<redirect>

  my $tx = $t->redirect(Mojo::Transaction::HTTP->new);

Build L<Mojo::Transaction::HTTP> followup request for C<301>, C<302>, C<303>,
C<307> or C<308> redirect response if possible.

=head2 C<tx>

  my $tx = $t->tx(GET  => 'kraih.com');
  my $tx = $t->tx(POST => 'http://kraih.com');
  my $tx = $t->tx(GET  => 'http://kraih.com' => {DNT => 1});
  my $tx = $t->tx(PUT  => 'http://kraih.com' => 'Hi!');
  my $tx = $t->tx(POST => 'http://kraih.com' => {DNT => 1} => 'Hi!');

Versatile general purpose L<Mojo::Transaction::HTTP> builder for requests.

  # Inspect generated request
  say $t->tx(GET => 'mojolicio.us' => {DNT => 1} => 'Bye!')->req->to_string;

  # Streaming response
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->res->body(sub { say $_[1] });

  # Custom socket
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->connection($sock);

=head2 C<websocket>

  my $tx = $t->websocket('ws://localhost:3000');
  my $tx = $t->websocket('ws://localhost:3000' => {DNT => 1});

Versatile L<Mojo::Transaction::WebSocket> builder for WebSocket handshake
requests.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
