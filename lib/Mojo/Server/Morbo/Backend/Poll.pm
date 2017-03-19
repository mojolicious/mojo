package Mojo::Server::Morbo::Backend::Poll;
use Mojo::Base 'Mojo::Server::Morbo::Backend';

use Mojo::File 'path';

sub modified_files {
  my $self = shift;

  sleep $self->watch_timeout;
  my $cache = $self->{cache} ||= {};
  my @files;
  for my $file (map { -f $_ && -r _ ? $_ : _list($_) } @{$self->watch}) {
    my ($size, $mtime) = (stat $file)[7, 9];
    next unless defined $size and defined $mtime;
    my $stats = $cache->{$file} ||= [$^T, $size];
    next if $mtime <= $stats->[0] && $size == $stats->[1];
    @$stats = ($mtime, $size);
    push @files, $file;
  }

  return \@files;
}

sub _list { path(shift)->list_tree->map('to_string')->each }

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo::Backend::Poll - Morbo default backend class

=head1 SYNOPSIS

  my $backend = Mojo::Server::Morbo::Backend::Poll->new;
  if ($backend->modified_files) {...}

=head1 DESCRIPTION

L<Mojo::Server::Morbo::Backend:Poll> is the default reloader backend for
L<Mojo::Server::Morbo>.

=head1 METHODS

L<Mojo::Server::Morbo::Backend::Poll> inherits all methods from
L<Mojo::Server::Morbo::Backend>.

=head2 modified_files

Checks the mtime timestamp for all the watched files and returns
an array reference with any modified files.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
