package Mojo::IOLoop;
use Mojo::Base -base;

# "Professor: Amy, technology isn't intrinsically good or evil. It's how it's
#             used. Like the death ray."
use Carp 'croak';
use Mojo::IOLoop::Client;
use Mojo::IOLoop::Delay;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::Reactor::Poll;
use Mojo::Util qw(md5_sum steady_time);
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_IOLOOP_DEBUG} || 0;

has accept_interval => 0.025;
has [qw(lock unlock)];
has max_accepts     => 0;
has max_connections => 1000;
has multi_accept    => 50;
has reactor         => sub {
  my $class = Mojo::Reactor::Poll->detect;
  warn "-- Reactor initialized ($class)\n" if DEBUG;
  return $class->new;
};

# Ignore PIPE signal
$SIG{PIPE} = 'IGNORE';

# Initialize singleton reactor early
__PACKAGE__->singleton->reactor;

sub acceptor {
  my ($self, $acceptor) = @_;
  $self = $self->singleton unless ref $self;

  # Find acceptor for id
  return $self->{acceptors}{$acceptor} unless ref $acceptor;

  # Connect acceptor with reactor
  my $id = $self->_id;
  $self->{acceptors}{$id} = $acceptor;
  weaken $acceptor->reactor($self->reactor)->{reactor};
  $self->{accepts} = $self->max_accepts if $self->max_accepts;

  # Stop accepting so new acceptor can get picked up
  $self->_not_accepting;

  return $id;
}

sub client {
  my ($self, $cb) = (shift, pop);
  $self = $self->singleton unless ref $self;

  # Make sure timers are running
  $self->_timers;

  my $id     = $self->_id;
  my $c      = $self->{connections}{$id} ||= {};
  my $client = $c->{client} = Mojo::IOLoop::Client->new;
  weaken $client->reactor($self->reactor)->{reactor};

  weaken $self;
  $client->on(
    connect => sub {
      my $handle = pop;

      # Turn handle into stream
      my $c = $self->{connections}{$id};
      delete $c->{client};
      my $stream = $c->{stream} = Mojo::IOLoop::Stream->new($handle);
      $self->_stream($stream => $id);

      $self->$cb(undef, $stream);
    }
  );
  $client->on(
    error => sub {
      $self->_remove($id);
      $self->$cb(pop, undef);
    }
  );
  $client->connect(@_);

  return $id;
}

sub delay {
  my $self = shift;
  $self = $self->singleton unless ref $self;

  my $delay = Mojo::IOLoop::Delay->new;
  weaken $delay->ioloop($self)->{ioloop};
  @_ > 1 ? $delay->steps(@_) : $delay->once(finish => shift) if @_;

  return $delay;
}

sub generate_port { Mojo::IOLoop::Server->generate_port }

sub is_running { (ref $_[0] ? $_[0] : $_[0]->singleton)->reactor->is_running }
sub one_tick   { (ref $_[0] ? $_[0] : $_[0]->singleton)->reactor->one_tick }

sub recurring {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->reactor->recurring($after => sub { $self->$cb });
}

sub remove {
  my ($self, $id) = @_;
  $self = $self->singleton unless ref $self;
  my $c = $self->{connections}{$id};
  if ($c && (my $stream = $c->{stream})) { return $stream->close_gracefully }
  $self->_remove($id);
}

sub server {
  my ($self, $cb) = (shift, pop);
  $self = $self->singleton unless ref $self;

  my $server = Mojo::IOLoop::Server->new;
  weaken $self;
  $server->on(
    accept => sub {
      my $handle = pop;

      # Turn handle into stream
      my $stream = Mojo::IOLoop::Stream->new($handle);
      $self->$cb($stream, $self->stream($stream));

      # Enforce connection limit (randomize to improve load balancing)
      $self->max_connections(0)
        if defined $self->{accepts}
        && ($self->{accepts} -= int(rand 2) + 1) <= 0;

      # Stop accepting to release accept mutex
      $self->_not_accepting;
    }
  );
  $server->listen(@_);

  return $self->acceptor($server);
}

sub singleton { state $loop = shift->SUPER::new }

