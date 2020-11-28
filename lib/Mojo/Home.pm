package Mojo::Home;
use Mojo::Base 'Mojo::File';

use Mojo::Util qw(class_to_path);

sub detect {
  my ($self, $class) = @_;

  # Environment variable
  my $home;
  if ($ENV{MOJO_HOME}) { $home = Mojo::File->new($ENV{MOJO_HOME})->to_array }

  # Location of the application class (Windows mixes backslash and slash)
  elsif ($class && (my $path = $INC{my $file = class_to_path $class})) {
    $home = Mojo::File->new($path)->to_array;
    splice @$home, (my @dummy = split(/\//, $file)) * -1;
    @$home && $home->[-1] eq $_ && pop @$home for qw(lib blib);
  }

  $$self = Mojo::File->new(@$home)->to_abs->to_string if $home;
  return $self;
}

sub rel_file { shift->child(split(/\//, shift)) }

1;

=encoding utf8

=head1 NAME

Mojo::Home - Home sweet home

=head1 SYNOPSIS

  use Mojo::Home;

  # Find and manage the project root directory
  my $home = Mojo::Home->new;
  $home->detect;
  say $home->child('templates', 'layouts', 'default.html.ep');
  say "$home";

=head1 DESCRIPTION

L<Mojo::Home> is a container for home directories based on L<Mojo::File>.

=head1 METHODS

L<Mojo::Home> inherits all methods from L<Mojo::File> and implements the following new ones.

=head2 detect

  $home = $home->detect;
  $home = $home->detect('My::App');

Detect home directory from the value of the C<MOJO_HOME> environment variable or the location of the application class.

=head2 rel_file

  my $path = $home->rel_file('foo/bar.html');

Return a new L<Mojo::Home> object relative to the home directory.

=head1 OPERATORS

L<Mojo::Home> inherits all overloaded operators from L<Mojo::File>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
