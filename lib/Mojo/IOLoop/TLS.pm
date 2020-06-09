package Mojo::IOLoop::TLS;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::File qw(curfile);
use Mojo::IOLoop;
use Scalar::Util qw(weaken);

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS} ? 0 : eval { require IO::Socket::SSL; IO::Socket::SSL->VERSION('2.009'); 1 };
use constant READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

has reactor => sub { Mojo::IOLoop->singleton->reactor }, weak => 1;

# To regenerate the certificate run this command (28.06.2019)
# openssl req -x509 -newkey rsa:4096 -nodes -sha256 -out server.crt \
#   -keyout server.key -days 7300 -subj '/CN=localhost'
my $CERT = curfile->sibling('resources', 'server.crt')->to_string;
my $KEY  = curfile->sibling('resources', 'server.key')->to_string;

sub DESTROY { shift->_cleanup }

sub can_tls {TLS}

sub negotiate {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  return $self->emit(error => 'IO::Socket::SSL 2.009+ required for TLS support') unless TLS;

  my $handle = $self->{handle};
  return $self->emit(error => $IO::Socket::SSL::SSL_ERROR)
    unless IO::Socket::SSL->start_SSL($handle, %{$self->_expand($args)});
  $self->reactor->io($handle => sub { $self->_tls($handle, $args->{server}) });
}

sub new { shift->SUPER::new(handle => shift) }

sub _cleanup {
  my $self = shift;
  return undef unless my $reactor = $self->reactor;
  $reactor->remove($self->{handle}) if $self->{handle};
  return $self;
}

sub _expand {
  my ($self, $args) = @_;

  weaken $self;
  my $tls = {SSL_error_trap => sub { $self->_cleanup->emit(error => $_[1]) }, SSL_startHandshake => 0};
  $tls->{SSL_alpn_protocols} = $args->{tls_protocols} if $args->{tls_protocols};
  $tls->{SSL_ca_file}        = $args->{tls_ca}        if $args->{tls_ca} && -T $args->{tls_ca};
  $tls->{SSL_cert_file}      = $args->{tls_cert}      if $args->{tls_cert};
  $tls->{SSL_cipher_list}    = $args->{tls_ciphers}   if $args->{tls_ciphers};
  $tls->{SSL_key_file}       = $args->{tls_key}       if $args->{tls_key};
  $tls->{SSL_server}         = $args->{server}        if $args->{server};
  $tls->{SSL_verify_mode}    = $args->{tls_verify}    if defined $args->{tls_verify};
  $tls->{SSL_version}        = $args->{tls_version}   if $args->{tls_version};

  if ($args->{server}) {
    $tls->{SSL_cert_file} ||= $CERT;
    $tls->{SSL_key_file}  ||= $KEY;
  }
  else {
    $tls->{SSL_hostname}      = IO::Socket::SSL->can_client_sni ? $args->{address} : '';
    $tls->{SSL_verifycn_name} = $args->{address};
  }

  return $tls;
}

sub _tls {
  my ($self, $handle, $server) = @_;

  # Switch between reading and writing
  if (!($server ? $handle->accept_SSL : $handle->connect_SSL)) {
    my $err = $IO::Socket::SSL::SSL_ERROR;
    if    ($err == READ)  { $self->reactor->watch($handle, 1, 0) }
    elsif ($err == WRITE) { $self->reactor->watch($handle, 1, 1) }
  }

  else { $self->_cleanup->emit(upgrade => delete $self->{handle}) }
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::TLS - Non-blocking TLS handshake

=head1 SYNOPSIS

  use Mojo::IOLoop::TLS;

  # Negotiate TLS
  my $tls = Mojo::IOLoop::TLS->new($old_handle);
  $tls->on(upgrade => sub {
    my ($tls, $new_handle) = @_;
    ...
  });
  $tls->on(error => sub {
    my ($tls, $err) = @_;
    ...
  });
  $tls->negotiate(server => 1, tls_version => 'TLSv1_2');

  # Start reactor if necessary
  $tls->reactor->start unless $tls->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::TLS> negotiates TLS for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::TLS> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

=head2 upgrade

  $tls->on(upgrade => sub {
    my ($tls, $handle) = @_;
    ...
  });

Emitted once TLS has been negotiated.

=head2 error

  $tls->on(error => sub {
    my ($tls, $err) = @_;
    ...
  });

Emitted if an error occurs during negotiation, fatal if unhandled.

=head1 ATTRIBUTES

L<Mojo::IOLoop::TLS> implements the following attributes.

=head2 reactor

  my $reactor = $tls->reactor;
  $tls        = $tls->reactor(Mojo::Reactor::Poll->new);

Low-level event reactor, defaults to the C<reactor> attribute value of the global L<Mojo::IOLoop> singleton. Note that
this attribute is weakened.

=head1 METHODS

L<Mojo::IOLoop::TLS> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 can_tls

  my $bool = Mojo::IOLoop::TLS->can_tls;

True if L<IO::Socket::SSL> 2.009+ is installed and TLS support enabled.

=head2 negotiate

  $tls->negotiate(server => 1, tls_version => 'TLSv1_2');
  $tls->negotiate({server => 1, tls_version => 'TLSv1_2'});

Negotiate TLS.

These options are currently available:

=over 2

=item server

  server => 1

Negotiate TLS from the server-side, defaults to the client-side.

=item tls_ca

  tls_ca => '/etc/tls/ca.crt'

Path to TLS certificate authority file.

=item tls_cert

  tls_cert => '/etc/tls/server.crt'
  tls_cert => {'mojolicious.org' => '/etc/tls/mojo.crt'}

Path to the TLS cert file, defaults to a built-in test certificate on the server-side.

=item tls_ciphers

  tls_ciphers => 'AES128-GCM-SHA256:RC4:HIGH:!MD5:!aNULL:!EDH'

TLS cipher specification string. For more information about the format see
L<https://www.openssl.org/docs/manmaster/apps/ciphers.html#CIPHER-STRINGS>.

=item tls_key

  tls_key => '/etc/tls/server.key'
  tls_key => {'mojolicious.org' => '/etc/tls/mojo.key'}

Path to the TLS key file, defaults to a built-in test key on the server-side.

=item tls_protocols

  tls_protocols => ['foo', 'bar']

ALPN protocols to negotiate.

=item tls_verify

  tls_verify => 0x00

TLS verification mode.

=item tls_version

  tls_version => 'TLSv1_2'

TLS protocol version.

=back

=head2 new

  my $tls = Mojo::IOLoop::TLS->new($handle);

Construct a new L<Mojo::IOLoop::Stream> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
