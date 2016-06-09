package Mojo::Reactor;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Config;
use Mojo::Loader 'load_class';

sub again { croak 'Method "again" not implemented by subclass' }

sub detect {
  my $default = 'Mojo::Reactor::' . ($Config{d_pseudofork} ? 'Poll' : 'EV');
  my $try = $ENV{MOJO_REACTOR} || $default;
  return load_class($try) ? 'Mojo::Reactor::Poll' : $try;
}

sub io         { croak 'Method "io" not implemented by subclass' }
sub is_running { croak 'Method "is_running" not implemented by subclass' }
sub next_tick  { croak 'Method "next_tick" not implemented by subclass' }
sub one_tick   { croak 'Method "one_tick" not implemented by subclass' }
sub recurring  { croak 'Method "recurring" not implemented by subclass' }
sub remove     { croak 'Method "remove" not implemented by subclass' }
sub reset      { croak 'Method "reset" not implemented by subclass' }
sub start      { croak 'Method "start" not implemented by subclass' }
sub stop       { croak 'Method "stop" not implemented by subclass' }
sub timer      { croak 'Method "timer" not implemented by subclass' }
sub watch      { croak 'Method "watch" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Mojo::Reactor - Low-level event reactor base class

=head1 SYNOPSIS

  package Mojo::Reactor::MyEventLoop;
  use Mojo::Base 'Mojo::Reactor';

  sub again      {...}
  sub io         {...}
  sub is_running {...}
  sub next_tick  {...}
  sub one_tick   {...}
  sub recurring  {...}
  sub remove     {...}
  sub reset      {...}
  sub start      {...}
  sub stop       {...}
  sub timer      {...}
  sub watch      {...}

=head1 DESCRIPTION

L<Mojo::Reactor> is an abstract base class for low-level event reactors, like
L<Mojo::Reactor::EV> and L<Mojo::Reactor::Poll>.

=head1 EVENTS

L<Mojo::Reactor> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 error

  $reactor->on(error => sub {
    my ($reactor, $err) = @_;
    ...
  });

Emitted for exceptions caught in callbacks, fatal if unhandled. Note that if
this event is unhandled or fails it might kill your program, so you need to be
careful.

  $reactor->on(error => sub {
    my ($reactor, $err) = @_;
    say "Something very bad happened: $err";
  });

=head1 METHODS

L<Mojo::Reactor> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 again

  $reactor->again($id);

Restart timer. Meant to be overloaded in a subclass. Note that this method
requires an active timer.

=head2 detect

  my $class = Mojo::Reactor->detect;

Detect and load the best reactor implementation available, will try the value
of the C<MOJO_REACTOR> environment variable, L<Mojo::Reactor::EV> or
L<Mojo::Reactor::Poll>.

  # Instantiate best reactor implementation available
  my $reactor = Mojo::Reactor->detect->new;

=head2 io

  $reactor = $reactor->io($handle => sub {...});

Watch handle for I/O events, invoking the callback whenever handle becomes
readable or writable. Meant to be overloaded in a subclass.

  # Callback will be executed twice if handle becomes readable and writable
  $reactor->io($handle => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Handle is writable' : 'Handle is readable';
  });

=head2 is_running

  my $bool = $reactor->is_running;

Check if reactor is running. Meant to be overloaded in a subclass.

=head2 next_tick

  my $undef = $reactor->next_tick(sub {...});

Execute callback as soon as possible, but not before returning or other
callbacks that have been registered with this method, always returns C<undef>.
Meant to be overloaded in a subclass.

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

=head2 remove

  my $bool = $reactor->remove($handle);
  my $bool = $reactor->remove($id);

Remove handle or timer. Meant to be overloaded in a subclass.

=head2 reset

  $reactor->reset;

Remove all handles and timers. Meant to be overloaded in a subclass.

=head2 start

  $reactor->start;

Start watching for I/O and timer events, this will block until L</"stop"> is
called. Note that some reactors stop automatically if there are no events being
watched anymore. Meant to be overloaded in a subclass.

  # Start reactor only if it is not running already
  $reactor->start unless $reactor->is_running;

=head2 stop

  $reactor->stop;

Stop watching for I/O and timer events. Meant to be overloaded in a subclass.

=head2 timer

  my $id = $reactor->timer(0.5 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds. Meant to be overloaded in a subclass.

=head2 watch

  $reactor = $reactor->watch($handle, $readable, $writable);

Change I/O events to watch handle for with true and false values. Meant to be
overloaded in a subclass. Note that this method requires an active I/O watcher.

  # Watch only for readable events
  $reactor->watch($handle, 1, 0);

  # Watch only for writable events
  $reactor->watch($handle, 0, 1);

  # Watch for readable and writable events
  $reactor->watch($handle, 1, 1);

  # Pause watching for events
  $reactor->watch($handle, 0, 0);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
