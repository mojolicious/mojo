package Mojo::IOLoop;
use Mojo::Base -base;

use Mojo::IOLoop::Client;
use Mojo::IOLoop::Resolver;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::IOLoop::Trigger;
use Mojo::IOWatcher;
use Scalar::Util 'weaken';
use Time::HiRes 'time';

use constant DEBUG => $ENV{MOJO_IOLOOP_DEBUG} || 0;

has client_class    => 'Mojo::IOLoop::Client';
has connect_timeout => 3;
has iowatcher       => sub {
  my $class = Mojo::IOWatcher->detect;
  warn "MAINLOOP ($class)\n" if DEBUG;
  $class->new;
};
has max_accepts     => 0;
has max_connections => 1000;
has [qw/on_lock on_unlock/] => sub {
  sub {1}
};
has resolver => sub {
  my $resolver = Mojo::IOLoop::Resolver->new(ioloop => shift);
  weaken $resolver->{ioloop};
  return $resolver;
};
has server_class => 'Mojo::IOLoop::Server';
has stream_class => 'Mojo::IOLoop::Stream';
has timeout      => '0.025';

# Ignore PIPE signal
$SIG{PIPE} = 'IGNORE';

# Singleton
our $LOOP;

sub new {
  my $class = shift;

  # Build new loop from singleton and inherit watcher
  my $loop = $LOOP;
  local $LOOP = undef;
  my $self;
  if ($loop) {
    $self = $loop->new(@_);
    $self->iowatcher($loop->iowatcher->new);
  }

  # Start from scratch
  else { $self = $class->SUPER::new(@_) }

  return $self;
}

sub connect {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $args = ref $_[0] ? $_[0] : {@_};

  # New client
  my $client = $self->client_class->new;
  (my $id) = "$client" =~ /0x([\da-f]+)/;
  $id = $args->{id} if $args->{id};
  my $c = $self->{connections}->{$id} ||= {};
  $c->{client} = $client;
  $client->resolver($self->resolver);
  weaken $client->{resolver};

  # Events
  $c->{close}   ||= delete $args->{on_close};
  $c->{connect} ||= delete $args->{on_connect};
  $c->{error}   ||= delete $args->{on_error};
  $c->{read}    ||= delete $args->{on_read};
  weaken $self;
  $client->on(
    connect => sub {
      my $handle = pop;

      # New stream
      my $c = $self->{connections}->{$id};
      delete $c->{client};
      my $stream = $c->{stream} = $self->stream_class->new($handle);
      $stream->iowatcher($self->iowatcher);
      weaken $stream->{iowatcher};

      # Events
      $stream->on(
        close => sub {
          $c->{close}->($self, $id) if $c->{close};
          $self->drop($id);
        }
      );
      weaken $c;
      $stream->on(
        error => sub {
          my $c = delete $self->{connections}->{$id};
          $c->{error}->($self, $id, pop) if $c->{error};
        }
      );
      $stream->on(
        read => sub {
          my $c = $self->{connections}->{$id};
          $c->{active} = time;
          $c->{read}->($self, $id, pop) if $c->{read};
        }
      );

      # Connected
      $stream->resume;
      $self->write($id, @$_) for @{$c->{write} || []};
      $c->{connect}->($self, $id) if $c->{connect};
    }
  );
  $client->on(
    error => sub {
      my $c = delete $self->{connections}->{$id};
      $c->{error}->($self, $id, pop) if $c->{error};
    }
  );

  # Connect
  $args->{timeout} ||= $self->connect_timeout;
  $client->connect($args);

  return $id;
}

sub connection_timeout {
  my ($self, $id, $timeout) = @_;
  return unless my $c = $self->{connections}->{$id};
  $c->{timeout} = $timeout and return $self if defined $timeout;
  $c->{timeout};
}

sub defer { shift->timer(0 => @_) }

sub drop {
  my ($self, $id) = @_;
  $self = $self->singleton unless ref $self;
  if (my $c = $self->{connections}->{$id}) { return $c->{finish} = 1 }
  $self->_drop($id);
}

sub generate_port { Mojo::IOLoop::Server->generate_port }

sub handle {
  my ($self, $id) = @_;
  return unless my $c      = $self->{connections}->{$id};
  return unless my $stream = $c->{stream};
  return $stream->handle;
}

sub is_running {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  return $self->{running};
}

