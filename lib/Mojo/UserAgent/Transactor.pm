package Mojo::UserAgent::Transactor;
use Mojo::Base -base;

use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::Parameters;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Mojo::Util qw/encode url_escape/;

sub form {
  my ($self, $url) = (shift, shift);

  # Callback
  my $cb = pop @_ if (ref $_[-1] || '') eq 'CODE';

  # Form
  my $encoding = shift;
  my $form = ref $encoding ? $encoding : shift;
  $encoding = undef if ref $encoding;

  # Parameters
  my $params = Mojo::Parameters->new;
  $params->charset($encoding) if defined $encoding;
  my $multipart;
  for my $name (sort keys %$form) {

    # Array
    if (ref $form->{$name} eq 'ARRAY') {
      $params->append($name, $_) for @{$form->{$name}};
    }

    # Hash
    elsif (ref $form->{$name} eq 'HASH') {
      my $hash = $form->{$name};

      # Enforce "multipart/form-data"
      $multipart = 1;

      # File
      if (my $file = $hash->{file}) {

        # Upgrade
        $file = $hash->{file} = Mojo::Asset::File->new(path => $file)
          unless ref $file;

        # Filename
        $hash->{filename} ||= $file->path if $file->can('path');
      }

      # Memory
      elsif (defined(my $content = delete $hash->{content})) {
        $hash->{file} = Mojo::Asset::Memory->new->add_chunk($content);
      }

      $hash->{'Content-Type'} ||= 'application/octet-stream';
      push @{$params->params}, $name, $hash;
    }

    # Single value
    else { $params->append($name, $form->{$name}) }
  }

  # New transaction
  my $tx      = $self->tx(POST => $url);
  my $req     = $tx->req;
  my $headers = $req->headers;
  $headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  # Multipart
  $headers->content_type('multipart/form-data') if $multipart;
  my $type = $headers->content_type || '';
  if ($type eq 'multipart/form-data') {
    my $form = $params->to_hash;

    # Parts
    my @parts;
    for my $name (sort keys %$form) {
      my $part = Mojo::Content::Single->new;
      my $h    = $part->headers;
      my $f    = $form->{$name};

      # File
      my $filename;
      if (ref $f eq 'HASH') {
        $filename = delete $f->{filename} || $name;
        $filename = encode $encoding, $filename if $encoding;
        $filename = url_escape $filename, $Mojo::URL::UNRESERVED;
        $part->asset(delete $f->{file});
        $h->from_hash($f);
        push @parts, $part;
      }

      # Fields
      else {
        my $type = 'text/plain';
        $type .= qq/;charset=$encoding/ if $encoding;
        $h->content_type($type);

        # Values
        for my $value (ref $f ? @$f : ($f)) {
          $part = Mojo::Content::Single->new(headers => $h);
          $value = encode $encoding, $value if $encoding;
          $part->asset->add_chunk($value);
          push @parts, $part;
        }
      }

      # Content-Disposition
      $name = encode $encoding, $name if $encoding;
      $name = url_escape $name, $Mojo::URL::UNRESERVED;
      my $disposition = qq/form-data; name="$name"/;
      $disposition .= qq/; filename="$filename"/ if $filename;
      $h->content_disposition($disposition);
    }

    # Multipart content
    my $content = Mojo::Content::MultiPart->new;
    $headers->content_type('multipart/form-data');
    $content->headers($headers)->parts(\@parts);

    # Add content to transaction
    $req->content($content);
  }

  # Urlencoded
  else {
    $headers->content_type('application/x-www-form-urlencoded');
    $req->body($params->to_string);
  }

  return wantarray ? ($tx, $cb) : $tx;
}

# "This kid's a wonder!
#  He organized all the law suits against me into one class action suit."
sub peer {
  my ($self, $tx) = @_;

  # Peer for transaction
  my $req    = $tx->req;
  my $url    = $req->url;
  my $scheme = $url->scheme || 'http';
  my $host   = $url->ihost;
  my $port   = $url->port;
  if (my $proxy = $req->proxy) {
    $scheme = $proxy->scheme;
    $host   = $proxy->ihost;
    $port   = $proxy->port;
  }
  $port ||= $scheme eq 'https' ? 443 : 80;

  return $scheme, $host, $port;
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
  my $url = $req->url;
  return
    unless lc($req->headers->upgrade || '') eq 'websocket'
      || ($url->scheme || '') eq 'https';

  # CONNECT request
  my $new = $self->tx(CONNECT => $url->clone);
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

  # Callback
  my $cb = pop @_ if (ref $_[-1] || '') eq 'CODE';

  # Body
  $req->body(pop @_)
    if @_ & 1 == 1 && ref $_[0] ne 'HASH' || ref $_[-2] eq 'HASH';

  # Headers
  $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  return wantarray ? ($tx, $cb) : $tx;
}

# "She found my one weakness... that I'm weak!"
sub websocket {
  my $self = shift;

  # New WebSocket
  my ($tx, $cb) = $self->tx(GET => @_);
  my $req = $tx->req;
  my $abs = $req->url->to_abs;
  if (my $scheme = $abs->scheme) {
    $req->url($abs->scheme($scheme eq 'wss' ? 'https' : 'http'));
  }

  # Handshake
  Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1)
    ->client_handshake;

  return wantarray ? ($tx, $cb) : $tx;
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

=head2 C<form>

  my $tx = $t->form('kraih.com' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {mytext => {file => '/foo.txt'}});
  my $tx = $t->form('http://kraih.com' => {mytext => {content => 'lalala'}});
  my $tx = $t->form('http://kraih.com' => {
    myzip => {
      file     => Mojo::Asset::Memory->new->add_chunk('lalala'),
      filename => 'foo.zip'
    }
  });
  my $tx = $t->form('http://kraih.com' => 'UTF-8' => {a => 'b'});
  my $tx = $t->form('http://kraih.com' => {a => 'b'} => {DNT => 1});
  my $tx = $t->form('http://kraih.com', 'UTF-8', {a => 'b'}, {DNT => 1});

Versatile L<Mojo::Transaction::HTTP> builder for form requests.

  my $tx = $t->form('http://kraih.com/foo' => {a => 'b'});
  $tx->res->body(sub { say $_[1] });
  $ua->start($tx);

While the "multipart/form-data" content type will be automatically used
instead of "application/x-www-form-urlencoded" when necessary, you can also
enforce it by setting the header manually.

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

  # Streaming response
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->res->body(sub { say $_[1] });
  $ua->start($tx);

  # Custom socket
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->connection($sock);
  $ua->start($tx);

=head2 C<websocket>

  my $tx = $t->websocket('ws://localhost:3000');
  my $tx = $t->websocket('ws://localhost:3000' => {DNT => 1});

Versatile L<Mojo::Transaction::WebSocket> builder for WebSocket handshake
requests.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
