package Mojo::Transactor;
use Mojo::Base -base;

use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::Parameters;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::Util qw/encode url_escape/;

sub form {
  my $self = shift;
  my $url  = shift;

  # Callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

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
    foreach my $name (sort keys %$form) {
      my $part = Mojo::Content::Single->new;
      my $h    = $part->headers;
      my $f    = $form->{$name};

      # File
      my $filename;
      if (ref $f eq 'HASH') {
        $filename = delete $f->{filename} || $name;
        encode $encoding, $filename if $encoding;
        url_escape $filename, $Mojo::URL::UNRESERVED;
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
          encode $encoding, $value if $encoding;
          $part->asset->add_chunk($value);
          push @parts, $part;
        }
      }

      # Content-Disposition
      encode $encoding, $name if $encoding;
      url_escape $name, $Mojo::URL::UNRESERVED;
      my $disposition = qq/form-data; name="$name"/;
      $disposition .= qq/; filename="$filename"/ if $filename;
      $h->content_disposition($disposition);
    }

    # Multipart content
    my $content = Mojo::Content::MultiPart->new;
    $headers->content_type('multipart/form-data');
    $content->headers($headers);
    $content->parts(\@parts);

    # Add content to transaction
    $req->content($content);
  }

  # Urlencoded
  else {
    $headers->content_type('application/x-www-form-urlencoded');
    $req->body($params->to_string);
  }

  return $tx unless wantarray;
  $tx, $cb;
}

sub tx {
  my $self = shift;

  # New transaction
  my $tx  = Mojo::Transaction::HTTP->new;
  my $req = $tx->req;
  $req->method(shift);
  my $url = shift;
  $url = "http://$url" unless $url =~ /^\/|\:\/\//;
  $req->url->parse($url);

  # Callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

  # Body
  $req->body(pop @_)
    if @_ & 1 == 1 && ref $_[0] ne 'HASH' || ref $_[-2] eq 'HASH';

  # Headers
  $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  return $tx unless wantarray;
  $tx, $cb;
}

sub websocket {
  my $self = shift;

  # New WebSocket
  my ($tx, $cb) = $self->tx(GET => @_);
  my $req = $tx->req;
  my $url = $req->url;
  my $abs = $url->to_abs;
  if (my $scheme = $abs->scheme) {
    $scheme = $scheme eq 'wss' ? 'https' : 'http';
    $req->url($abs->scheme($scheme));
  }

  # Handshake
  Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1)
    ->client_handshake;

  return $tx unless wantarray;
  $tx, $cb;
}

1;
__END__

=head1 NAME

Mojo::Transactor - Transaction Builder

=head1 SYNOPSIS

  use Mojo::Transactor;

  my $t  = Mojo::Transactor->new;
  my $tx = $t->tx(GET => 'http://mojolicio.us');

=head1 DESCRIPTION

L<Mojo::Transactor> is the request building framework used by
L<Mojo::UserAgent>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::Transactor> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<form>

  my $tx = $t->form('http://kraih.com/foo' => {test => 123});
  my $tx = $t->form(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123}
  );
  my $tx = $t->form(
    'http://kraih.com/foo',
    {test => 123},
    {Accept => '*/*'}
  );
  my $tx = $t->form(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {Accept => '*/*'}
  );
  my $tx = $t->form(
    'http://kraih.com/foo',
    {file => {file => '/foo/bar.txt'}}
  );
  my $tx = $t->form(
    'http://kraih.com/foo',
    {file => {content => 'lalala'}}
  );
  my $tx = $t->form(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}}
  );

Versatile L<Mojo::Transaction::HTTP> builder for form requests.

  my $tx = $t->form('http://kraih.com/foo' => {test => 123});
  $tx->res->body(sub { print $_[1] });
  $ua->start($tx);

=head2 C<tx>

  my $tx = $t->tx(GET => 'mojolicio.us');
  my $tx = $t->tx(POST => 'http://mojolicio.us');
  my $tx = $t->tx(GET => 'http://kraih.com' => {Accept => '*/*'});
  my $tx = $t->tx(
    POST => 'http://kraih.com' => {{Accept => '*/*'} => 'Hi!'
  );

Versatile general purpose L<Mojo::Transaction::HTTP> builder for requests.

  # Streaming response
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->res->body(sub { print $_[1] });
  $ua->start($tx);

  # Custom socket
  my $tx = $t->tx(GET => 'http://mojolicio.us');
  $tx->connection($socket);
  $ua->start($tx);

=head2 C<websocket>

  my $tx = $t->websocket('ws://localhost:3000');

Versatile L<Mojo::Transaction::WebSocket> builder for WebSocket handshake
requests.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
