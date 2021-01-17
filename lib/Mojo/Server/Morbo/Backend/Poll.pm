package Mojo::Server::Morbo::Backend::Poll;
use Mojo::Base 'Mojo::Server::Morbo::Backend';

use Mojo::File qw(path);

sub modified_files {
  my $self = shift;

  my $cache = $self->{cache} //= {};
  my @files;
  for my $file (map { -f $_ && -r _ ? $_ : _list($_) } @{$self->watch}) {
    my ($size, $mtime) = (stat $file)[7, 9];
    next unless defined $size and defined $mtime;
    my $stats = $cache->{$file} ||= [$^T, $size];
    next if $mtime <= $stats->[0] && $size == $stats->[1];
    @$stats = ($mtime, $size);
    push @files, $file;
  }
  sleep $self->watch_timeout unless @files;

  return \@files;
}

sub _list { path(shift)->list_tree->map('to_string')->each }

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo::Backend::Poll - Morbo default backend

=head1 SYNOPSIS

  use Mojo::Server::Morbo::Backend::Poll;

  my $backend = Mojo::Server::Morbo::Backend::Poll->new;
  if (my $files = $backend->modified_files) {
    ...
  }

=head1 DESCRIPTION

L<Mojo::Server::Morbo::Backend:Poll> is the default backend for L<Mojo::Server::Morbo>.

=head1 ATTRIBUTES

L<Mojo::Server::Morbo::Backend::Poll> inherits all attributes from L<Mojo::Server::Morbo::Backend>.

=head1 METHODS

L<Mojo::Server::Morbo::Backend::Poll> inherits all methods from L<Mojo::Server::Morbo::Backend> and implements the
following new ones.

=head2 modified_files

  my $files = $backend->modified_files;

Check file size and mtime to determine which files have changed, this is not particularly efficient, but very portable.

  # All files that have been modified
  say for @{$backend->modified_files};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