sub start {
  my $self = shift;
  croak 'Mojo::IOLoop already running' if $self->is_running;
  (ref $self ? $self : $self->singleton)->reactor->start;
}

sub stop { (ref $_[0] ? $_[0] : $_[0]->singleton)->reactor->stop }

sub stream {
  my ($self, $stream) = @_;
  $self = $self->singleton unless ref $self;

  # Connect stream with reactor
  return $self->_stream($stream, $self->_id) if ref $stream;

  # Find stream for id
  return undef unless my $c = $self->{connections}{$stream};
  return $c->{stream};
}

sub timer {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->reactor->timer($after => sub { $self->$cb });
}

sub _accepting {
  my $self = shift;

  # Check if we have acceptors
  my $acceptors = $self->{acceptors} ||= {};
  return $self->_remove(delete $self->{accept}) unless keys %$acceptors;

  # Check connection limit
  my $i   = keys %{$self->{connections}};
  my $max = $self->max_connections;
  return unless $i < $max;

  # Acquire accept mutex
  if (my $cb = $self->lock) { return unless $self->$cb(!$i) }
  $self->_remove(delete $self->{accept});

  # Check if multi-accept is desirable
  my $multi = $self->multi_accept;
  $_->multi_accept($max < $multi ? 1 : $multi)->start for values %$acceptors;
  $self->{accepting}++;
}

sub _id {
  my $self = shift;
  my $id;
  do { $id = md5_sum('c' . steady_time . rand 999) }
    while $self->{connections}{$id} || $self->{acceptors}{$id};
  return $id;
}

sub _not_accepting {
  my $self = shift;

  # Make sure timers are running
  $self->_timers;

  # Release accept mutex
  return unless delete $self->{accepting};
  return unless my $cb = $self->unlock;
  $self->$cb;

  $_->stop for values %{$self->{acceptors} || {}};
}

sub _remove {
  my ($self, $id) = @_;

  # Timer
  return unless my $reactor = $self->reactor;
  return if $reactor->remove($id);

  # Acceptor
  if (delete $self->{acceptors}{$id}) { $self->_not_accepting }

  # Connection
  else { delete $self->{connections}{$id} }
}

sub _stop {
  my $self = shift;
  return      if keys %{$self->{connections}};
  $self->stop if $self->max_connections == 0;
  return      if keys %{$self->{acceptors}};
  $self->{$_} && $self->_remove(delete $self->{$_}) for qw(accept stop);
}

sub _stream {
  my ($self, $stream, $id) = @_;

  # Make sure timers are running
  $self->_timers;

  # Connect stream with reactor
  $self->{connections}{$id}{stream} = $stream;
  weaken $stream->reactor($self->reactor)->{reactor};
  weaken $self;
  $stream->on(close => sub { $self && $self->_remove($id) });
  $stream->start;

  return $id;
}

sub _timers {
  my $self = shift;
  $self->{accept} ||= $self->recurring($self->accept_interval => \&_accepting);
  $self->{stop} ||= $self->recurring(1 => \&_stop);
}

1;

=head1 NAME

Mojo::IOLoop - Minimalistic event loop

=head1 SYNOPSIS

  use Mojo::IOLoop;

  # Listen on port 3000
  Mojo::IOLoop->server({port => 3000} => sub {
    my ($loop, $stream) = @_;

    $stream->on(read => sub {
      my ($stream, $bytes) = @_;

      # Process input chunk
      say $bytes;

      # Write response
      $stream->write('HTTP/1.1 200 OK');
    });
  });

  # Connect to port 3000
  my $id = Mojo::IOLoop->client({port => 3000} => sub {
    my ($loop, $err, $stream) = @_;

    $stream->on(read => sub {
      my ($stream, $bytes) = @_;

      # Process input
      say "Input: $bytes";
    });

    # Write request
    $stream->write("GET / HTTP/1.1\x0d\x0a\x0d\x0a");
  });

  # Add a timer
  Mojo::IOLoop->timer(5 => sub {
    my $loop = shift;
    $loop->remove($id);
  });

  # Start event loop if necessary
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a very minimalistic event loop based on L<Mojo::Reactor>,
it has been reduced to the absolute minimal feature set required to build
solid and scalable non-blocking TCP clients and servers.

