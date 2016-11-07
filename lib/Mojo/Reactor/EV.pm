package Mojo::Reactor::EV;
use Mojo::Base 'Mojo::Reactor::Poll';

use Carp 'croak';
use EV 4.0;

my $EV;

sub DESTROY { undef $EV }

sub again {
  croak 'Timer not active' unless my $timer = shift->{timers}{shift()};
  $timer->{watcher}->again;
}

sub is_running { !!EV::depth }

# We have to fall back to Mojo::Reactor::Poll, since EV is unique
sub new { $EV++ ? Mojo::Reactor::Poll->new : shift->SUPER::new }

sub one_tick { EV::run(EV::RUN_ONCE) }

sub recurring { shift->_timer(1, @_) }

sub start {EV::run}

sub stop { EV::break(EV::BREAK_ALL) }

sub timer { shift->_timer(0, @_) }

sub watch {
  my ($self, $handle, $read, $write) = @_;

  my $fd = fileno $handle;
  croak 'I/O watcher not active' unless my $io = $self->{io}{$fd};

  my $mode = 0;
  $mode |= EV::READ  if $read;
  $mode |= EV::WRITE if $write;

  if ($mode == 0) { delete $io->{watcher} }
  elsif (my $w = $io->{watcher}) { $w->events($mode) }
  else {
    my $cb = sub {
      my ($w, $revents) = @_;
      $self->_try('I/O watcher', $self->{io}{$fd}{cb}, 0)
        if EV::READ & $revents;
      $self->_try('I/O watcher', $self->{io}{$fd}{cb}, 1)
        if EV::WRITE & $revents && $self->{io}{$fd};
    };
    $io->{watcher} = EV::io($fd, $mode, $cb);
  }

  return $self;
}

sub _timer {
  my ($self, $recurring, $after, $cb) = @_;
  $after ||= 0.0001 if $recurring;

  my $id      = $self->_id;
  my $wrapper = sub {
    delete $self->{timers}{$id} unless $recurring;
    $self->_try('Timer', $cb);
  };
  EV::now_update() if $after > 0;
  $self->{timers}{$id}{watcher} = EV::timer($after, $after, $wrapper);

  return $id;
}

1;

=encoding utf8

=head1 NAME

Mojo::Reactor::EV - Low-level event reactor with libev support

=head1 SYNOPSIS

  use Mojo::Reactor::EV;

  # Watch if handle becomes readable or writable
  my $reactor = Mojo::Reactor::EV->new;
  $reactor->io($first => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'First handle is writable' : 'First handle is readable';
  });

  # Change to watching only if handle becomes writable
  $reactor->watch($first, 0, 1);

  # Turn file descriptor into handle and watch if it becomes readable
  my $second = IO::Handle->new_from_fd($fd, 'r');
  $reactor->io($second => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Second handle is writable' : 'Second handle is readable';
  })->watch($second, 1, 0);

  # Add a timer
  $reactor->timer(15 => sub {
    my $reactor = shift;
    $reactor->remove($first);
    $reactor->remove($second);
    say 'Timeout!';
  });

  # Start reactor if necessary
  $reactor->start unless $reactor->is_running;

=head1 DESCRIPTION

L<Mojo::Reactor::EV> is a low-level event reactor based on L<EV> (4.0+).

=head1 EVENTS

L<Mojo::Reactor::EV> inherits all events from L<Mojo::Reactor::Poll>.

=head1 METHODS

L<Mojo::Reactor::EV> inherits all methods from L<Mojo::Reactor::Poll> and
implements the following new ones.

=head2 again

  $reactor->again($id);

Restart timer. Note that this method requires an active timer.

=head2 is_running

  my $bool = $reactor->is_running;

Check if reactor is running.

=head2 new

  my $reactor = Mojo::Reactor::EV->new;

Construct a new L<Mojo::Reactor::EV> object.

=head2 one_tick

  $reactor->one_tick;

Run reactor until an event occurs or no events are being watched anymore.

  # Don't block longer than 0.5 seconds
  my $id = $reactor->timer(0.5 => sub {});
  $reactor->one_tick;
  $reactor->remove($id);

=head2 recurring

  my $id = $reactor->recurring(0.25 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds.

=head2 start

  $reactor->start;

Start watching for I/O and timer events, this will block until L</"stop"> is
called or no events are being watched anymore.

  # Start reactor only if it is not running already
  $reactor->start unless $reactor->is_running;

=head2 stop

  $reactor->stop;

Stop watching for I/O and timer events.

=head2 timer

  my $id = $reactor->timer(0.5 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds.

=head2 watch

  $reactor = $reactor->watch($handle, $readable, $writable);

Change I/O events to watch handle for with true and false values. Note that
this method requires an active I/O watcher.

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
