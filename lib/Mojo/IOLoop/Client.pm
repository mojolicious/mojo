package Mojo::IOLoop::Client;
use Mojo::Base 'Mojo::EventEmitter';

use Errno 'EINPROGRESS';
use IO::Socket::IP;
use Mojo::IOLoop;
use Scalar::Util 'weaken';
use Socket qw(IPPROTO_TCP SOCK_STREAM TCP_NODELAY);

# Non-blocking name resolution requires Net::DNS::Native
use constant NDN => $ENV{MOJO_NO_NDN}
  ? 0
  : eval 'use Net::DNS::Native 0.15 (); 1';
my $NDN = NDN ? Net::DNS::Native->new(pool => 5, extra_thread => 1) : undef;

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.94 (); 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# SOCKS support requires IO::Socket::Socks
use constant SOCKS => $ENV{MOJO_NO_SOCKS}
  ? 0
  : eval 'use IO::Socket::Socks 0.64 (); 1';
use constant SOCKS_READ  => SOCKS ? IO::Socket::Socks::SOCKS_WANT_READ()  : 0;
use constant SOCKS_WRITE => SOCKS ? IO::Socket::Socks::SOCKS_WANT_WRITE() : 0;

has reactor => sub { Mojo::IOLoop->singleton->reactor };

sub DESTROY { shift->_cleanup }

sub connect {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  # Timeout
  weaken $self;
  my $reactor = $self->reactor;
  $self->{timer} = $reactor->timer($args->{timeout} || 10,
    sub { $self->emit(error => 'Connect timeout') });

  # Blocking name resolution
  $_ && s/[[\]]//g for @$args{qw(address socks_address)};
  my $address = $args->{socks_address} || ($args->{address} ||= '127.0.0.1');
  return $reactor->next_tick(sub { $self && $self->_connect($args) })
    if !NDN || $args->{handle};

  # Non-blocking name resolution
  my $handle = $self->{dns} = $NDN->getaddrinfo($address, _port($args),
    {protocol => IPPROTO_TCP, socktype => SOCK_STREAM});
  $reactor->io(
    $handle => sub {
      my $reactor = shift;

      $reactor->remove($self->{dns});
      my ($err, @res) = $NDN->get_result(delete $self->{dns});
      return $self->emit(error => "Can't resolve: $err") if $err;

      $args->{addr_info} = \@res;
      $self->_connect($args);
    }
  )->watch($handle, 1, 0);
}

sub _cleanup {
  my $self = shift;
  $NDN->timedout($self->{dns}) if $self->{dns};
  return unless my $reactor = $self->reactor;
  $self->{$_} && $reactor->remove(delete $self->{$_}) for qw(dns timer handle);
  return $self;
}

sub _connect {
  my ($self, $args) = @_;

  my $handle;
  my $address = $args->{socks_address} || $args->{address};
  unless ($handle = $self->{handle} = $args->{handle}) {
    my %options = (PeerAddr => $address, PeerPort => _port($args));
    %options = (PeerAddrInfo => $args->{addr_info}) if $args->{addr_info};
    $options{Blocking} = 0;
    $options{LocalAddr} = $args->{local_address} if $args->{local_address};
    return $self->emit(error => "Can't connect: $@")
      unless $self->{handle} = $handle = IO::Socket::IP->new(%options);
  }
  $handle->blocking(0);

  $self->_wait($handle, $args);
}

sub _port { $_[0]{socks_port} || $_[0]{port} || ($_[0]{tls} ? 443 : 80) }

sub _ready {
  my ($self, $args) = @_;

  # Socket changes in between attempts and needs to be re-added for epoll/kqueue
  my $handle = $self->{handle};
  unless ($handle->connect) {
    return $self->emit(error => $!) unless $! == EINPROGRESS;
    $self->reactor->remove($handle);
    return $self->_wait($handle, $args);
  }

  return $self->emit(error => $! || 'Not connected') unless $handle->connected;

  # Disable Nagle's algorithm
  setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

  $self->_try_socks($args);
}