Optional modules L<EV> (4.0+), L<IO::Socket::IP> (0.16+) and
L<IO::Socket::SSL> (1.75+) are supported transparently, and used if installed.
Individual features can also be disabled with the MOJO_NO_IPV6 and MOJO_NO_TLS
environment variables.

The event loop will be resilient to time jumps if a monotonic clock is
available through L<Time::HiRes>. A TLS certificate and key are also built
right in, to make writing test servers as easy as possible. Also note that for
convenience the C<PIPE> signal will be set to C<IGNORE> when L<Mojo::IOLoop>
is loaded.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 accept_interval

  my $interval = $loop->accept_interval;
  $loop        = $loop->accept_interval(0.5);

Interval in seconds for trying to reacquire the accept mutex, defaults to
C<0.025>. Note that changing this value can affect performance and idle CPU
usage.

=head2 lock

  my $cb = $loop->lock;
  $loop  = $loop->lock(sub {...});

A callback for acquiring the accept mutex, used to sync multiple server
processes. The callback should return true or false. Note that exceptions in
this callback are not captured.

  $loop->lock(sub {
    my ($loop, $blocking) = @_;

    # Got the accept mutex, start accepting new connections
    return 1;
  });

=head2 max_accepts

  my $max = $loop->max_accepts;
  $loop   = $loop->max_accepts(1000);

The maximum number of connections this event loop is allowed to accept before
shutting down gracefully without interrupting existing connections, defaults
to C<0>. Setting the value to C<0> will allow this event loop to accept new
connections indefinitely. Note that up to half of this value can be subtracted
randomly to improve load balancing between multiple server processes.

=head2 max_connections

  my $max = $loop->max_connections;
  $loop   = $loop->max_connections(1000);

The maximum number of parallel connections this event loop is allowed to
handle before stopping to accept new incoming connections, defaults to
C<1000>. Setting the value to C<0> will make this event loop stop accepting
new connections and allow it to shut down gracefully without interrupting
existing connections.

=head2 multi_accept

  my $multi = $loop->multi_accept;
  $loop     = $loop->multi_accept(100);

Number of connections to accept at once, defaults to C<50>.

=head2 reactor

  my $reactor = $loop->reactor;
  $loop       = $loop->reactor(Mojo::Reactor->new);

Low level event reactor, usually a L<Mojo::Reactor::Poll> or
L<Mojo::Reactor::EV> object.

  # Watch if handle becomes readable or writable
  $loop->reactor->io($handle => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Handle is writable' : 'Handle is readable';
  });

  # Change to watching only if handle becomes writable
  $loop->reactor->watch($handle, 0, 1);

=head2 unlock

  my $cb = $loop->unlock;
  $loop  = $loop->unlock(sub {...});

A callback for releasing the accept mutex, used to sync multiple server
processes. Note that exceptions in this callback are not captured.

=head1 METHODS

L<Mojo::IOLoop> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 acceptor

  my $server = Mojo::IOLoop->acceptor($id);
  my $server = $loop->acceptor($id);
  my $id     = $loop->acceptor(Mojo::IOLoop::Server->new);

Get L<Mojo::IOLoop::Server> object for id or turn object into an acceptor.

=head2 client

  my $id
    = Mojo::IOLoop->client(address => '127.0.0.1', port => 3000, sub {...});
  my $id = $loop->client(address => '127.0.0.1', port => 3000, sub {...});
  my $id = $loop->client({address => '127.0.0.1', port => 3000} => sub {...});

Open TCP connection with L<Mojo::IOLoop::Client>, takes the same arguments as
L<Mojo::IOLoop::Client/"connect">.

  # Connect to localhost on port 3000
  Mojo::IOLoop->client({port => 3000} => sub {
    my ($loop, $err, $stream) = @_;
    ...
  });

=head2 delay

  my $delay = Mojo::IOLoop->delay;
  my $delay = $loop->delay;
  my $delay = $loop->delay(sub {...});
  my $delay = $loop->delay(sub {...}, sub {...});

