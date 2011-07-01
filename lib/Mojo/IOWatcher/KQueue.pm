package Mojo::IOWatcher::KQueue;
use Mojo::Base 'Mojo::IOWatcher';

use IO::KQueue 0.34;

# "Wow, Barney. You brought a whole beer keg.
#  Yeah... where do I fill it up?"
sub not_writing {
  my ($self, $handle) = @_;

  my $fd     = fileno $handle;
  my $h      = $self->{handles}->{$fd};
  my $kqueue = $self->_kqueue;
  $kqueue->EV_SET($fd, EVFILT_READ, EV_ADD)
    unless defined $h->{writing};
  $kqueue->EV_SET($fd, EVFILT_WRITE, EV_DELETE) if $h->{writing};
  $h->{writing} = 0;

  return $self;
}

sub remove {
  my ($self, $handle) = @_;

  my $fd     = fileno $handle;
  my $h      = delete $self->{handles}->{$fd};
  my $kqueue = $self->_kqueue;
  $kqueue->EV_SET($fd, EVFILT_READ,  EV_DELETE) if defined $h->{writing};
  $kqueue->EV_SET($fd, EVFILT_WRITE, EV_DELETE) if $h->{writing};

  return $self;
}

sub watch {
  my ($self, $timeout) = @_;

  my @ret;
  eval { @ret = $self->_kqueue->kevent(1000 * $timeout) };
  for my $kev (@ret) {
    my ($fd, $filter, $flags, $fflags) = @$kev;
    my $h = $self->{handles}->{$fd};
    $self->_sandbox('Read', $h->{on_readable}, $h->{handle})
      if $filter == EVFILT_READ || $flags == EV_EOF;
    $self->_sandbox('Write', $h->{on_writable}, $h->{handle})
      if $filter == EVFILT_WRITE;
  }
}

sub writing {
  my ($self, $handle) = @_;

  my $fd = fileno $handle;
  my $h  = $self->{handles}->{$fd};
  $self->_kqueue->EV_SET($fd, EVFILT_READ, EV_ADD)
    unless defined $h->{writing};
  $self->_kqueue->EV_SET($fd, EVFILT_WRITE, EV_ADD) unless $h->{writing};
  $h->{writing} = 1;

  return $self;
}

sub _kqueue { shift->{kqueue} ||= IO::KQueue->new }

1;
__END__

=head1 NAME

Mojo::IOWatcher::KQueue - KQueue Async IO Watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher::KQueue;

=head1 DESCRIPTION

L<Mojo::IOWatcher> is a minimalistic async io watcher with C<kqueue> support.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOWatcher::KQueue> inherits all methods from L<Mojo::IOWatcher> and
implements the following new ones.

=head2 C<not_writing>

  $watcher = $watcher->not_writing($handle);

Only watch handle for readable events.

=head2 C<remove>

  $watcher = $watcher->remove($handle);

Remove handle.

=head2 C<watch>

  $watcher->watch('0.25');

Run for exactly one tick and watch only for io events.

=head2 C<writing>

  $watcher = $watcher->writing($handle);

Watch handle for readable and writable events.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
