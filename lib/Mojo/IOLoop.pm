package Mojo::IOLoop;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::IOLoop::Client;
use Mojo::IOLoop::Delay;
use Mojo::IOLoop::Server;
use Mojo::IOLoop::Stream;
use Mojo::Reactor::Poll;
use Mojo::Util 'md5_sum';
use Scalar::Util qw/blessed weaken/;
use Time::HiRes 'time';

use constant DEBUG => $ENV{MOJO_IOLOOP_DEBUG} || 0;

has client_class => 'Mojo::IOLoop::Client';
has [qw/lock unlock/];
has max_accepts     => 0;
has max_connections => 1000;
has reactor         => sub {
  my $class = Mojo::Reactor::Poll->detect;
  warn "-- Mainloop ($class)\n" if DEBUG;
  return $class->new;
};
has server_class => 'Mojo::IOLoop::Server';
has stream_class => 'Mojo::IOLoop::Stream';

# Ignore PIPE signal
$SIG{PIPE} = 'IGNORE';

# Initialize singleton reactor early
__PACKAGE__->singleton->reactor;

sub client {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $cb = pop;

  # Make sure garbage gets collected
  $self->_cleaner;

  # New client
  my $client = $self->client_class->new;
  my $id     = $self->_id;
  my $c      = $self->{connections}{$id} ||= {};
  $c->{client} = $client;
  weaken $client->reactor($self->reactor)->{reactor};

  # Events
  weaken $self;
  $client->on(
    connect => sub {
      my $handle = pop;

      # New stream
      my $c = $self->{connections}{$id};
      delete $c->{client};
      my $stream = $c->{stream} = $self->stream_class->new($handle);
      $self->_stream($stream => $id);

      # Connected
      $self->$cb(undef, $stream);
    }
  );
  $client->on(
    error => sub {
      delete $self->{connections}{$id};
      $self->$cb(pop, undef);
    }
  );

  # Connect
  $client->connect(@_);

  return $id;
}

sub delay {
  my ($self, $cb) = @_;
  $self = $self->singleton unless ref $self;
  my $delay = Mojo::IOLoop::Delay->new;
  weaken $delay->ioloop($self)->{ioloop};
  $delay->once(finish => $cb) if $cb;
  return $delay;
}

# DEPRECATED in Leaf Fluttering In Wind!
sub drop {
  warn "Mojo::IOLoop->drop is DEPRECATED in favor of Mojo::IOLoop->remove!\n";
  shift->remove(@_);
}

sub generate_port { Mojo::IOLoop::Server->generate_port }

sub is_running {
  my $self = shift;
  return (ref $self ? $self : $self->singleton)->reactor->is_running;
}

sub one_tick {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  $self->reactor->one_tick;
}

sub recurring {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->reactor->recurring($after => sub { $self->$cb });
}

sub remove {
  my ($self, $id) = @_;
  $self = $self->singleton unless ref $self;
  if (my $c = $self->{connections}{$id}) { return $c->{finish} = 1 }
  $self->_remove($id);
}

# "Fat Tony is a cancer on this fair city!
#  He is the cancer and I am the… uh… what cures cancer?"
sub server {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $cb = pop;

  # Make sure garbage gets collected
  $self->_cleaner;

  # New server
  my $server = $self->server_class->new;
  my $id     = $self->_id;
  $self->{servers}{$id} = $server;
  weaken $server->reactor($self->reactor)->{reactor};

  # Events
  weaken $self;
  $server->on(
    accept => sub {
      my $handle = pop;

      # Accept
      my $stream = $self->stream_class->new($handle);
      my $id     = $self->stream($stream);
      $self->$cb($stream, $id);

      # Enforce limit
      $self->max_connections(0)
        if defined $self->{accepts} && --$self->{accepts} == 0;
      $self->_not_listening;
    }
  );

  # Listen
  $server->listen(@_);
  $self->{accepts} = $self->max_accepts if $self->max_accepts;
  $self->_not_listening;

  return $id;
}

sub singleton { state $loop ||= shift->SUPER::new }

sub start {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  croak 'Mojo::IOLoop already running' if $self->is_running;
  $self->reactor->start;
}

sub stop {
  my $self = shift;
  (ref $self ? $self : $self->singleton)->reactor->stop;
}

sub stream {
  my $self = shift;
  $self = $self->singleton unless ref $self;

  # Connect stream with reactor
  my $stream = shift;
  return $self->_stream($stream, $self->_id) if blessed $stream;

  # Find stream for id
  return unless my $c = $self->{connections}{$stream};
  return $c->{stream};
}

sub timer {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->reactor->timer($after => sub { $self->$cb });
}

sub _cleaner {
  my $self = shift;
  $self->{cleaner} ||= $self->recurring(
    0.025 => sub {
      my $self = shift;

      # Manage connections
      $self->_listening;
      my $connections = $self->{connections} ||= {};
      while (my ($id, $c) = each %$connections) {
        $self->_remove($id)
          if $c->{finish} && (!$c->{stream} || !$c->{stream}->is_writing);
      }

      # Graceful shutdown
      $self->_remove(delete $self->{cleaner})
        unless keys(%$connections) || keys(%{$self->{servers}});
      $self->stop if $self->max_connections == 0 && keys %$connections == 0;
    }
  );
}

