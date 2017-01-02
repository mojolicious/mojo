package Mojo::IOLoop::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use IO::Socket::IP;
use Mojo::File 'path';
use Mojo::IOLoop;
use Scalar::Util 'weaken';
use Socket qw(IPPROTO_TCP TCP_NODELAY);

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.94 (); 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# To regenerate the certificate run this command (18.04.2012)
# openssl req -new -x509 -keyout server.key -out server.crt -nodes -days 7300
my $CERT = path(__FILE__)->dirname->child('resources', 'server.crt')->to_string;
my $KEY  = path(__FILE__)->dirname->child('resources', 'server.key')->to_string;

has reactor => sub { Mojo::IOLoop->singleton->reactor };

sub DESTROY {
  my $self = shift;
  $ENV{MOJO_REUSE} =~ s/(?:^|\,)\Q$self->{reuse}\E// if $self->{reuse};
  return unless my $reactor = $self->reactor;
  $self->stop if $self->{handle};
  $reactor->remove($_) for values %{$self->{handles}};
}

sub generate_port {
  IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1')->sockport;
}

sub handle { shift->{handle} }

sub is_accepting { !!shift->{active} }

sub listen {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  # Look for reusable file descriptor
  my $address = $args->{address} || '0.0.0.0';
  my $port = $args->{port};
  $ENV{MOJO_REUSE} ||= '';
  my $fd;
  $fd = $1 if $port && $ENV{MOJO_REUSE} =~ /(?:^|\,)\Q$address:$port\E:(\d+)/;

  # Allow file descriptor inheritance
  local $^F = 1023;

  # Reuse file descriptor
  my $handle;
  if (defined $fd) {
    $handle = IO::Socket::IP->new_from_fd($fd, 'r')
      or croak "Can't open file descriptor $fd: $!";
  }

  # New socket
  else {
    my %options = (
      Listen => $args->{backlog} // SOMAXCONN,
      LocalAddr => $address,
      ReuseAddr => 1,
      ReusePort => $args->{reuse},
      Type      => SOCK_STREAM
    );
    $options{LocalPort} = $port if $port;
    $options{LocalAddr} =~ s/[\[\]]//g;
    $handle = IO::Socket::IP->new(%options)
      or croak "Can't create listen socket: $@";
    $fd = fileno $handle;
    my $reuse = $self->{reuse} = join ':', $address, $handle->sockport, $fd;
    $ENV{MOJO_REUSE} .= length $ENV{MOJO_REUSE} ? ",$reuse" : "$reuse";
  }
  $handle->blocking(0);
  @$self{qw(handle single_accept)} = ($handle, $args->{single_accept});

  return unless $args->{tls};
  croak "IO::Socket::SSL 1.94+ required for TLS support" unless TLS;

  weaken $self;
  my $tls = $self->{tls} = {
    SSL_cert_file => $args->{tls_cert} || $CERT,
    SSL_error_trap => sub {
      return unless my $handle = delete $self->{handles}{shift()};
      $self->reactor->remove($handle);
      close $handle;
    },
    SSL_honor_cipher_order => 1,
    SSL_key_file           => $args->{tls_key} || $KEY,
    SSL_startHandshake     => 0,
    SSL_verify_mode => $args->{tls_verify} // ($args->{tls_ca} ? 0x03 : 0x00)
  };
  $tls->{SSL_ca_file} = $args->{tls_ca}
    if $args->{tls_ca} && -T $args->{tls_ca};
  $tls->{SSL_cipher_list} = $args->{tls_ciphers} if $args->{tls_ciphers};
  $tls->{SSL_version}     = $args->{tls_version} if $args->{tls_version};
}

sub port { shift->{handle}->sockport }

sub start {
  my $self = shift;
  weaken $self;
  ++$self->{active}
    and $self->reactor->io($self->{handle} => sub { $self->_accept });
}

sub stop { delete($_[0]{active}) and $_[0]->reactor->remove($_[0]{handle}) }

