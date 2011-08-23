package Mojo::IOWatcher;
use Mojo::Base -base;

use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use Time::HiRes qw/time usleep/;

use constant DEBUG => $ENV{MOJO_IOWATCHER_DEBUG} || 0;

# "I don't know.
#  Can I really betray my country?
#  I say the Pledge of Allegiance every day.
#  You pledge allegiance to the flag.
#  And the flag is made in China."
sub add {
  my $self   = shift;
  my $handle = shift;
  my $args   = {@_, handle => $handle};

  $self->{handles}->{fileno $handle} = $args;
  $args->{on_writable}
    ? $self->writing($handle)
    : $self->not_writing($handle);

  return $self;
}

sub cancel {
  my ($self, $id) = @_;
  return 1 if delete $self->{timers}->{$id};
  return;
}

sub detect {
  my $try = $ENV{MOJO_IOWATCHER} || 'Mojo::IOWatcher::EV';
  return $try if eval "use $try; 1";
  return 'Mojo::IOWatcher';
}

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

sub not_writing {
  my ($self, $handle) = @_;

  # Make sure we only watch for readable events
  my $poll = $self->_poll;
  $poll->remove($handle)
    if delete $self->{handles}->{fileno $handle}->{writing};
  $poll->mask($handle, POLLIN);

  return $self;
}

# "This was such a pleasant St. Patrick's Day until Irish people showed up."
sub one_tick {
  my ($self, $timeout) = @_;

  # I/O
  my $poll = $self->_poll;
  $poll->poll($timeout);
  my $handles = $self->{handles};
  $self->_sandbox('Read', $handles->{fileno $_}->{on_readable}, $_)
    for $poll->handles(POLLIN | POLLHUP | POLLERR);
  $self->_sandbox('Write', $handles->{fileno $_}->{on_writable}, $_)
    for $poll->handles(POLLOUT);

  # Wait for timeout
  usleep 1000000 * $timeout unless keys %{$self->{handles}};

  # Timers
  my $timers = $self->{timers} || {};
  for my $id (keys %$timers) {
    my $t = $timers->{$id};
    my $after = $t->{after} || 0;
    if ($after <= time - ($t->{started} || $t->{recurring} || 0)) {
      warn "TIMER $id\n" if DEBUG;

      # Normal timer
      if ($t->{started}) { $self->cancel($id) }

      # Recurring timer
      elsif ($after && $t->{recurring}) { $t->{recurring} += $after }

      # Handle timer
      if (my $cb = $t->{cb}) { $self->_sandbox("Timer $id", $cb, $id) }
    }
  }
}

sub recurring { shift->_timer(pop, after => pop, recurring => time) }

sub remove {
  my ($self, $handle) = @_;
  delete $self->{handles}->{fileno $handle};
  $self->_poll->remove($handle);
  return $self;
}

# "Bart, how did you get a cellphone?
#  The same way you got me, by accident on a golf course."
sub timer { shift->_timer(pop, after => pop, started => time) }

sub writing {
  my ($self, $handle) = @_;

  my $poll = $self->_poll;
  $poll->remove($handle);
  $poll->mask($handle, POLLIN | POLLOUT);
  $self->{handles}->{fileno $handle}->{writing} = 1;

  return $self;
}

sub _timer {
  my $self = shift;
  my $cb   = shift;
  my $t    = {cb => $cb, @_};
  (my $id) = "$t" =~ /0x([\da-f]+)/;
  $self->{timers}->{$id} = $t;
  return $id;
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

Mojo::IOWatcher - Non-Blocking I/O Watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher;

  # Watch if I/O handles become readable or writable
  my $watcher = Mojo::IOWatcher->new;
  $watcher->add($handle, on_readable => sub {
    my ($watcher, $handle) = @_;
    ...
  });

  # Use timers
  $watcher->timer(15 => sub {
    my $watcher = shift;
    $watcher->remove($handle);
    print "Timeout!\n";
  });

  # And loop!
  $watcher->one_tick('0.25') while 1;

=head1 DESCRIPTION

L<Mojo::IOWatcher> is a minimalistic non-blocking I/O watcher and the
foundation of L<Mojo::IOLoop>.
L<Mojo::IOWatcher::EV> is a good example for its extensibility.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOWatcher> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<add>

  $watcher = $watcher->add($handle, on_readable => sub {...});

Add handles and watch for I/O events.

These options are currently available:

=over 2

=item C<on_readable>

Callback to be invoked once the handle becomes readable.

=item C<on_writable>

Callback to be invoked once the handle becomes writable.

=back

=head2 C<cancel>

  my $success = $watcher->cancel($id);

Cancel timer.

=head2 C<detect>

  my $class = Mojo::IOWatcher->detect;

Detect and load the best watcher implementation available, will try the value
of the C<MOJO_IOWATCHER> environment variable or L<Mojo::IOWatcher::EV>.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<is_readable>

  my $readable = $watcher->is_readable($handle);

Quick check if a handle is readable, useful for identifying tainted
sockets.

=head2 C<not_writing>

  $watcher = $watcher->not_writing($handle);

Only watch handle for readable events.

=head2 C<one_tick>

  $watcher->one_tick('0.25');

Run for exactly one tick and watch for I/O and timer events.

=head2 C<recurring>

  my $id = $watcher->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of seconds.

=head2 C<remove>

  $watcher = $watcher->remove($handle);

Remove handle.

=head2 C<timer>

  my $id = $watcher->timer(3 => sub {...});

Create a new timer, invoking the callback after a given amount of seconds.

=head2 C<writing>

  $watcher = $watcher->writing($handle);

Watch handle for readable and writable events.

=head1 DEBUGGING

You can set the C<MOJO_IOWATCHER_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_IOWATCHER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
