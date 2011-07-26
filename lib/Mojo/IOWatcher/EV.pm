package Mojo::IOWatcher::EV;
use Mojo::Base 'Mojo::IOWatcher';

use EV;
use Scalar::Util 'weaken';

my $SINGLETON;

sub DESTROY { undef $SINGLETON }

# We have to fall back to Mojo::IOWatcher, since EV is unique
sub new { $SINGLETON++ ? Mojo::IOWatcher->new : shift->SUPER::new }

sub not_writing {
  my ($self, $handle) = @_;

  my $fd = fileno $handle;
  my $h  = $self->{handles}->{$fd};
  my $w  = $h->{watcher};
  if ($w) { $w->set($fd, EV::READ) if delete $h->{writing} }
  else {
    weaken $self;
    $h->{watcher} = EV::io($fd, EV::READ, sub { $self->_io($fd, @_) });
  }

  return $self;
}

# "Wow, Barney. You brought a whole beer keg.
#  Yeah... where do I fill it up?"
sub one_tick {
  my ($self, $timeout) = @_;
  my $w = EV::timer($timeout, 0, sub { EV::unloop(EV::BREAK_ONE) });
  EV::loop;
  undef $w;
}

sub recurring { shift->_timer(shift, 1, @_) }

sub remove {
  my ($self, $handle) = @_;
  delete $self->{handles}->{fileno $handle};
  return $self;
}

sub timer { shift->_timer(shift, 0, @_) }

sub writing {
  my ($self, $handle) = @_;

  my $fd = fileno $handle;
  my $h  = $self->{handles}->{$fd};
  my $w  = $h->{watcher};
  if ($w) { $w->set($fd, EV::WRITE | EV::READ) }
  else {
    weaken $self;
    $h->{watcher} =
      EV::io($fd, EV::WRITE | EV::READ, sub { $self->_io($fd, @_) });
  }
  $h->{writing} = 1;

  return $self;
}

sub _io {
  my ($self, $fd, $w, $revents) = @_;
  my $h = $self->{handles}->{$fd};
  $self->_sandbox('Read', $h->{on_readable}, $h->{handle})
    if EV::READ &$revents;
  $self->_sandbox('Write', $h->{on_writable}, $h->{handle})
    if EV::WRITE &$revents;
}

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

Mojo::IOWatcher::EV - EV Async I/O Watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher::EV;

=head1 DESCRIPTION

L<Mojo::IOWatcher::EV> is a minimalistic async I/O watcher with C<libev>
support.
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

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
