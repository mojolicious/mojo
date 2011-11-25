package Mojo::IOLoop::Client;
use Mojo::Base 'Mojo::EventEmitter';

use IO::Socket::INET;
use Scalar::Util 'weaken';
use Socket qw/IPPROTO_TCP SO_ERROR TCP_NODELAY/;

# IPv6 support requires IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval 'use IO::Socket::IP 0.06 (); 1';

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.37 "inet4"; 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# "It's like my dad always said: eventually, everybody gets shot."
has iowatcher => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->iowatcher;
};

sub DESTROY {
  my $self = shift;
  return if $self->{connected};
  $self->_cleanup;
}

# "I wonder where Bart is, his dinner's getting all cold... and eaten."
sub connect {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};
  $args->{address} ||= '127.0.0.1';
  $args->{address} = '127.0.0.1' if $args->{address} eq 'localhost';
  weaken $self;
  $self->iowatcher->timer(0 => sub { $self->_connect($args) });
}

sub _cleanup {
  my $self = shift;
  return unless my $watcher = $self->{iowatcher};
  $watcher->drop_timer($self->{timer})   if $self->{timer};
  $watcher->drop_handle($self->{handle}) if $self->{handle};
}

sub _connect {
  my ($self, $args) = @_;

  # New socket
  my $handle;
  my $watcher = $self->iowatcher;
  my $timeout = $args->{timeout} || 3;
  unless ($handle = $args->{handle}) {
    my %options = (
      Blocking => 0,
      PeerAddr => $args->{address},
      PeerPort => $args->{port} || ($args->{tls} ? 443 : 80),
      Proto    => 'tcp',
      %{$args->{args} || {}}
    );
    $options{PeerAddr} =~ s/[\[\]]//g if $options{PeerAddr};
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
    return $self->emit_safe(error => "Couldn't connect.")
      unless $handle = $class->new(%options);

    # Timer
    $self->{timer} =
      $watcher->timer($timeout,
      sub { $self->emit_safe(error => 'Connect timeout.') });

    # IPv6 needs an early start
    $handle->connect if IPV6;
  }
  $handle->blocking(0);

  # Disable Nagle's algorithm
  setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

  # TLS
  weaken $self;
  if ($args->{tls}) {

    # No TLS support
    return $self->emit_safe(
      error => 'IO::Socket::SSL 1.37 required for TLS support.')
      unless TLS;

    # Upgrade
    my %options = (
      SSL_startHandshake => 0,
      SSL_error_trap     => sub {
        $self->_cleanup;
        close delete $self->{handle};
        $self->emit_safe(error => $_[1]);
      },
      SSL_cert_file   => $args->{tls_cert},
      SSL_key_file    => $args->{tls_key},
      SSL_verify_mode => 0x00,
      Timeout         => $timeout,
      %{$args->{tls_args} || {}}
    );
    $self->{tls} = 1;
    return $self->emit_safe(error => 'TLS upgrade failed.')
      unless $handle = IO::Socket::SSL->start_SSL($handle, %options);
  }

  # Start writing right away
  $self->{handle} = $handle;
  $watcher->watch(
    $handle,
    sub { $self->_connecting },
    sub { $self->_connecting }
  );
}

# "Have you ever seen that Blue Man Group? Total ripoff of the Smurfs.
#  And the Smurfs, well, they SUCK."
sub _connecting {
  my $self = shift;

  # Switch between reading and writing
  my $handle  = $self->{handle};
  my $watcher = $self->iowatcher;
  if ($self->{tls} && !$handle->connect_SSL) {
    my $error = $IO::Socket::SSL::SSL_ERROR;
    if    ($error == TLS_READ)  { $watcher->change($handle, 1, 0) }
    elsif ($error == TLS_WRITE) { $watcher->change($handle, 1, 1) }
    return;
  }

  # Check for errors
  return $self->emit_safe(error => $! = $handle->sockopt(SO_ERROR))
    unless $handle->connected;

  # Connected
  $self->{connected} = 1;
  $self->_cleanup;
  $self->emit_safe(connect => $handle);
}

1;
__END__

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
    my ($client, $error) = @_;
    ...
  });
  $client->connect(address => 'mojolicio.us', port => 80);

=head1 DESCRIPTION

L<Mojo::IOLoop::Client> opens TCP connections for L<Mojo::IOLoop>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 EVENTS

L<Mojo::IOLoop::Client> can emit the following events.

=head2 C<connect>

  $client->on(connect => sub {
    my ($client, $handle) = @_;
  });

Emitted safely once the connection is established.

=head2 C<error>

  $client->on(error => sub {
    my ($client, $error) = @_;
  });

Emitted safely if an error happens on the connection.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Client> implements the following attributes.

=head2 C<iowatcher>

  my $watcher = $client->iowatcher;
  $client     = $client->iowatcher(Mojo::IOWatcher->new);

Low level event watcher, defaults to the C<iowatcher> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Client> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<connect>

  $client->connect(
    address => '127.0.0.1',
    port    => 3000
  );

Open a socket connection to a remote host.
Note that TLS support depends on L<IO::Socket::SSL> and IPv6 support on
L<IO::Socket::IP>.

These options are currently available:

=over 2

=item C<address>

Address or host name of the peer to connect to.

=item C<handle>

Use an already prepared handle.

=item C<port>

Port to connect to.

=item C<timeout>

Maximum amount of time in seconds establishing connection may take.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS certificate file.

=item C<tls_key>

Path to the TLS key file.

=back

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
