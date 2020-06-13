package Mojo::Server::Morbo::Backend;
use Mojo::Base -base;

use Carp qw(croak);

has watch         => sub { [qw(lib templates)] };
has watch_timeout => sub { $ENV{MOJO_MORBO_TIMEOUT} || 1 };

sub modified_files { croak 'Method "modified_files" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo::Backend - Morbo backend base class

=head1 SYNOPSIS

  package Mojo::Server::Morbo::Backend::Inotify:
  use Mojo::Base 'Mojo::Server::Morbo::Backend';

  sub modified_files {...}

=head1 DESCRIPTION

L<Mojo::Server::Morbo::Backend> is an abstract base class for Morbo backends, like
L<Mojo::Server::Morbo::Backend::Poll>.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo::Backend> implements the following attributes.

=head2 watch

  my $watch = $backend->watch;
  $backend  = $backend->watch(['/home/sri/my_app']);

Files and directories to watch for changes, defaults to the application script as well as the C<lib> and C<templates>
directories in the current working directory.

=head2 watch_timeout

  my $timeout = $backend->watch_timeout;
  $backend    = $backend->watch_timeout(10);

Maximum amount of time in seconds a backend may block when waiting for files to change, defaults to the value of the
C<MOJO_MORBO_TIMEOUT> environment variable or C<1>.

=head1 METHODS

L<Mojo::Server::Morbo::Backend> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 modified_files

  my $files = $backend->modified_files;

Check if files from L</"watch"> have been modified since the last check and return an array reference with the results.
Meant to be overloaded in a subclass.

  # All files that have been modified
  say for @{$backend->modified_files};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