sub _id {
  my $self = shift;
  my $id;
  do { $id = md5_sum('c' . time . rand 999) }
    while $self->{connections}{$id} || $self->{servers}{$id};
  return $id;
}

sub _listening {
  my $self = shift;

  # Check if we should be listening
  return if $self->{listening};
  my $servers = $self->{servers} ||= {};
  return unless keys %$servers;
  my $i   = keys %{$self->{connections}};
  my $max = $self->max_connections;
  return unless $i < $max;
  if (my $cb = $self->lock) { return unless $self->$cb(!$i) }

  # Check if multi-accept is desirable and start listening
  $_->accepts($max > 1 ? 10 : 1)->start for values %$servers;
  $self->{listening} = 1;
}

sub _not_listening {
  my $self = shift;

  # Check if we are listening
  return unless delete $self->{listening};
  return unless my $cb = $self->unlock;
  $self->$cb();

  # Stop listening
  $_->stop for values %{$self->{servers} || {}};
}

sub _remove {
  my ($self, $id) = @_;

  # Timer
  return unless my $reactor = $self->reactor;
  return if $reactor->remove($id);

  # Listen socket
  if (delete $self->{servers}{$id}) { delete $self->{listening} }

  # Connection (stream needs to be deleted first)
  else {
    delete(($self->{connections}{$id} || {})->{stream});
    delete $self->{connections}{$id};
  }
}

sub _stream {
  my ($self, $stream, $id) = @_;

  # Make sure garbage gets collected
  $self->_cleaner;

  # Connect stream with reactor
  $self->{connections}{$id}{stream} = $stream;
  weaken $stream->reactor($self->reactor)->{reactor};

  # Events
  weaken $self;
  $stream->on(close => sub { $self->{connections}{$id}{finish} = 1 });
  $stream->start;

  return $id;
}

1;
__END__

=head1 NAME

Mojo::IOLoop - Minimalistic reactor for non-blocking TCP clients and servers

=head1 SYNOPSIS

  use Mojo::IOLoop;

  # Listen on port 3000
  Mojo::IOLoop->server({port => 3000} => sub {
    my ($loop, $stream) = @_;

    $stream->on(read => sub {
      my ($stream, $chunk) = @_;

      # Process input
      say $chunk;

      # Got some data, time to write
      $stream->write('HTTP/1.1 200 OK');
    });
  });

  # Connect to port 3000
  my $id = Mojo::IOLoop->client({port => 3000} => sub {
    my ($loop, $err, $stream) = @_;

    $stream->on(read => sub {
      my ($stream, $chunk) = @_;

      # Process input
      say "Input: $chunk";
    });

    # Write request
    $stream->write("GET / HTTP/1.1\r\n\r\n");
  });

  # Add a timer
  Mojo::IOLoop->timer(5 => sub {
    my $loop = shift;
    $loop->remove($id);
  });

  # Start loop if necessary
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a very minimalistic reactor based on L<Mojo::Reactor>, it
has been reduced to the absolute minimal feature set required to build solid
and scalable non-blocking TCP clients and servers.

Optional modules L<EV>, L<IO::Socket::IP> and L<IO::Socket::SSL> are
supported transparently and used if installed. Individual features can also
be disabled with the C<MOJO_NO_IPV6> and C<MOJO_NO_TLS> environment
variables.

A TLS certificate and key are also built right in to make writing test
servers as easy as possible. Also note that for convenience the C<PIPE>
signal will be set to C<IGNORE> when L<Mojo::IOLoop> is loaded.

=head1 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 C<client_class>

  my $class = $loop->client_class;
  $loop     = $loop->client_class('Mojo::IOLoop::Client');

Class to be used for opening TCP connections with the C<client> method,
defaults to L<Mojo::IOLoop::Client>.

=head2 C<lock>

  my $cb = $loop->lock;
  $loop  = $loop->lock(sub {...});

A locking callback that decides if this loop is allowed to accept new
incoming connections, used to sync multiple server processes. The callback
should return true or false. Note that exceptions in this callback are not
captured.

  $loop->lock(sub {
    my ($loop, $blocking) = @_;

    # Got the lock, listen for new connections
    return 1;
  });

=head2 C<max_accepts>

  my $max = $loop->max_accepts;
  $loop   = $loop->max_accepts(1000);

The maximum number of connections this loop is allowed to accept before
shutting down gracefully without interrupting existing connections, defaults
to C<0>. Setting the value to C<0> will allow this loop to accept new
connections indefinitely.

=head2 C<max_connections>

  my $max = $loop->max_connections;
  $loop   = $loop->max_connections(1000);

The maximum number of parallel connections this loop is allowed to handle
before stopping to accept new incoming connections, defaults to C<1000>.
Setting the value to C<0> will make this loop stop accepting new connections
and allow it to shutdown gracefully without interrupting existing
connections.

