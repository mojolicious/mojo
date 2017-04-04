package Mojo::Server::Morbo::Backend;
use Mojo::Base -base;

use Carp 'croak';

has watch => sub { [qw(lib templates)] };
has watch_timeout => sub { $ENV{MORBO_BACKEND_TIMEOUT} || 1 };

sub modified_files {
  croak 'Method "modified_files" not implemented by subclass';
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo::Backend - Morbo backend base class

=head1 SYNOPSIS

  package Mojo::Server::Morbo::Backend::Inotify:
  use Mojo::Base 'Mojo::Server::Morbo::Backend';

  sub modified_files {...}

=head1 DESCRIPTION

L<Mojo::Server::Morbo::Backend> is an abstract base class for the morbo
auto-reloader backend. The default included with Mojo is
L<Mojo::Server::Morbo::Backend::Poll>.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo::Backend> implements the following attributes.

=head2 watch

  my $watch = $backend->watch;
  $backend  = $backend->watch(['/home/sri/my_app']);

Files and directories to watch for changes, defaults to the application script
as well as the C<lib> and C<templates> directories in the current working
directory.

=head2 watch_timeout

  my $watch_timeout = $backend->watch_timeout;
  $backend          = $backend->watch_timeout(10);

Backends should not block longer than this many seconds to wait for events. Defaults
to 1 or the MORBO_BACKEND_TIMEOUT environment variable.

=head1 METHODS

L<Mojo::Server::Morbo::Backend> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 modified_files

  my $files = $backend->modified_files;

Check if files from L</"watch"> have been modified since the last check and
return an array reference with the results.

  # All files that have been modified
  say for @{$backend->modified_files};

Meant to be implemented in a subclass. Make sure your implementation uses
the L</"watch_timeout"> attribute to return for signal handling.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