Get L<Mojo::IOLoop::Delay> object to manage callbacks and control the flow of
events. A single callback will be treated as a subscriber to the C<finish>
event, and multiple ones as a chain of steps.

  # Synchronize multiple events
  my $delay = Mojo::IOLoop->delay(sub { say 'BOOM!' });
  for my $i (1 .. 10) {
    my $end = $delay->begin;
    Mojo::IOLoop->timer($i => sub {
      say 10 - $i;
      $end->();
    });
  }

  # Sequentialize multiple events
  my $delay = Mojo::IOLoop->delay(

    # First step (simple timer)
    sub {
      my $delay = shift;
      Mojo::IOLoop->timer(2 => $delay->begin);
      say 'Second step in 2 seconds.';
    },

    # Second step (parallel timers)
    sub {
      my $delay = shift;
      Mojo::IOLoop->timer(1 => $delay->begin);
      Mojo::IOLoop->timer(3 => $delay->begin);
      say 'Third step in 3 seconds.';
    },

    # Third step (the end)
    sub { say 'And done after 5 seconds total.' }
  );

  # Wait for events if necessary
  $delay->wait unless Mojo::IOLoop->is_running;

=head2 generate_port

  my $port = Mojo::IOLoop->generate_port;
  my $port = $loop->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 is_running

  my $success = Mojo::IOLoop->is_running;
  my $success = $loop->is_running;

Check if event loop is running.

  exit unless Mojo::IOLoop->is_running;

=head2 one_tick

  Mojo::IOLoop->one_tick;
  $loop->one_tick;

Run event loop until an event occurs. Note that this method can recurse back
into the reactor, so you need to be careful.

=head2 recurring

  my $id = Mojo::IOLoop->recurring(0.5 => sub {...});
  my $id = $loop->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds.

  # Invoke as soon as possible
  Mojo::IOLoop->recurring(0 => sub { say 'Reactor tick.' });

=head2 remove

  Mojo::IOLoop->remove($id);
  $loop->remove($id);

Remove anything with an id, connections will be dropped gracefully by allowing
them to finish writing all data in their write buffers.

=head2 server

  my $id = Mojo::IOLoop->server(port => 3000, sub {...});
  my $id = $loop->server(port => 3000, sub {...});
  my $id = $loop->server({port => 3000} => sub {...});

Accept TCP connections with L<Mojo::IOLoop::Server>, takes the same arguments
as L<Mojo::IOLoop::Server/"listen">.

  # Listen on port 3000
  Mojo::IOLoop->server({port => 3000} => sub {
    my ($loop, $stream, $id) = @_;
    ...
  });

=head2 singleton

  my $loop = Mojo::IOLoop->singleton;

The global L<Mojo::IOLoop> singleton, used to access a single shared event
loop object from everywhere inside the process.

  # Many methods also allow you to take shortcuts
  Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;

=head2 start

  Mojo::IOLoop->start;
  $loop->start;

Start the event loop, this will block until C<stop> is called. Note that some
reactors stop automatically if there are no events being watched anymore.

  # Start event loop only if it is not running already
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 stop

  Mojo::IOLoop->stop;
  $loop->stop;

Stop the event loop, this will not interrupt any existing connections and the
event loop can be restarted by running C<start> again.

=head2 stream

  my $stream = Mojo::IOLoop->stream($id);
  my $stream = $loop->stream($id);
  my $id     = $loop->stream(Mojo::IOLoop::Stream->new);

Get L<Mojo::IOLoop::Stream> object for id or turn object into a connection.

  # Increase inactivity timeout for connection to 300 seconds
  Mojo::IOLoop->stream($id)->timeout(300);

=head2 timer

  my $id = Mojo::IOLoop->timer(5 => sub {...});
  my $id = $loop->timer(5 => sub {...});
  my $id = $loop->timer(0.25 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds.

  # Invoke as soon as possible
  Mojo::IOLoop->timer(0 => sub { say 'Next tick.' });

=head1 DEBUGGING

You can set the MOJO_IOLOOP_DEBUG environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_IOLOOP_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
