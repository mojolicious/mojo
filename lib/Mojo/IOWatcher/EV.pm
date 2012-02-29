package Mojo::IOWatcher::EV;
use Mojo::Base 'Mojo::IOWatcher';

use EV 4.0;
use Scalar::Util 'weaken';

my $EV;

sub DESTROY { undef $EV }

# We have to fall back to Mojo::IOWatcher, since EV is unique
sub new { $EV++ ? Mojo::IOWatcher->new : shift->SUPER::new }

sub is_running {EV::depth}

sub recurring { shift->_timer(shift, 1, @_) }

# "Wow, Barney. You brought a whole beer keg.
#  Yeah... where do I fill it up?"
sub start {EV::run}

sub stop { EV::break(EV::BREAK_ONE) }

sub timer { shift->_timer(shift, 0, @_) }

sub watch {
  my ($self, $handle, $read, $write) = @_;

  my $fd = fileno $handle;
  my $h  = $self->{handles}->{$fd};
  my $mode;
  if ($read && $write) { $mode = EV::READ | EV::WRITE }
  elsif ($read)  { $mode = EV::READ }
  elsif ($write) { $mode = EV::WRITE }
  else           { delete $h->{watcher} }
  if (my $w = $h->{watcher}) { $w->set($fd, $mode) }
  elsif ($mode) {
    weaken $self;
    $h->{watcher} = EV::io($fd, $mode, sub { $self->_io($fd, @_) });
  }

  return $self;
}

sub _io {
  my ($self, $fd, $w, $revents) = @_;
  my $handles = $self->{handles};
  my $h       = $handles->{$fd};
  $self->_sandbox('Read', $h->{cb}, $h->{handle}, 0) if EV::READ &$revents;
  $self->_sandbox('Write', $h->{cb}, $h->{handle}, 1)
    if EV::WRITE &$revents && $handles->{$fd};
}

# "It's great! We can do *anything* now that Science has invented Magic."
sub _timer {
  my ($self, $after, $recurring, $cb) = @_;
  $after ||= '0.0001';

  my $id = $self->SUPER::_timer($cb);
  weaken $self;
  $self->{timers}->{$id}->{watcher} = EV::timer(
    $after,
    $recurring ? $after : 0,
    sub {
      my $w = shift;
      $self->_sandbox("Timer $id", $self->{timers}->{$id}->{cb});
      delete $self->{timers}->{$id} unless $recurring;
    }
  );

  return $id;
}

1;
__END__

=head1 NAME

Mojo::IOWatcher::EV - EV non-blocking I/O watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher::EV;

  my $watcher = Mojo::IOWatcher::EV->new;

=head1 DESCRIPTION

L<Mojo::IOWatcher::EV> is a minimalistic non-blocking I/O watcher with
C<libev> support. Note that this module is EXPERIMENTAL and might change
without warning!

=head1 EVENTS

L<Mojo::IOWatcher::EV> inherits all events from L<Mojo::IOWatcher>.

=head1 METHODS

L<Mojo::IOWatcher::EV> inherits all methods from L<Mojo::IOWatcher> and
implements the following new ones.

=head2 C<new>

  my $watcher = Mojo::IOWatcher::EV->new;

Construct a new L<Mojo::IOWatcher::EV> object.

=head2 C<is_running>

  my $success = $watcher->is_running;

Check if watcher is running.

=head2 C<recurring>

  my $id = $watcher->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of time in seconds.

=head2 C<start>

  $watcher->start;

Start watching for I/O and timer events, this will block until C<stop> is
called or no events are being watched anymore.

=head2 C<stop>

  $watcher->stop;

Stop watching for I/O and timer events.

=head2 C<timer>

  my $id = $watcher->timer(3 => sub {...});

Create a new timer, invoking the callback after a given amount of time in
seconds.

=head2 C<watch>

  $watcher = $watcher->watch($handle, $read, $write);

Change I/O events to watch handle for.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