# "Fat Tony is a cancer on this fair city!
#  He is the cancer and I am the… uh… what cures cancer?"
sub listen {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $args = ref $_[0] ? $_[0] : {@_};

  # New server
  my $server = $self->server_class->new;
  (my $id) = "$server" =~ /0x([\da-f]+)/;
  $self->{servers}->{$id} = $server;
  $server->iowatcher($self->iowatcher);
  weaken $server->{iowatcher};

  # Events
  my $accept = delete $args->{on_accept};
  my $close  = delete $args->{on_close};
  my $error  = delete $args->{on_error};
  my $read   = delete $args->{on_read};
  weaken $self;
  $server->on(
    accept => sub {
      my $handle = pop;

      # New stream
      my $stream = $self->stream_class->new($handle);
      (my $id) = "$stream" =~ /0x([\da-f]+)/;
      my $c = $self->{connections}->{$id} ||= {};
      $c->{stream} = $stream;
      $stream->iowatcher($self->iowatcher);
      weaken $stream->{iowatcher};

      # Events
      $c->{close} = $close;
      $c->{error} = $error;
      $c->{read}  = $read;
      $stream->on(
        close => sub {
          my $c = delete $self->{connections}->{$id};
          $c->{close}->($self, $id) if $c->{close};
        }
      );
      $stream->on(
        error => sub {
          my $c = delete $self->{connections}->{$id};
          $c->{error}->($self, $id, pop) if $c->{error};
        }
      );
      $stream->on(
        read => sub {
          my $c = $self->{connections}->{$id};
          $c->{active} = time;
          $c->{read}->($self, $id, pop) if $c->{read};
        }
      );

      # Accept and enforce limit
      $stream->resume;
      $accept->($self, $id) if $accept;
      $self->max_connections(0)
        if defined $self->{accepts} && --$self->{accepts} == 0;
      $self->_not_listening;
    }
  );

  # Listen
  $server->listen($args);
  $self->{accepts} = $self->max_accepts if $self->max_accepts;
  $self->_not_listening;

  return $id;
}

sub local_info {
  my ($self, $id) = @_;
  return {} unless my $handle = $self->handle($id);
  return {address => $handle->sockhost, port => $handle->sockport};
}

sub on_close { shift->_event(close => @_) }
sub on_error { shift->_event(error => @_) }
sub on_read  { shift->_event(read  => @_) }

sub one_tick {
  my ($self, $timeout) = @_;
  $timeout = $self->timeout unless defined $timeout;

  # Housekeeping
  $self->_listening;
  my $connections = $self->{connections} ||= {};
  while (my ($id, $c) = each %$connections) {

    # Connection needs to be finished
    if ($c->{finish} && (!$c->{stream} || $c->{stream}->is_finished)) {
      $self->_drop($id);
      next;
    }

    # Connection timeout
    $self->_drop($id)
      if (time - ($c->{active} || time)) >= ($c->{timeout} || 15);
  }

  # Graceful shutdown
  $self->stop if $self->max_connections == 0 && keys %$connections == 0;

  # Watcher
  $self->iowatcher->one_tick($timeout);
}

sub recurring {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->iowatcher->recurring($after => sub { $self->$cb(pop) });
}

sub remote_info {
  my ($self, $id) = @_;
  return {} unless my $handle = $self->handle($id);
  return {address => $handle->peerhost, port => $handle->peerport};
}

sub singleton { $LOOP ||= shift->new(@_) }

sub start {
  my $self = shift;
  $self = $self->singleton unless ref $self;

  # Check if we are already running
  return if $self->{running};
  $self->{running} = 1;

  # Mainloop
  $self->one_tick while $self->{running};

  return $self;
}

sub start_tls {
  my $self = shift;
  my $id   = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # Steal handle and upgrade to TLS
  my $stream = delete $self->{connections}->{$id}->{stream};
  $args->{handle} = $stream->steal_handle;
  $args->{id}     = $id;
  $args->{tls}    = 1;
  $self->connect($args);
}

sub stop {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  delete $self->{running};
}

sub test {
  my ($self, $id) = @_;
  return unless my $c      = $self->{connections}->{$id};
  return unless my $stream = $c->{stream};
  return !$self->iowatcher->is_readable($stream->handle);
}

sub timer {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->iowatcher->timer($after => sub { $self->$cb(pop) });
}

sub trigger {
  my ($self, $cb) = @_;
  $self = $self->singleton unless ref $self;
  my $t = Mojo::IOLoop::Trigger->new;
  $t->ioloop($self);
  weaken $t->{ioloop};
  $t->once(done => $cb) if $cb;
  return $t;
}

