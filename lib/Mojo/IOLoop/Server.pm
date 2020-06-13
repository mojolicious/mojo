package Mojo::IOLoop::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp qw(croak);
use IO::Socket::IP;
use IO::Socket::UNIX;
use Mojo::File qw(path);
use Mojo::IOLoop;
use Mojo::IOLoop::TLS;
use Scalar::Util qw(weaken);
use Socket qw(IPPROTO_TCP TCP_NODELAY);

has reactor => sub { Mojo::IOLoop->singleton->reactor }, weak => 1;

sub DESTROY {
  my $self = shift;
  $ENV{MOJO_REUSE} =~ s/(?:^|\,)\Q$self->{reuse}\E// if $self->{reuse};
  $self->stop                                        if $self->{handle} && $self->reactor;
}

sub generate_port { IO::Socket::IP->new(Listen => 5, LocalAddr => '127.0.0.1')->sockport }

sub handle { shift->{handle} }

sub is_accepting { !!shift->{active} }

sub listen {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  # Look for reusable file descriptor
  my $path    = $args->{path};
  my $address = $args->{address} || '0.0.0.0';
  my $port    = $args->{port};
  $ENV{MOJO_REUSE} ||= '';
  my $fd = ($path && $ENV{MOJO_REUSE} =~ /(?:^|\,)unix:\Q$path\E:(\d+)/)
    || ($port && $ENV{MOJO_REUSE} =~ /(?:^|\,)\Q$address:$port\E:(\d+)/) ? $1 : undef;

  # Allow file descriptor inheritance
  local $^F = 1023;

  # Reuse file descriptor
  my $handle;
  my $class = $path ? 'IO::Socket::UNIX' : 'IO::Socket::IP';
  if (defined($fd //= $args->{fd})) {
    $handle = $class->new_from_fd($fd, 'r') or croak "Can't open file descriptor $fd: $!";
  }

  else {
    my %options = (Listen => $args->{backlog} // SOMAXCONN, Type => SOCK_STREAM);

    # UNIX domain socket
    my $reuse;
    if ($path) {
      path($path)->remove if -S $path;
      $options{Local} = $path;
      $handle = $class->new(%options) or croak "Can't create listen socket: $!";
      $reuse = $self->{reuse} = join ':', 'unix', $path, fileno $handle;
    }

    # IP socket
    else {
      $options{LocalAddr} = $address;
      $options{LocalAddr} =~ y/[]//d;
      $options{LocalPort} = $port if $port;
      $options{ReuseAddr} = 1;
      $options{ReusePort} = $args->{reuse};
      $handle             = $class->new(%options) or croak "Can't create listen socket: $@";
      $fd                 = fileno $handle;
      $reuse = $self->{reuse} = join ':', $address, $handle->sockport, $fd;
    }

    $ENV{MOJO_REUSE} .= length $ENV{MOJO_REUSE} ? ",$reuse" : "$reuse";
  }
  $handle->blocking(0);
  @$self{qw(args handle)} = ($args, $handle);

  croak 'IO::Socket::SSL 2.009+ required for TLS support' if !Mojo::IOLoop::TLS->can_tls && $args->{tls};
}

sub port { shift->{handle}->sockport }

sub start {
  my $self = shift;
  weaken $self;
  ++$self->{active} and $self->reactor->io($self->{handle} => sub { $self->_accept })->watch($self->{handle}, 1, 0);
}

sub stop { delete($_[0]{active}) and $_[0]->reactor->remove($_[0]{handle}) }

sub _accept {
  my $self = shift;

  # Greedy accept
  my $args     = $self->{args};
  my $accepted = 0;
  while ($self->{active} && !($args->{single_accept} && $accepted++)) {
    return unless my $handle = $self->{handle}->accept;
    $handle->blocking(0);

    # Disable Nagle's algorithm
    setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

    $self->emit(accept => $handle) and next unless $args->{tls};

    # Start TLS handshake
    my $tls = Mojo::IOLoop::TLS->new($handle)->reactor($self->reactor);
    $tls->on(upgrade => sub { $self->emit(accept => pop) });
    $tls->on(error   => sub { });
    $tls->negotiate(%$args, server => 1);
  }
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Server - Non-blocking TCP and UNIX domain socket server

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

L<Mojo::IOLoop::Server> accepts TCP/IP and UNIX domain socket connections for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Server> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

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

Low-level event reactor, defaults to the C<reactor> attribute value of the global L<Mojo::IOLoop> singleton. Note that
this attribute is weakened.

=head1 METHODS

L<Mojo::IOLoop::Server> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 generate_port

  my $port = Mojo::IOLoop::Server->generate_port;

Find a free TCP port, primarily used for tests.

=head2 handle

  my $handle = $server->handle;

Get handle for server, usually an L<IO::Socket::IP> object.

=head2 is_accepting

  my $bool = $server->is_accepting;

Check if connections are currently being accepted.

=head2 listen

  $server->listen(port => 3000);
  $server->listen({port => 3000});

Create a new listen socket. Note that TLS support depends on L<IO::Socket::SSL> (2.009+).

These options are currently available:

=over 2

=item address

  address => '127.0.0.1'

Local address to listen on, defaults to C<0.0.0.0>.

=item backlog

  backlog => 128

Maximum backlog size, defaults to C<SOMAXCONN>.

=item fd

  fd => 3

File descriptor with an already prepared listen socket.

=item path

  path => '/tmp/myapp.sock'

Path for UNIX domain socket to listen on.

=item port

  port => 80

Port to listen on, defaults to a random port.

=item reuse

  reuse => 1

Allow multiple servers to use the same port with the C<SO_REUSEPORT> socket option.

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

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
