package Mojo::Reactor;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use IO::Poll qw(POLLERR POLLHUP POLLIN);
use Mojo::Loader;

sub again { croak 'Method "again" not implemented by subclass' }

sub detect {
  my $try = $ENV{MOJO_REACTOR} || 'Mojo::Reactor::EV';
  return Mojo::Loader->new->load($try) ? 'Mojo::Reactor::Poll' : $try;
}

sub io { croak 'Method "io" not implemented by subclass' }

sub is_readable {
  my ($self, $handle) = @_;

  my $test = $self->{test} ||= IO::Poll->new;
  $test->mask($handle, POLLIN);
  $test->poll(0);
  my $result = $test->handles(POLLIN | POLLERR | POLLHUP);
  $test->remove($handle);

  return !!$result;
}

sub is_running { croak 'Method "is_running" not implemented by subclass' }
sub one_tick   { croak 'Method "one_tick" not implemented by subclass' }
sub recurring  { croak 'Method "recurring" not implemented by subclass' }
sub remove     { croak 'Method "remove" not implemented by subclass' }
sub start      { croak 'Method "start" not implemented by subclass' }
sub stop       { croak 'Method "stop" not implemented by subclass' }
sub timer      { croak 'Method "timer" not implemented by subclass' }
sub watch      { croak 'Method "watch" not implemented by subclass' }

1;

=head1 NAME

Mojo::Reactor - Low level event reactor base class

=head1 SYNOPSIS

  package Mojo::Reactor::MyEventLoop;
  use Mojo::Base 'Mojo::Reactor';

  $ENV{MOJO_REACTOR} ||= 'Mojo::Reactor::MyEventLoop';

  sub again      {...}
  sub io         {...}
  sub is_running {...}
  sub one_tick   {...}
  sub recurring  {...}
  sub remove     {...}
  sub start      {...}
  sub stop       {...}
  sub timer      {...}
  sub watch      {...}

=head1 DESCRIPTION

L<Mojo::Reactor> is an abstract base class for low level event reactors.

=head1 EVENTS

L<Mojo::Reactor> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 error

  $reactor->on(error => sub {
    my ($reactor, $err) = @_;
    ...
  });

Emitted safely for exceptions caught in callbacks.

  $reactor->on(error => sub {
    my ($reactor, $err) = @_;
    say "Something very bad happened: $err";
  });

=head1 METHODS

L<Mojo::Reactor> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 again

  $reactor->again($id);

Restart active timer. Meant to be overloaded in a subclass.

=head2 detect

  my $class = Mojo::Reactor->detect;

Detect and load the best reactor implementation available, will try the value
of the MOJO_REACTOR environment variable, L<Mojo::Reactor::EV> or
L<Mojo::Reactor::Poll>.

  # Instantiate best reactor implementation available
  my $reactor = Mojo::Reactor->detect->new;

=head2 io

  $reactor = $reactor->io($handle => sub {...});

Watch handle for I/O events, invoking the callback whenever handle becomes
readable or writable. Meant to be overloaded in a subclass.

  # Callback will be invoked twice if handle becomes readable and writable
  $reactor->io($handle => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Handle is writable' : 'Handle is readable';
  });

=head2 is_readable

  my $success = $reactor->is_readable($handle);

Quick non-blocking check if a handle is readable, useful for identifying
tainted sockets.

=head2 is_running

  my $success = $reactor->is_running;

Check if reactor is running. Meant to be overloaded in a subclass.

=head2 one_tick

  $reactor->one_tick;

Run reactor until an event occurs. Note that this method can recurse back into
the reactor, so you need to be careful. Meant to be overloaded in a subclass.

  # Don't block longer than 0.5 seconds
  my $id = $reactor->timer(0.5 => sub {});
  $reactor->one_tick;
  $reactor->remove($id);

=head2 recurring

  my $id = $reactor->recurring(0.25 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds. Meant to be overloaded in a subclass.

  # Invoke as soon as possible
  $reactor->recurring(0 => sub { say 'Reactor tick.' });

=head2 remove

  my $success = $reactor->remove($handle);
  my $success = $reactor->remove($id);

Remove handle or timer. Meant to be overloaded in a subclass.

=head2 start

  $reactor->start;

Start watching for I/O and timer events, this will block until C<stop> is
called. Note that some reactors stop automatically if there are no events
being watched anymore. Meant to be overloaded in a subclass.

=head2 stop

  $reactor->stop;

Stop watching for I/O and timer events. Meant to be overloaded in a subclass.

=head2 timer

  my $id = $reactor->timer(0.5 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds. Meant to be overloaded in a subclass.

  # Invoke as soon as possible
  $reactor->timer(0 => sub { say 'Next tick.' });

=head2 watch

  $reactor = $reactor->watch($handle, $readable, $writable);

Change I/O events to watch handle for with true and false values. Meant to be
overloaded in a subclass. Note that this method requires an active I/O
watcher.

  # Watch only for readable events
  $reactor->watch($handle, 1, 0);

  # Watch only for writable events
  $reactor->watch($handle, 0, 1);

  # Watch for readable and writable events
  $reactor->watch($handle, 1, 1);

  # Pause watching for events
  $reactor->watch($handle, 0, 0);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