sub write {
  my ($self, $id, $chunk, $cb) = @_;

  # Write right away
  my $c = $self->{connections}->{$id};
  $c->{active} = time;
  if (my $stream = $c->{stream}) {
    return $stream->write($chunk) unless $cb;
    weaken $self;
    return $stream->write($chunk, sub { $self->$cb($id) });
  }

  # Delayed write
  $c->{write} ||= [];
  push @{$c->{write}}, [$chunk, $cb];
}

sub _drop {
  my ($self, $id) = @_;
  return $self unless my $watcher = $self->iowatcher;
  return $self if $watcher->cancel($id);
  if (delete $self->{servers}->{$id}) { delete $self->{listening} }
  else { delete((delete($self->{connections}->{$id}) || {})->{stream}) }
  return $self;
}

sub _event {
  my ($self, $event, $id, $cb) = @_;
  return unless my $c = $self->{connections}->{$id};
  $c->{$event} = $cb if $cb;
  return $self;
}

sub _listening {
  my $self = shift;

  # Check if we should be listening
  return if $self->{listening};
  my $servers = $self->{servers} ||= {};
  return unless keys %$servers;
  my $i = keys %{$self->{connections}};
  return unless $i < $self->max_connections;
  return unless $self->on_lock->($self, !$i);

  # Start listening
  $_->resume for values %$servers;
  $self->{listening} = 1;
}

sub _not_listening {
  my $self = shift;

  # Check if we are listening
  return unless delete $self->{listening};
  $self->on_unlock->($self);

  # Stop listening
  $_->pause for values %{$self->{servers} || {}};
  delete $self->{listening};
}

1;
__END__

=head1 NAME

Mojo::IOLoop - Minimalistic Reactor For Non-Blocking TCP Clients And Servers

=head1 SYNOPSIS

  use Mojo::IOLoop;

  # Listen on port 3000
  Mojo::IOLoop->listen(
    port => 3000,
    on_read => sub {
      my ($self, $id, $chunk) = @_;

      # Process input
      print $chunk;

      # Got some data, time to write
      $self->write($id, 'HTTP/1.1 200 OK');
    }
  );

  # Connect to port 3000 with TLS activated
  my $id = Mojo::IOLoop->connect(
    address => 'localhost',
    port => 3000,
    tls => 1,
    on_connect => sub {
      my ($self, $id) = @_;

      # Write request
      $self->write($id, "GET / HTTP/1.1\r\n\r\n");
    },
    on_read => sub {
      my ($self, $id, $chunk) = @_;

      # Process input
      print $chunk;
    }
  );

  # Add a timer
  Mojo::IOLoop->timer(5 => sub {
    my $self = shift;
    $self->drop($id);
  });

  # Start and stop loop
  Mojo::IOLoop->start;
  Mojo::IOLoop->stop;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a very minimalistic reactor that has been reduced to the
absolute minimal feature set required to build solid and scalable
non-blocking TCP clients and servers.

Optional modules L<EV>, L<IO::Socket::IP> and L<IO::Socket::SSL> are
supported transparently and used if installed.

A TLS certificate and key are also built right in to make writing test
servers as easy as possible.

=head1 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 C<client_class>

  my $class = $loop->client_class;
  $loop     = $loop->client_class('Mojo::IOLoop::Client');

Class to be used for performing non-blocking socket connections with the
C<connect> method, defaults to L<Mojo::IOLoop::Client>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<connect_timeout>

  my $timeout = $loop->connect_timeout;
  $loop       = $loop->connect_timeout(5);

Maximum time in seconds a connection can take to be connected before being
dropped, defaults to C<3>.

=head2 C<iowatcher>

  my $watcher = $loop->iowatcher;
  $loop       = $loop->iowatcher(Mojo::IOWatcher->new);

Low level event watcher, usually a L<Mojo::IOWatcher> or
L<Mojo::IOWatcher::EV> object.
Replacing the event watcher of the singleton loop makes all new loops use the
same type of event watcher.
Note that this attribute is EXPERIMENTAL and might change without warning!

  Mojo::IOLoop->singleton->iowatcher(MyWatcher->new);

=head2 C<max_accepts>

  my $max = $loop->max_accepts;
  $loop   = $loop->max_accepts(1000);

The maximum number of connections this loop is allowed to accept before
shutting down gracefully without interrupting existing connections, defaults
to C<0>.
Setting the value to C<0> will allow this loop to accept new connections
infinitely.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<max_connections>

  my $max = $loop->max_connections;
  $loop   = $loop->max_connections(1000);