=head2 C<reactor>

  my $reactor = $loop->reactor;
  $loop       = $loop->reactor(Mojo::Reactor->new);

Low level event reactor, usually a L<Mojo::Reactor::Poll> or
L<Mojo::Reactor::EV> object.

  # Watch handle for I/O events
  $loop->reactor->io($handle => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Handle is writable' : 'Handle is readable';
  });

=head2 C<server_class>

  my $class = $loop->server_class;
  $loop     = $loop->server_class('Mojo::IOLoop::Server');

Class to be used for accepting TCP connections with the C<server> method,
defaults to L<Mojo::IOLoop::Server>.

=head2 C<stream_class>

  my $class = $loop->stream_class;
  $loop     = $loop->stream_class('Mojo::IOLoop::Stream');

Class to be used by C<client> and C<server> methods for I/O streams, defaults
to L<Mojo::IOLoop::Stream>.

=head2 C<unlock>

  my $cb = $loop->unlock;
  $loop  = $loop->unlock(sub {...});

A callback to free the accept lock, used to sync multiple server processes.
Note that exceptions in this callback are not captured.

=head1 METHODS

L<Mojo::IOLoop> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<client>

  my $id
    = Mojo::IOLoop->client(address => '127.0.0.1', port => 3000, sub {...});
  my $id = $loop->client(address => '127.0.0.1', port => 3000, sub {...});
  my $id = $loop->client({address => '127.0.0.1', port => 3000}, sub {...});

Open TCP connection with C<client_class>, which is usually
L<Mojo::IOLoop::Client>, takes the same arguments as
L<Mojo::IOLoop::Client/"connect">.

  Mojo::IOLoop->client({port => 3000} => sub {
    my ($loop, $err, $stream) = @_;
    ...
  });

=head2 C<delay>

  my $delay = Mojo::IOLoop->delay;
  my $delay = $loop->delay;
  my $delay = $loop->delay(sub {...});

Get L<Mojo::IOLoop::Delay> object to synchronize events and subscribe to
event L<Mojo::IOLoop::Delay/"finish"> if optional callback is provided.

  # Synchronize multiple events
  my $delay = Mojo::IOLoop->delay(sub { say 'BOOM!' });
  for my $i (1 .. 10) {
    $delay->begin;
    Mojo::IOLoop->timer($i => sub {
      say 10 - $i;
      $delay->end;
    });
  }

  # Wait for events if necessary
  $delay->wait unless Mojo::IOLoop->is_running;

=head2 C<generate_port>

  my $port = Mojo::IOLoop->generate_port;
  my $port = $loop->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 C<is_running>

  my $success = Mojo::IOLoop->is_running;
  my $success = $loop->is_running;

Check if loop is running.

  exit unless Mojo::IOLoop->is_running;

=head2 C<one_tick>

  Mojo::IOLoop->one_tick;
  $loop->one_tick;

Run reactor until at least one event has been handled or no events are being
watched anymore. Note that this method can recurse back into the reactor, so
you need to be careful.

=head2 C<recurring>

  my $id = Mojo::IOLoop->recurring(0 => sub {...});
  my $id = $loop->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds.

=head2 C<remove>

  Mojo::IOLoop->remove($id);
  $loop->remove($id);

Remove anything with an id. Connections will be dropped gracefully by
allowing them to finish writing all data in their write buffers.

=head2 C<server>

  my $id = Mojo::IOLoop->server(port => 3000, sub {...});
  my $id = $loop->server(port => 3000, sub {...});
  my $id = $loop->server({port => 3000}, sub {...});

Accept TCP connections with C<server_class>, which is usually
L<Mojo::IOLoop::Server>, takes the same arguments as
L<Mojo::IOLoop::Server/"listen">.

  Mojo::IOLoop->server({port => 3000} => sub {
    my ($loop, $stream, $id) = @_;
    ...
  });

=head2 C<singleton>

  my $loop = Mojo::IOLoop->singleton;

The global L<Mojo::IOLoop> singleton, used to access a single shared loop
object from everywhere inside the process.

  # Many methods also allow you to take shortcuts
  Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;

=head2 C<start>

  Mojo::IOLoop->start;
  $loop->start;

Start the loop, this will block until C<stop> is called or no events are
being watched anymore.

  # Start loop only if it is not running already
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head2 C<stop>

  Mojo::IOLoop->stop;
  $loop->stop;

Stop the loop immediately, this will not interrupt any existing connections
and the loop can be restarted by running C<start> again.

=head2 C<stream>

  my $stream = Mojo::IOLoop->stream($id);
  my $stream = $loop->stream($id);
  my $id     = $loop->stream($stream);

Get L<Mojo::IOLoop::Stream> object for id or turn object into a connection.

  # Increase inactivity timeout for connection to 300 seconds
  Mojo::IOLoop->stream($id)->timeout(300);

=head2 C<timer>

  my $id = Mojo::IOLoop->timer(5 => sub {...});
  my $id = $loop->timer(5 => sub {...});
  my $id = $loop->timer(0.25 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds.

=head1 DEBUGGING

You can set the C<MOJO_IOLOOP_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_IOLOOP_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
