package Mojo::IOWatcher;
use Mojo::Base -base;

use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use Time::HiRes 'usleep';

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

  $self->{_handles}->{fileno $handle} = $args;
  $args->{on_writable}
    ? $self->writing($handle)
    : $self->not_writing($handle);

  $self;
}

sub cancel {
  my ($self, $id) = @_;
  delete $self->{$_}->{$id} and return 1 for qw/_timers _idle/;
  undef;
}

sub idle { shift->_event(_idle => shift) }

sub is_readable {
  my ($self, $handle) = @_;

  # Make sure we watch for readable and writable events
  my $test = $self->{_test} ||= IO::Poll->new;
  $test->mask($handle, POLLIN);
  $test->poll(0);
  my $result = $test->handles(POLLIN | POLLERR | POLLHUP);
  $test->remove($handle);

  !$result;
}

sub not_writing {
  my ($self, $handle) = @_;

  # Make sure we only watch for readable events
  my $poll = $self->_poll;
  $poll->remove($handle)
    if delete $self->{_handles}->{fileno $handle}->{writing};
  $poll->mask($handle, $self->POLLIN);

  $self;
}

sub on_readable {
  my ($self, $handle, $cb) = @_;
  $self->{_handles}->{fileno $handle}->{on_readable} = $cb;
  $self;
}

sub on_writable {
  my ($self, $handle, $cb) = @_;
  $self->{_handles}->{fileno $handle}->{on_writable} = $cb;
  $self;
}

# "This was such a pleasant St. Patrick's Day until Irish people showed up."
sub one_tick {
  my ($self, $timeout) = @_;

  # IO events
  my $activity = $self->watch($timeout);

  # Timers
  my $timers = $self->{_timers} || {};
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
      if (my $cb = $t->{cb}) {
        $self->_sandbox("Timer $id", $cb, $id);
        $activity++ if $t->{started};
      }
    }
  }

  # Idle
  unless ($activity) {
    for my $id (keys %{$self->{_idle} || {}}) {
      warn "IDLE $id\n" if DEBUG;
      $self->_sandbox("Idle $id", $self->{_idle}->{$id}->{cb}, $id);
    }
  }
}

sub recurring {
  my $self = shift;
  $self->_event(_timers => pop, after => pop, recurring => time);
}

sub remove {
  my ($self, $handle) = @_;
  delete $self->{_handles}->{fileno $handle};
  $self->_poll->remove($handle);
  $self;
}

# "Bart, how did you get a cellphone?
#  The same way you got me, by accident on a golf course."
sub timer {
  my $self = shift;
  $self->_event(_timers => pop, after => pop, started => time);
}

sub watch {
  my ($self, $timeout) = @_;

  # Check for IO events
  my $poll = $self->_poll;
  $poll->poll($timeout);
  my $activity;
  my $handles = $self->{_handles};
  for ($poll->handles($self->POLLIN | $self->POLLHUP | $self->POLLERR)) {
    $self->_sandbox('Read', $handles->{fileno $_}->{on_readable}, $_);
    $activity++;
  }
  for ($poll->handles($self->POLLOUT)) {
    $self->_sandbox('Write', $handles->{fileno $_}->{on_writable}, $_);
    $activity++;
  }

  # Wait for timeout
  usleep 1000000 * $timeout unless keys %{$self->{_handles}};

  $activity;
}

sub writing {
  my ($self, $handle) = @_;

  my $poll = $self->_poll;
  $poll->remove($handle);
  $poll->mask($handle, $self->POLLIN | $self->POLLOUT);
  $self->{_handles}->{fileno $handle}->{writing} = 1;

  $self;
}

sub _event {
  my $self = shift;
  my $pool = shift;
  my $cb   = shift;

  # Events have an id for easy removal
  my $e = {cb => $cb, @_};
  (my $id) = "$e" =~ /0x([\da-f]+)/;
  $self->{$pool}->{$id} = $e;

  $id;
}

sub _poll { shift->{_poll} ||= IO::Poll->new }

sub _sandbox {
  my $self = shift;
  my $desc = shift;
  my $cb   = shift;
  warn "$desc failed: $@" unless eval { $self->$cb(@_); 1 };
}

1;
__END__

=head1 NAME

Mojo::IOWatcher - Async IO Watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher;

  # Watch if io handles become readable or writable
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

L<Mojo::IOWatcher> is a minimalistic async io watcher that can be easily
extended for more scalability.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOWatcher> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<add>

  $watcher = $watcher->add($handle, on_readable => sub {...});

Add handles and watch for io events.

These options are currently available:

=over 2

=item C<on_readable>

Callback to be invoked once the handle becomes readable.

=item C<on_writable>

Callback to be invoked once the handle becomes writable.

=back

=head2 C<cancel>

  $watcher->cancel($id);

Cancel timer or idle event.

=head2 C<idle>

  my $id = $watcher->idle(sub {...});

Callback to be invoked on every tick if no other events occurred.

=head2 C<is_readable>

  my $readable = $watcher->is_readable($handle);

Quick check if a handle is readable, useful for identifying tainted
sockets.

=head2 C<not_writing>

  $watcher = $watcher->not_writing($handle);

Only watch handle for readable events.

=head2 C<on_readable>

  $watcher = $watcher->on_readable($handle, sub {...});

Callback to be invoked once the handle becomes readable.

=head2 C<on_writable>

  $watcher = $watcher->on_writable($handle, sub {...});

Callback to be invoked once the handle becomes writable.

=head2 C<one_tick>

  $watcher->one_tick('0.25');

Run for exactly one tick and watch for io, timer and idle events.

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

=head2 C<watch>

  $watcher->watch('0.25');

Run for exactly one tick and watch only for io events.

=head2 C<writing>

  $watcher = $watcher->writing($handle);

Watch handle for readable and writable events.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