The maximum number of parallel connections this loop is allowed to handle
before stopping to accept new incoming connections, defaults to C<1000>.
Setting the value to C<0> will make this loop stop accepting new connections
and allow it to shutdown gracefully without interrupting existing
connections.

=head2 C<on_lock>

  my $cb = $loop->on_lock;
  $loop  = $loop->on_lock(sub {...});

A locking callback that decides if this loop is allowed to accept new
incoming connections, used to sync multiple server processes.
The callback should return true or false.
Note that exceptions in this callback are not captured.

  $loop->on_lock(sub {
    my ($loop, $blocking) = @_;

    # Got the lock, listen for new connections
    return 1;
  });

=head2 C<on_unlock>

  my $cb = $loop->on_unlock;
  $loop  = $loop->on_unlock(sub {...});

A callback to free the accept lock, used to sync multiple server processes.
Note that exceptions in this callback are not captured.

=head2 C<resolver>

  my $resolver = $loop->resolver;
  $loop        = $loop->resolver(Mojo::IOLoop::Resolver->new);

DNS stub resolver, usually a L<Mojo::IOLoop::Resolver> object.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<server_class>

  my $class = $loop->server_class;
  $loop     = $loop->server_class('Mojo::IOLoop::Server');

Class to be used for accepting incoming connections with the C<listen>
method, defaults to L<Mojo::IOLoop::Server>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<stream_class>

  my $class = $loop->stream_class;
  $loop     = $loop->stream_class('Mojo::IOLoop::Stream');

Class to be used for streaming handles, defaults to L<Mojo::IOLoop::Stream>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<timeout>

  my $timeout = $loop->timeout;
  $loop       = $loop->timeout(5);

Maximum time in seconds our loop waits for new events to happen, defaults to
C<0.025>.
Note that a value of C<0> would make the loop non-blocking.

=head1 METHODS

L<Mojo::IOLoop> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $loop = Mojo::IOLoop->new;

Construct a new L<Mojo::IOLoop> object.
Multiple of these will block each other, so use C<singleton> instead if
possible.

=head2 C<connect>

  my $id = Mojo::IOLoop->connect(
    address => '127.0.0.1',
    port    => 3000
  );
  my $id = $loop->connect(
    address => '127.0.0.1',
    port    => 3000
  );

Open a TCP connection to a remote host.
Note that TLS support depends on L<IO::Socket::SSL> and IPv6 support on
L<IO::Socket::IP>.

These options are currently available:

=over 2

=item C<address>

Address or host name of the peer to connect to.

=item C<handle>

Use an already prepared handle.

=item C<on_connect>

Callback to be invoked once the connection is established.

=item C<on_close>

Callback to be invoked if the connection gets closed.

=item C<on_error>

Callback to be invoked if an error happens on the connection.

=item C<on_read>

Callback to be invoked if new data arrives on the connection.

=item C<port>

Port to connect to.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS certificate file.

=item C<tls_key>

Path to the TLS key file.

=back

=head2 C<connection_timeout>

  my $timeout = $loop->connection_timeout($id);
  $loop       = $loop->connection_timeout($id => 45);

Maximum amount of time in seconds a connection can be inactive before being
dropped, defaults to C<15>.

=head2 C<defer>

  Mojo::IOLoop->defer(sub {...});
  $loop->defer(sub {...});

Invoke callback on next reactor tick.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<drop>

  $loop = Mojo::IOLoop->drop($id)
  $loop = $loop->drop($id);

Drop anything with an id.
Connections will be dropped gracefully by allowing them to finish writing all
data in its write buffer.

=head2 C<generate_port>

  my $port = Mojo::IOLoop->generate_port;
  my $port = $loop->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 C<handle>

  my $handle = $loop->handle($id);

Get handle for id.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<is_running>

  my $running = Mojo::IOLoop->is_running;
  my $running = $loop->is_running;

Check if loop is running.

  exit unless Mojo::IOLoop->is_running;

=head2 C<listen>

  my $id = Mojo::IOLoop->listen(port => 3000);
  my $id = $loop->listen(port => 3000);
  my $id = $loop->listen({port => 3000});
  my $id = $loop->listen(
    port     => 443,
    tls      => 1,
    tls_cert => '/foo/server.cert',
    tls_key  => '/foo/server.key'
  );

