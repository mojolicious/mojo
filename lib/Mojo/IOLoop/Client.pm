package Mojo::IOLoop::Client;
use Mojo::Base 'Mojo::EventEmitter';

use Errno 'EINPROGRESS';
use IO::Socket::INET;
use Scalar::Util 'weaken';
use Socket qw(IPPROTO_TCP SO_ERROR TCP_NODELAY);

# IPv6 support requires IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval 'use IO::Socket::IP 0.16 (); 1';

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS} ? 0
  : eval(IPV6 ? 'use IO::Socket::SSL 1.75 (); 1'
  : 'use IO::Socket::SSL 1.75 "inet4"; 1');
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

has reactor => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->reactor;
};

sub DESTROY { shift->_cleanup }

sub connect {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};
  weaken $self;
  $self->{delay} = $self->reactor->timer(0 => sub { $self->_connect($args) });
}

sub _cleanup {
  my $self = shift;
  return $self unless my $reactor = $self->reactor;
  $self->{$_} && $reactor->remove(delete $self->{$_})
    for qw(delay timer handle);
  return $self;
}

sub _connect {
  my ($self, $args) = @_;

  my $handle;
  my $reactor = $self->reactor;
  my $address = $args->{address} ||= 'localhost';
  unless ($handle = $self->{handle} = $args->{handle}) {
    my %options = (
      Blocking => 0,
      PeerAddr => $address eq 'localhost' ? '127.0.0.1' : $address,
      PeerPort => $args->{port} || ($args->{tls} ? 443 : 80)
    );
    $options{LocalAddr} = $args->{local_address} if $args->{local_address};
    $options{PeerAddr} =~ s/[\[\]]//g if $options{PeerAddr};
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
    return $self->emit(error => "Couldn't connect: $@")
      unless $self->{handle} = $handle = $class->new(%options);

    # Timeout
    $self->{timer} = $reactor->timer($args->{timeout} || 10,
      sub { $self->emit(error => 'Connect timeout') });
  }
  $handle->blocking(0);

  # Wait for handle to become writable
  weaken $self;
  $reactor->io($handle => sub { $self->_try($args) })->watch($handle, 0, 1);
}

sub _tls {
  my $self = shift;

  # Connected
  my $handle = $self->{handle};
  return $self->_cleanup->emit_safe(connect => $handle)
    if $handle->connect_SSL;

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == TLS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == TLS_WRITE) { $self->reactor->watch($handle, 1, 1) }
}

sub _try {
  my ($self, $args) = @_;

  # Retry or handle exceptions
  my $handle = $self->{handle};
  return $! == EINPROGRESS ? undef : $self->emit(error => $!)
    if IPV6 && !$handle->connect;
  return $self->emit(error => $! = $handle->sockopt(SO_ERROR))
    if !IPV6 && !$handle->connected;

  # Disable Nagle's algorithm
  setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

  return $self->_cleanup->emit_safe(connect => $handle)
    if !$args->{tls} || $handle->isa('IO::Socket::SSL');
  return $self->emit(error => 'IO::Socket::SSL 1.75 required for TLS support')
    unless TLS;

  # Upgrade
  weaken $self;
  my %options = (
    SSL_ca_file => $args->{tls_ca}
      && -T $args->{tls_ca} ? $args->{tls_ca} : undef,
    SSL_cert_file       => $args->{tls_cert},
    SSL_error_trap      => sub { $self->_cleanup->emit(error => $_[1]) },
    SSL_hostname        => $args->{address},
    SSL_key_file        => $args->{tls_key},
    SSL_startHandshake  => 0,
    SSL_verify_mode     => $args->{tls_ca} ? 0x01 : 0x00,
    SSL_verifycn_name   => $args->{address},
    SSL_verifycn_scheme => $args->{tls_ca} ? 'http' : undef
  );
  my $reactor = $self->reactor;
  $reactor->remove($handle);
  return $self->emit(error => 'TLS upgrade failed')
    unless $handle = IO::Socket::SSL->start_SSL($handle, %options);
  $reactor->io($handle => sub { $self->_tls })->watch($handle, 0, 1);
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Client - Non-blocking TCP client

=head1 SYNOPSIS

  use Mojo::IOLoop::Client;

  # Create socket connection
  my $client = Mojo::IOLoop::Client->new;
  $client->on(connect => sub {
    my ($client, $handle) = @_;
    ...
  });
  $client->on(error => sub {
    my ($client, $err) = @_;
    ...
  });
  $client->connect(address => 'example.com', port => 80);

  # Start reactor if necessary
  $client->reactor->start unless $client->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Client> opens TCP connections for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Client> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 connect

  $client->on(connect => sub {
    my ($client, $handle) = @_;
    ...
  });

Emitted safely once the connection is established.

=head2 error

  $client->on(error => sub {
    my ($client, $err) = @_;
    ...
  });

Emitted if an error occurs on the connection, fatal if unhandled.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Client> implements the following attributes.

=head2 reactor

  my $reactor = $client->reactor;
  $client     = $client->reactor(Mojo::Reactor::Poll->new);

Low level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Client> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 connect

  $client->connect(address => '127.0.0.1', port => 3000);

Open a socket connection to a remote host. Note that TLS support depends on
L<IO::Socket::SSL> (1.75+) and IPv6 support on L<IO::Socket::IP> (0.16+).

These options are currently available:

=over 2

=item address

  address => 'mojolicio.us'

Address or host name of the peer to connect to, defaults to C<localhost>.

=item handle

  handle => $handle

Use an already prepared handle.

=item local_address

  local_address => '127.0.0.1'

Local address to bind to.

=item port

  port => 80

Port to connect to, defaults to C<80> or C<443> with C<tls> option.

=item timeout

  timeout => 15

Maximum amount of time in seconds establishing connection may take before
getting canceled, defaults to C<10>.

=item tls

  tls => 1

Enable TLS.

=item tls_ca

  tls_ca => '/etc/tls/ca.crt'

Path to TLS certificate authority file. Also activates hostname verification.

=item tls_cert

  tls_cert => '/etc/tls/client.crt'

Path to the TLS certificate file.

=item tls_key

  tls_key => '/etc/tls/client.key'

Path to the TLS key file.

=back

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
