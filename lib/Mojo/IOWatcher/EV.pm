package Mojo::IOWatcher::EV;
use Mojo::Base 'Mojo::IOWatcher';

use EV 4.0;
use Scalar::Util 'weaken';

my $EV;

sub DESTROY { undef $EV }

# We have to fall back to Mojo::IOWatcher, since EV is unique
sub new { $EV++ ? Mojo::IOWatcher->new : shift->SUPER::new }

sub not_writing {
  my ($self, $handle) = @_;

  my $fd = fileno $handle;
  my $h  = $self->{handles}->{$fd};
  if (my $w = $h->{watcher}) { $w->set($fd, EV::READ) }
  else {
    weaken $self;
    $h->{watcher} = EV::io($fd, EV::READ, sub { $self->_io($fd, @_) });
  }

  return $self;
}

sub recurring { shift->_timer(shift, 1, @_) }

sub remove {
  my ($self, $handle) = @_;
  delete $self->{handles}->{fileno $handle};
  return $self;
}

# "Wow, Barney. You brought a whole beer keg.
#  Yeah... where do I fill it up?"
sub start {EV::run}

sub stop { EV::break(EV::BREAK_ONE) }

sub timer { shift->_timer(shift, 0, @_) }

sub writing {
  my ($self, $handle) = @_;

  my $fd = fileno $handle;
  my $h  = $self->{handles}->{$fd};
  if (my $w = $h->{watcher}) { $w->set($fd, EV::WRITE | EV::READ) }
  else {
    weaken $self;
    $h->{watcher} =
      EV::io($fd, EV::WRITE | EV::READ, sub { $self->_io($fd, @_) });
  }

  return $self;
}

sub _io {
  my ($self, $fd, $w, $revents) = @_;
  my $handles = $self->{handles};
  my $h       = $handles->{$fd};
  $self->_sandbox('Read', $h->{on_readable}, $h->{handle})
    if EV::READ &$revents;
  $self->_sandbox('Write', $h->{on_writable}, $h->{handle})
    if EV::WRITE &$revents && $handles->{$fd};
}

# "It's great! We can do *anything* now that Science has invented Magic."
sub _timer {
  my $self      = shift;
  my $after     = shift || '0.0001';
  my $recurring = shift;
  my $cb        = shift;

  my $id = $self->SUPER::_timer($cb);
  weaken $self;
  $self->{timers}->{$id}->{watcher} = EV::timer(
    $after,
    $recurring ? $after : 0,
    sub {
      my $w = shift;
      $self->_sandbox("Timer $id", $self->{timers}->{$id}->{cb}, $id);
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

=head1 DESCRIPTION

L<Mojo::IOWatcher::EV> is a minimalistic non-blocking I/O watcher with
C<libev> support.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOWatcher::EV> inherits all methods from L<Mojo::IOWatcher> and
implements the following new ones.

=head2 C<new>

  my $watcher = Mojo::IOWatcher::EV->new;

Construct a new L<Mojo::IOWatcher::EV> object.

=head2 C<not_writing>

  $watcher = $watcher->not_writing($handle);

Only watch handle for readable events.

=head2 C<recurring>

  my $id = $watcher->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of seconds.

=head2 C<remove>

  $watcher = $watcher->remove($handle);

Remove handle.

=head2 C<start>

  $watcher->start;

Start watching for I/O and timer events.

=head2 C<stop>

  $watcher->stop;

Stop watching for I/O and timer events.

=head2 C<timer>

  my $id = $watcher->timer(3 => sub {...});

Create a new timer, invoking the callback after a given amount of seconds.

=head2 C<writing>

  $watcher = $watcher->writing($handle);

Watch handle for readable and writable events.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