Create a new listen socket.
Note that TLS support depends on L<IO::Socket::SSL> and IPv6 support on
L<IO::Socket::IP>.

These options are currently available:

=over 2

=item C<address>

Local address to listen on, defaults to all.

=item C<backlog>

Maximum backlog size, defaults to C<SOMAXCONN>.

=item C<on_accept>

Callback to be invoked for each accepted connection.

=item C<on_close>

Callback to be invoked if the connection gets closed.

=item C<on_error>

Callback to be invoked if an error happens on the connection.

=item C<on_read>

Callback to be invoked if new data arrives on the connection.

=item C<port>

Port to listen on.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS cert file, defaulting to a built-in test certificate.

=item C<tls_key>

Path to the TLS key file, defaulting to a built-in test key.

=item C<tls_ca>

Path to TLS certificate authority file or directory.

=back

=head2 C<local_info>

  my $info = $loop->local_info($id);

Get local information about a connection.

  my $address = $info->{address};

These values are to be expected in the returned hash reference.

=over 2

=item C<address>

The local address.

=item C<port>

The local port.

=back

=head2 C<on_close>

  $loop = $loop->on_close($id => sub {...});

Callback to be invoked if the connection gets closed.

=head2 C<on_error>

  $loop = $loop->on_error($id => sub {...});

Callback to be invoked if an error happens on the connection.

=head2 C<on_read>

  $loop = $loop->on_read($id => sub {...});

Callback to be invoked if new data arrives on the connection.

  $loop->on_read($id => sub {
    my ($loop, $id, $chunk) = @_;

    # Process chunk
  });

=head2 C<one_tick>

  $loop->one_tick;
  $loop->one_tick('0.25');
  $loop->one_tick(0);

Run reactor for exactly one tick.

=head2 C<recurring>

  my $id = Mojo::IOLoop->recurring(0 => sub {...});
  my $id = $loop->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of seconds.
This for example allows you to run multiple reactors next to each other.

  my $loop2 = Mojo::IOLoop->new(timeout => 0);
  Mojo::IOLoop->recurring(0 => sub { $loop2->one_tick });

Note that the loop timeout can be changed dynamically at any time to adjust
responsiveness.

=head2 C<remote_info>

  my $info = $loop->remote_info($id);

Get remote information about a connection.

  my $address = $info->{address};

These values are to be expected in the returned hash reference.

=over 2

=item C<address>

The remote address.

=item C<port>

The remote port.

=back

=head2 C<singleton>

  my $loop = Mojo::IOLoop->singleton;

The global loop object, used to access a single shared loop instance from
everywhere inside the process.
Many methods also allow you to take shortcuts when using the L<Mojo::IOLoop>
singleton.

  Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;

=head2 C<start>

  Mojo::IOLoop->start;
  $loop->start;

Start the loop, this will block until C<stop> is called or return immediately
if the loop is already running.

=head2 C<start_tls>

  $loop->start_tls($id);

Start new TLS connection inside old connection.
Note that TLS support depends on L<IO::Socket::SSL>.

=head2 C<stop>

  Mojo::IOLoop->stop;
  $loop->stop;

Stop the loop immediately, this will not interrupt any existing connections
and the loop can be restarted by running C<start> again.

=head2 C<test>

  my $success = $loop->test($id);

Test for errors and garbage bytes on the connection.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<timer>

  my $id = Mojo::IOLoop->timer(5 => sub {...});
  my $id = $loop->timer(5 => sub {...});
  my $id = $loop->timer(0.25 => sub {...});

Create a new timer, invoking the callback after a given amount of seconds.

=head2 C<trigger>

  my $t = Mojo::IOLoop->trigger;
  my $t = $loop->trigger;
  my $t = $loop->trigger(sub {...});

Get L<Mojo::IOLoop::Trigger> remote control for the loop.
Note that this method is EXPERIMENTAL and might change without warning!

  # Synchronize multiple events
  my $t = Mojo::IOLoop->trigger(sub { print "BOOM!\n" });
  for my $i (1 .. 10) {
    $t->begin;
    Mojo::IOLoop->timer($i => sub {
      print 10 - $i,"\n";
      $t->end;
    });
  }

  # Stop automatically when done
  $t->start;

=head2 C<write>

  $loop->write($id => 'Hello!');
  $loop->write($id => 'Hello!', sub {...});

Write data to connection, the optional drain callback will be invoked once
all data has been written.

=head1 DEBUGGING

You can set the C<MOJO_IOLOOP_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_IOLOOP_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
