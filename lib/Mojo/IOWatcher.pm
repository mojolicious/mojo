package Mojo::IOWatcher;
use Mojo::Base -base;

use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use Mojo::Loader;
use Mojo::Util 'md5_sum';
use Time::HiRes qw/time usleep/;

use constant DEBUG => $ENV{MOJO_IOWATCHER_DEBUG} || 0;

# "I don't know.
#  Can I really betray my country?
#  I say the Pledge of Allegiance every day.
#  You pledge allegiance to the flag.
#  And the flag is made in China."
sub change {
  my ($self, $handle, $read, $write) = @_;

  my $poll = $self->_poll;
  $poll->remove($handle);
  if ($read && $write) { $poll->mask($handle, POLLIN | POLLOUT) }
  elsif ($read)  { $poll->mask($handle, POLLIN) }
  elsif ($write) { $poll->mask($handle, POLLOUT) }

  return $self;
}

sub detect {
  my $try = $ENV{MOJO_IOWATCHER} || 'Mojo::IOWatcher::EV';
  return $try unless Mojo::Loader->load($try);
  return 'Mojo::IOWatcher';
}

sub drop_handle {
  my ($self, $handle) = @_;
  delete $self->{handles}->{fileno $handle};
  $self->_poll->remove($handle);
}

sub drop_timer { delete shift->{timers}->{shift()} }

sub is_readable {
  my ($self, $handle) = @_;

  # Make sure we watch for readable and writable events
  my $test = $self->{test} ||= IO::Poll->new;
  $test->mask($handle, POLLIN);
  $test->poll(0);
  my $result = $test->handles(POLLIN | POLLERR | POLLHUP);
  $test->remove($handle);

  return !!$result;
}

# "This was such a pleasant St. Patrick's Day until Irish people showed up."
sub recurring { shift->_timer(pop, after => pop, recurring => time) }

sub start {
  my $self = shift;
  return if $self->{running}++;
  $self->_one_tick while $self->{running};
}

sub stop { delete shift->{running} }

# "Bart, how did you get a cellphone?
#  The same way you got me, by accident on a golf course."
sub timer { shift->_timer(pop, after => pop, started => time) }

sub watch {
  my $self   = shift;
  my $handle = shift;
  my $args   = {@_, handle => $handle};
  $self->{handles}->{fileno $handle} = $args;
  $self->change($handle, 1, $args->{on_writable});
  return $self;
}

sub _timer {
  my $self = shift;
  my $cb   = shift;
  my $t    = {cb => $cb, @_};
  my $id;
  do { $id = md5_sum('t' . time . rand 999) } while $self->{timers}->{$id};
  $self->{timers}->{$id} = $t;
  return $id;
}

sub _one_tick {
  my $self = shift;

  # I/O
  my $poll = $self->_poll;
  $poll->poll('0.025');
  my $handles = $self->{handles};
  $self->_sandbox('Read', $handles->{fileno $_}->{on_readable}, $_)
    for $poll->handles(POLLIN | POLLHUP | POLLERR);
  $self->_sandbox('Write', $handles->{fileno $_}->{on_writable}, $_)
    for $poll->handles(POLLOUT);

  # Wait for timeout
  usleep 25000 unless keys %{$self->{handles}};

  # Timers
  my $timers = $self->{timers} || {};
  for my $id (keys %$timers) {
    my $t = $timers->{$id};
    my $after = $t->{after} || 0;
    if ($after <= time - ($t->{started} || $t->{recurring} || 0)) {
      warn "TIMER $id\n" if DEBUG;

      # Normal timer
      if ($t->{started}) { $self->drop_timer($id) }

      # Recurring timer
      elsif ($after && $t->{recurring}) { $t->{recurring} += $after }

      # Handle timer
      if (my $cb = $t->{cb}) { $self->_sandbox("Timer $id", $cb, $id) }
    }
  }
}

sub _poll { shift->{poll} ||= IO::Poll->new }

sub _sandbox {
  my $self = shift;
  my $desc = shift;
  return unless my $cb = shift;
  warn "$desc failed: $@" unless eval { $self->$cb(@_); 1 };
}

1;
__END__

=head1 NAME

Mojo::IOWatcher - Non-blocking I/O watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher;

  # Watch if handle becomes readable
  my $watcher = Mojo::IOWatcher->new;
  $watcher->watch($handle, on_readable => sub {
    my ($watcher, $handle) = @_;
    ...
  });

  # Add a timer
  $watcher->timer(15 => sub {
    my $watcher = shift;
    $watcher->drop_handle($handle);
    say "Timeout!";
  });

  # Start and stop watcher
  $watcher->start;
  $watcher->stop;

=head1 DESCRIPTION

L<Mojo::IOWatcher> is a minimalistic non-blocking I/O watcher and the
foundation of L<Mojo::IOLoop>.
L<Mojo::IOWatcher::EV> is a good example for its extensibility.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOWatcher> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<detect>

  my $class = Mojo::IOWatcher->detect;

Detect and load the best watcher implementation available, will try the value
of the C<MOJO_IOWATCHER> environment variable or L<Mojo::IOWatcher::EV>.

=head2 C<change>

  $watcher = $watcher->change($handle, $read, $write);

Change I/O events to watch handle for.

  $watcher->change($handle, 0, 1);

=head2 C<drop_handle>

  $watcher->drop_handle($handle);

Drop handle.

=head2 C<drop_timer>

  my $success = $watcher->drop_timer($id);

Drop timer.

=head2 C<is_readable>

  my $success = $watcher->is_readable($handle);

Quick check if a handle is readable, useful for identifying tainted
sockets.

=head2 C<recurring>

  my $id = $watcher->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of seconds.

=head2 C<start>

  $watcher->start;

Start watching for I/O and timer events.

=head2 C<stop>

  $watcher->stop;

Stop watching for I/O and timer events.

=head2 C<timer>

  my $id = $watcher->timer(3 => sub {...});

Create a new timer, invoking the callback after a given amount of seconds.

=head2 C<watch>

  $watcher = $watcher->watch($handle, on_readable => sub {...});

Watch handle for I/O events.

These options are currently available:

=over 2

=item C<on_readable>

Callback to be invoked once the handle becomes readable.

=item C<on_writable>

Callback to be invoked once the handle becomes writable.

=back

=head1 DEBUGGING

You can set the C<MOJO_IOWATCHER_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_IOWATCHER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
