package Mojo::UserAgent::Transactor;
use Mojo::Base -base;

use File::Spec::Functions 'splitpath';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::Parameters;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::Util qw/encode url_escape/;

sub endpoint {
  my ($self, $tx) = @_;

  # Basic endpoint
  my $req    = $tx->req;
  my $url    = $req->url;
  my $scheme = $url->scheme || 'http';
  my $host   = $url->ihost;
  my $port   = $url->port || ($scheme eq 'https' ? 443 : 80);

  # Proxy for normal HTTP requests
  return $scheme eq 'http' && lc($req->headers->upgrade || '') ne 'websocket'
    ? $self->_proxy($tx, $scheme, $host, $port)
    : ($scheme, $host, $port);
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
      $multipart = 1;

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
  my $tx      = $self->tx(POST => $url);
  my $req     = $tx->req;
  my $headers = $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  # Multipart
  $headers->content_type('multipart/form-data') if $multipart;
  if (($headers->content_type || '') eq 'multipart/form-data') {
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

# "This kid's a wonder!
#  He organized all the law suits against me into one class action suit."
sub peer {
  my ($self, $tx) = @_;
  return $self->_proxy($tx, $self->endpoint($tx));
}

# "America's health care system is second only to Japan...
#  Canada, Sweden, Great Britain... well, all of Europe.
#  But you can thank your lucky stars we don't live in Paraguay!"
sub proxy_connect {
  my ($self, $old) = @_;

  # No proxy
  my $req = $old->req;
  return unless my $proxy = $req->proxy;

  # WebSocket and/or HTTPS
  my $url     = $req->url;
  my $upgrade = lc($req->headers->upgrade || '');
  my $scheme  = $url->scheme;
  return unless $upgrade eq 'websocket' || $scheme eq 'https';

  # CONNECT request
  my $new = $self->tx(CONNECT => $url->clone->userinfo(undef));
  $new->req->proxy($proxy);

  return $new;
}

sub redirect {
  my ($self, $old) = @_;

  # Commonly used codes
  my $res = $old->res;
  my $code = $res->code || 0;
  return unless $code ~~ [301, 302, 303, 307];

  # Fix broken location without authority and/or scheme
  return unless my $location = $res->headers->location;
  $location = Mojo::URL->new($location);
  my $req = $old->req;
  my $url = $req->url;
  $location->authority($url->authority) unless $location->authority;
  $location->scheme($url->scheme)       unless $location->scheme;

  # Clone request if necessary
  my $new    = Mojo::Transaction::HTTP->new;
  my $method = $req->method;
  if ($code ~~ [301, 307]) {
    return unless $req = $req->clone;
    $new->req($req);
    $req->headers->remove('Host')->remove('Cookie')->remove('Referer');
  }
  else { $method = 'GET' unless $method ~~ [qw/GET HEAD/] }
  $new->req->method($method)->url($location);
  return $new->previous($old);
}

# "If he is so smart, how come he is dead?"
sub tx {
  my $self = shift;

  # New transaction
  my $tx  = Mojo::Transaction::HTTP->new;
  my $req = $tx->req;
  $req->method(shift);
  my $url = shift;
  $url = "http://$url" unless $url =~ m#^/|\://#;
  ref $url ? $req->url($url) : $req->url->parse($url);

  # Body
  $req->body(pop)
    if @_ & 1 == 1 && ref $_[0] ne 'HASH' || ref $_[-2] eq 'HASH';

  # Headers
  $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  return $tx;
}

# "She found my one weakness... that I'm weak!"
sub websocket {
  my $self = shift;

  # New WebSocket
  my $tx  = $self->tx(GET => @_);
  my $req = $tx->req;
  my $abs = $req->url->to_abs;
  if (my $scheme = $abs->scheme) {
    $req->url($abs->scheme($scheme eq 'wss' ? 'https' : 'http'));
  }

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
      $filename = url_escape $filename, "^$Mojo::URL::UNRESERVED";
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
    $name = url_escape $name, "^$Mojo::URL::UNRESERVED";
    my $disposition = qq/form-data; name="$name"/;
    $disposition .= qq/; filename="$filename"/ if $filename;
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
__END__

=head1 NAME

Mojo::UserAgent::Transactor - User agent transactor

=head1 SYNOPSIS

  use Mojo::UserAgent::Transactor;

  my $t  = Mojo::UserAgent::Transactor->new;
  my $tx = $t->tx(GET => 'http://mojolicio.us');

=head1 DESCRIPTION

L<Mojo::UserAgent::Transactor> is the transaction building and manipulation
framework used by L<Mojo::UserAgent>.

=head1 METHODS

L<Mojo::UserAgent::Transactor> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<endpoint>

  my ($scheme, $host, $port) = $t->endpoint($tx);

Actual endpoint for transaction.

=head2 C<form>

  my $tx = $t->form('kraih.com' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => ['b', 'c', 'd']});
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

  # Inspect generated request
  say $t->form('mojolicio.us' => {a => [1, 2, 3]})->req->to_string;

  # Streaming multipart file upload
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

=head2 C<peer>

  my ($scheme, $host, $port) = $t->peer($tx);

Actual peer for transaction.

=head2 C<proxy_connect>

  my $tx = $t->proxy_connect($old);

Build L<Mojo::Transaction::HTTP> proxy connect request for transaction if
possible.

=head2 C<redirect>

  my $tx = $t->redirect($old);

Build L<Mojo::Transaction::HTTP> followup request for C<301>, C<302>, C<303>
or C<307> redirect response if possible.

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