sub _socks {
  my ($self, $args) = @_;

  # Connected
  my $handle = $self->{handle};
  return $self->_try_tls($args) if $handle->ready;

  # Switch between reading and writing
  my $err = $IO::Socket::Socks::SOCKS_ERROR;
  if    ($err == SOCKS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == SOCKS_WRITE) { $self->reactor->watch($handle, 1, 1) }
  else                        { $self->emit(error => $err) }
}

sub _tls {
  my $self = shift;

  # Connected
  my $handle = $self->{handle};
  return $self->_cleanup->emit(connect => $handle) if $handle->connect_SSL;

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == TLS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == TLS_WRITE) { $self->reactor->watch($handle, 1, 1) }
}

sub _try_socks {
  my ($self, $args) = @_;

  my $handle = $self->{handle};
  return $self->_try_tls($args) unless $args->{socks_address};
  return $self->emit(
    error => 'IO::Socket::Socks 0.64+ required for SOCKS support')
    unless SOCKS;

  my %options = (ConnectAddr => $args->{address}, ConnectPort => $args->{port});
  @options{qw(AuthType Username Password)}
    = ('userpass', @$args{qw(socks_user socks_pass)})
    if $args->{socks_user};
  my $reactor = $self->reactor;
  $reactor->remove($handle);
  return $self->emit(error => 'SOCKS upgrade failed')
    unless IO::Socket::Socks->start_SOCKS($handle, %options);
  weaken $self;
  $reactor->io($handle => sub { $self->_socks($args) })->watch($handle, 0, 1);
}

sub _try_tls {
  my ($self, $args) = @_;

  my $handle = $self->{handle};
  return $self->_cleanup->emit(connect => $handle) unless $args->{tls};
  return $self->emit(error => 'IO::Socket::SSL 1.94+ required for TLS support')
    unless TLS;

  # Upgrade
  weaken $self;
  my %options = (
    SSL_ca_file => $args->{tls_ca}
      && -T $args->{tls_ca} ? $args->{tls_ca} : undef,
    SSL_cert_file  => $args->{tls_cert},
    SSL_error_trap => sub { $self->emit(error => $_[1]) },
    SSL_hostname   => IO::Socket::SSL->can_client_sni ? $args->{address} : '',
    SSL_key_file   => $args->{tls_key},
    SSL_startHandshake  => 0,
    SSL_verify_mode     => $args->{tls_ca} ? 0x01 : 0x00,
    SSL_verifycn_name   => $args->{address},
    SSL_verifycn_scheme => $args->{tls_ca} ? 'http' : undef
  );
  my $reactor = $self->reactor;
  $reactor->remove($handle);
  return $self->emit(error => 'TLS upgrade failed')
    unless IO::Socket::SSL->start_SSL($handle, %options);
  $reactor->io($handle => sub { $self->_tls })->watch($handle, 0, 1);
}

sub _wait {
  my ($self, $handle, $args) = @_;
  weaken $self;
  $self->reactor->io($handle => sub { $self->_ready($args) })
    ->watch($handle, 0, 1);
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

Emitted once the connection is established.

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

Low-level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Client> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 connect

  $client->connect(address => '127.0.0.1', port => 3000);

Open a socket connection to a remote host. Note that non-blocking name
resolution depends on L<Net::DNS::Native> (0.15+), SOCKS5 support on
L<IO::Socket::Socks> (0.64), and TLS support on L<IO::Socket::SSL> (1.94+).

These options are currently available:

=over 2

=item address

  address => 'mojolicious.org'

Address or host name of the peer to connect to, defaults to C<127.0.0.1>.

=item handle

  handle => $handle

Use an already prepared L<IO::Socket::IP> object.

=item local_address

  local_address => '127.0.0.1'

Local address to bind to.

=item port

  port => 80

Port to connect to, defaults to C<80> or C<443> with C<tls> option.

=item socks_address

  socks_address => '127.0.0.1'

Address or host name of SOCKS5 proxy server to use for connection.

=item socks_pass

  socks_pass => 'secr3t'

Password to use for SOCKS5 authentication.

=item socks_port

  socks_port => 9050

Port of SOCKS5 proxy server to use for connection.

=item socks_user

  socks_user => 'sri'

Username to use for SOCKS5 authentication.

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
