package Mojo::IOLoop::Client;
use Mojo::Base 'Mojo::IOLoop::EventEmitter';

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
  : eval 'use IO::Socket::SSL 1.43 "inet4"; 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

has resolver => sub {
  require Mojo::IOLoop::Resolver;
  Mojo::IOLoop::Resolver->new;
};

# "It's like my dad always said: eventually, everybody gets shot."
sub DESTROY {
  my $self = shift;
  return if $self->{connected};
  return unless my $resolver = $self->resolver;
  return unless my $loop     = $resolver->ioloop;
  return unless my $watcher  = $loop->iowatcher;
  $watcher->cancel($self->{timer})  if $self->{timer};
  $watcher->remove($self->{handle}) if $self->{handle};
}

sub connect {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # Lookup
  if (!$args->{handle} && (my $address = $args->{address})) {
    $self->resolver->lookup(
      $address => sub {
        $args->{address} = $_[1] || $args->{address};
        $self->_connect($args);
      }
    );
  }

  # Connect
  else {
    $self->resolver->ioloop->defer(sub { $self->_connect($args) });
  }
}

sub _connect {
  my ($self, $args) = @_;

  # New socket
  my $handle;
  my $watcher = $self->resolver->ioloop->iowatcher;
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
    return $self->emit(error => "Couldn't connect.")
      unless $handle = $class->new(%options);

    # Timer
    $self->{timer} =
      $watcher->timer($timeout,
      sub { $self->emit(error => 'Connect timeout.') });

    # IPv6 needs an early start
    $handle->connect if IPV6;
  }

  # Non-blocking
  $handle->blocking(0);

  # Disable Nagle's algorithm
  setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

  # TLS
  weaken $self;
  if ($args->{tls}) {

    # No TLS support
    return $self->emit(
      error => 'IO::Socket::SSL 1.43 required for TLS support.')
      unless TLS;

    # Upgrade
    my %options = (
      SSL_startHandshake => 0,
      SSL_error_trap     => sub {
        my $handle  = delete $self->{handle};
        my $watcher = $self->resolver->ioloop->iowatcher;
        $watcher->remove($handle);
        $watcher->cancel($self->{timer});
        close $handle;
        $self->emit(error => $_[1]);
      },
      SSL_cert_file   => $args->{tls_cert},
      SSL_key_file    => $args->{tls_key},
      SSL_verify_mode => 0x00,
      SSL_create_ctx_callback =>
        sub { Net::SSLeay::CTX_sess_set_cache_size(shift, 128) },
      Timeout => $timeout,
      %{$args->{tls_args} || {}}
    );
    $self->{tls} = 1;
    return $self->emit(error => 'TLS upgrade failed.')
      unless $handle = IO::Socket::SSL->start_SSL($handle, %options);
  }

  # Start writing right away
  $self->{handle} = $handle;
  $watcher->add(
    $handle,
    on_readable => sub { $self->_connecting },
    on_writable => sub { $self->_connecting }
  );
}

# "Have you ever seen that Blue Man Group? Total ripoff of the Smurfs.
#  And the Smurfs, well, they SUCK."
sub _connecting {
  my $self = shift;

  # Switch between reading and writing
  my $handle  = $self->{handle};
  my $watcher = $self->resolver->ioloop->iowatcher;
  if ($self->{tls} && !$handle->connect_SSL) {
    my $error = $IO::Socket::SSL::SSL_ERROR;
    if    ($error == TLS_READ)  { $watcher->not_writing($handle) }
    elsif ($error == TLS_WRITE) { $watcher->writing($handle) }
    return;
  }

  # Check for errors
  return $self->emit(error => $! = $handle->sockopt(SO_ERROR))
    unless $handle->connected;

  # Connected
  $self->{connected} = 1;
  $watcher->cancel($self->{timer}) if $self->{timer};
  $watcher->remove($handle);
  $self->emit(connect => $handle);
}

1;
__END__

=head1 NAME

Mojo::IOLoop::Client - IOLoop Socket Client

=head1 SYNOPSIS

  use Mojo::IOLoop::Client;

  # Create socket connection
  my $client = Mojo::IOLoop::Client->new;
  $client->on(connect => sub {
    my ($self, $handle) = @_;
    ...
  });
  $client->on(error => sub {
    my ($self, $error) = @_;
    ...
  });
  $client->connect(address => 'mojolicio.us', port => 80);

=head1 DESCRIPTION

L<Mojo::IOLoop::Client> performs non-blocking socket connections for
L<Mojo::IOLoop>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::IOLoop::Client> implements the following attributes.

=head2 C<resolver>

  my $resolver = $client->resolver;
  $client      = $client->resolver(Mojo::IOLoop::Resolver->new);

DNS stub resolver, usually a L<Mojo::IOLoop::Resolver> object.

=head1 METHODS

L<Mojo::IOLoop::Client> inherits all methods from
L<Mojo::IOLoop::EventEmitter> and implements the following new ones.

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

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS certificate file.

=item C<tls_key>

Path to the TLS key file.

=back

=head1 EVENTS

L<Mojo::IOLoop::Client> can emit the following events.

=head2 C<connect>

Emitted once the connection is established.

=head2 C<error>

Emitted if an error happens on the connection.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
