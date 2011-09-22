package Mojolicious::Command::generate::gitignore;
use Mojo::Base 'Mojo::Command';

has description => <<'EOF';
Generate ".gitignore".
EOF
has usage => <<"EOF";
usage: $0 generate gitignore
EOF

# "I want to see the edge of the universe.
#  Ooh, that sounds cool.
#  It's funny, you live in the universe, but you never get to do this things
#  until someone comes to visit."
sub run {
  my $self = shift;
  $self->render_to_rel_file('gitignore', '.gitignore');
  $self->chmod_file('.gitignore', 0644);
}

1;
__DATA__

@@ gitignore
.*
!.gitignore
!.perltidyrc
*~
blib
Makefile*
!Makefile.PL
*META.*
MANIFEST*
!MANIFEST.SKIP
pm_to_blib

__END__
=head1 NAME

Mojolicious::Command::generate::gitignore - Gitignore generator command

=head1 SYNOPSIS

  use Mojolicious::Command::generate::gitignore;

  my $gitignore = Mojolicious::Command::generate::gitignore->new;
  $gitignore->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::generate::gitignore> is a C<.gitignore> generator.

=head1 ATTRIBUTES

L<Mojolicious::Command::generate::gitignore> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

  my $description = $gitignore->description;
  $gitignore      = $gitignore->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage  = $gitignore->usage;
  $gitignore = $gitignore->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::generate::gitignore> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

  $gitignore->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
