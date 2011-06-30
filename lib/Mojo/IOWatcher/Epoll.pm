package Mojo::IOWatcher::Epoll;
use Mojo::Base 'Mojo::IOWatcher';

use IO::Epoll 0.02 ':compat';
use Time::HiRes 'usleep';

# "And America has so many enemies.
#  Iran, Iraq, China, Mordor, the hoochies that laid low Tiger Woods,
#  undesirable immigrants - by which I mean everyone that came after me,
#  including my children..."
sub _poll { shift->{poll} ||= IO::Epoll->new }

1;
__END__

=head1 NAME

Mojo::IOWatcher::Epoll - Epoll Async IO Watcher

=head1 SYNOPSIS

  use Mojo::IOWatcher::Epoll;

=head1 DESCRIPTION

L<Mojo::IOWatcher> is a minimalistic async io watcher with C<epoll> support.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOWatcher::Epoll> inherits all methods from L<Mojo::IOWatcher>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