sub _accept {
  my $self = shift;

  # Greedy accept
  my $accepted = 0;
  while ($self->{active} && !($self->{single_accept} && $accepted++)) {
    return unless my $handle = $self->{handle}->accept;
    $handle->blocking(0);

    # Disable Nagle's algorithm
    setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

    # Start TLS handshake
    $self->emit(accept => $handle) and next unless my $tls = $self->{tls};
    $self->_handshake($self->{handles}{$handle} = $handle)
      if $handle = IO::Socket::SSL->start_SSL($handle, %$tls, SSL_server => 1);
  }
}

sub _handshake {
  my ($self, $handle) = @_;
  weaken $self;
  $self->reactor->io($handle => sub { $self->_tls($handle) });
}

sub _tls {
  my ($self, $handle) = @_;

  # Accepted
  if ($handle->accept_SSL) {
    $self->reactor->remove($handle);
    return $self->emit(accept => delete $self->{handles}{$handle});
  }

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == TLS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == TLS_WRITE) { $self->reactor->watch($handle, 1, 1) }
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Server - Non-blocking TCP server

=head1 SYNOPSIS

  use Mojo::IOLoop::Server;

  # Create listen socket
  my $server = Mojo::IOLoop::Server->new;
  $server->on(accept => sub {
    my ($server, $handle) = @_;
    ...
  });
  $server->listen(port => 3000);

  # Start and stop accepting connections
  $server->start;
  $server->stop;

  # Start reactor if necessary
  $server->reactor->start unless $server->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Server> accepts TCP connections for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Server> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 accept

  $server->on(accept => sub {
    my ($server, $handle) = @_;
    ...
  });

Emitted for each accepted connection.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Server> implements the following attributes.

=head2 reactor

  my $reactor = $server->reactor;
  $server     = $server->reactor(Mojo::Reactor::Poll->new);

Low-level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Server> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 generate_port

  my $port = $server->generate_port;

Find a free TCP port, primarily used for tests.

=head2 handle

  my $handle = $server->handle;

Get handle for server, usually an L<IO::Socket::IP> object.

=head2 is_accepting

  my $bool = $server->is_accepting;

Check if connections are currently being accepted.

=head2 listen

  $server->listen(port => 3000);

Create a new listen socket. Note that TLS support depends on L<IO::Socket::SSL>
(1.94+).

These options are currently available:

=over 2

=item address

  address => '127.0.0.1'

Local address to listen on, defaults to C<0.0.0.0>.

=item backlog

  backlog => 128

Maximum backlog size, defaults to C<SOMAXCONN>.

=item port

  port => 80

Port to listen on, defaults to a random port.

=item reuse

  reuse => 1

Allow multiple servers to use the same port with the C<SO_REUSEPORT> socket
option.

=item single_accept

  single_accept => 1

Only accept one connection at a time.

=item tls

  tls => 1

Enable TLS.

=item tls_ca

  tls_ca => '/etc/tls/ca.crt'

Path to TLS certificate authority file.

=item tls_cert

  tls_cert => '/etc/tls/server.crt'
  tls_cert => {'mojolicious.org' => '/etc/tls/mojo.crt'}

Path to the TLS cert file, defaults to a built-in test certificate.

=item tls_ciphers

  tls_ciphers => 'AES128-GCM-SHA256:RC4:HIGH:!MD5:!aNULL:!EDH'

TLS cipher specification string. For more information about the format see
L<https://www.openssl.org/docs/manmaster/apps/ciphers.html#CIPHER-STRINGS>.

=item tls_key

  tls_key => '/etc/tls/server.key'
  tls_key => {'mojolicious.org' => '/etc/tls/mojo.key'}

Path to the TLS key file, defaults to a built-in test key.

=item tls_verify

  tls_verify => 0x00

TLS verification mode, defaults to C<0x03> if a certificate authority file has
been provided, or C<0x00>.

=item tls_version

  tls_version => 'TLSv1_2'

TLS protocol version.

=back

=head2 port

  my $port = $server->port;

Get port this server is listening on.

=head2 start

  $server->start;

Start or resume accepting connections.

=head2 stop

  $server->stop;

Stop accepting connections.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
