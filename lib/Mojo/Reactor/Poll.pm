package Mojo::Reactor::Poll;
use Mojo::Base 'Mojo::Reactor';

use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use List::Util 'min';
use Mojo::Util 'md5_sum';
use Time::HiRes qw/time usleep/;

# "I don't know.
#  Can I really betray my country?
#  I say the Pledge of Allegiance every day.
#  You pledge allegiance to the flag.
#  And the flag is made in China."
sub io {
  my ($self, $handle, $cb) = @_;
  $self->{io}{fileno $handle} = {cb => $cb};
  return $self->watch($handle, 1, 1);
}

sub is_running { shift->{running} }

sub one_tick {
  my $self = shift;

  # Remember state
  my $running = $self->{running};
  $self->{running} = 1;

  # Wait for one event
  my $i    = 0;
  my $poll = $self->_poll;
  until ($i) {

    # Stop automatically if there is nothing to watch
    return $self->stop unless keys %{$self->{timers}} || keys %{$self->{io}};

    # Calculate ideal timeout based on timers
    my $min = min map { $_->{time} } values %{$self->{timers}};
    my $timeout = defined $min ? ($min - time) : 0.025;
    $timeout = 0 if $timeout < 0;

    # I/O
    if (keys %{$self->{io}}) {
      $poll->poll($timeout);
      ++$i and $self->_sandbox('Read', $self->{io}{fileno $_}{cb}, 0)
        for $poll->handles(POLLIN | POLLHUP | POLLERR);
      ++$i and $self->_sandbox('Write', $self->{io}{fileno $_}{cb}, 1)
        for $poll->handles(POLLOUT);
    }

    # Wait for timeout if poll can't be used
    elsif ($timeout) { usleep $timeout * 1000000 }

    # Timers
    while (my ($id, $t) = each %{$self->{timers} || {}}) {
      next unless $t->{time} <= time;

      # Recurring timer
      if (exists $t->{recurring}) { $t->{time} = time + $t->{recurring} }

      # Normal timer
      else { $self->remove($id) }

      # Handle timer
      ++$i and $self->_sandbox("Timer $id", $t->{cb}) if $t->{cb};
    }
  }

  # Restore state if necessary
  $self->{running} = $running if $self->{running};
}

sub recurring { shift->_timer(1, @_) }

sub remove {
  my ($self, $remove) = @_;
  return delete shift->{timers}{shift()} unless ref $remove;
  $self->_poll->remove($remove);
  return delete $self->{io}{fileno $remove};
}

sub start {
  my $self = shift;
  return if $self->{running}++;
  $self->one_tick while $self->{running};
}

sub stop { delete shift->{running} }

# "Bart, how did you get a cellphone?
#  The same way you got me, by accident on a golf course."
sub timer { shift->_timer(0, @_) }

sub watch {
  my ($self, $handle, $read, $write) = @_;

  my $poll = $self->_poll;
  $poll->remove($handle);
  if ($read && $write) { $poll->mask($handle, POLLIN | POLLOUT) }
  elsif ($read)  { $poll->mask($handle, POLLIN) }
  elsif ($write) { $poll->mask($handle, POLLOUT) }

  return $self;
}

sub _poll { shift->{poll} ||= IO::Poll->new }

sub _sandbox {
  my ($self, $desc, $cb) = (shift, shift, shift);
  return if eval { $self->$cb(@_); 1 };
  $self->once(error => sub { warn $_[1] })
    unless $self->has_subscribers('error');
  $self->emit_safe(error => "$desc failed: $@");
}

sub _timer {
  my ($self, $recurring, $after, $cb) = @_;
  my $id;
  do { $id = md5_sum('t' . time . rand 999) } while $self->{timers}{$id};
  my $t = $self->{timers}{$id} = {cb => $cb, time => time + $after};
  $t->{recurring} = $after if $recurring;
  return $id;
}

1;

=head1 NAME

Mojo::Reactor::Poll - Low level event reactor with poll support

=head1 SYNOPSIS

  use Mojo::Reactor::Poll;

  # Watch if handle becomes readable or writable
  my $reactor = Mojo::Reactor::Poll->new;
  $reactor->io($handle => sub {
    my ($reactor, $writable) = @_;
    say $writable ? 'Handle is writable' : 'Handle is readable';
  });

  # Add a timer
  $reactor->timer(15 => sub {
    my $reactor = shift;
    $reactor->remove($handle);
    say 'Timeout!';
  });

  # Start reactor if necessary
  $reactor->start unless $reactor->is_running;

=head1 DESCRIPTION

L<Mojo::Reactor::Poll> is a low level event reactor based on L<IO::Poll>.

=head1 EVENTS

L<Mojo::Reactor::Poll> inherits all events from L<Mojo::Reactor>.

=head1 METHODS

L<Mojo::Reactor::Poll> inherits all methods from L<Mojo::Reactor> and
implements the following new ones.

=head2 C<io>

  $reactor = $reactor->io($handle => sub {...});

Watch handle for I/O events, invoking the callback whenever handle becomes
readable or writable.

=head2 C<is_running>

  my $success = $reactor->is_running;

Check if reactor is running.

=head2 C<one_tick>

  $reactor->one_tick;

Run reactor until an event occurs or no events are being watched anymore. Note
that this method can recurse back into the reactor, so you need to be careful.

=head2 C<recurring>

  my $id = $reactor->recurring(0.25 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds.

=head2 C<remove>

  my $success = $reactor->remove($handle);
  my $success = $reactor->remove($id);

Remove handle or timer.

=head2 C<start>

  $reactor->start;

Start watching for I/O and timer events, this will block until C<stop> is
called or no events are being watched anymore.

=head2 C<stop>

  $reactor->stop;

Stop watching for I/O and timer events.

=head2 C<timer>

  my $id = $reactor->timer(0.5 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds.

=head2 C<watch>

  $reactor = $reactor->watch($handle, $readable, $writable);

Change I/O events to watch handle for with C<true> and C<false> values.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
