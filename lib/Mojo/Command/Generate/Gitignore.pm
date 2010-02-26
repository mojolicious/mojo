# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Generate::Gitignore;

use strict;
use warnings;

use base 'Mojo::Command';

__PACKAGE__->attr(description => <<'EOF');
Generate .gitignore.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 generate gitignore
EOF

# I want to see the edge of the universe.
# Ooh, that sounds cool.
# It's funny, you live in the universe, but you never get to do this things
# until someone comes to visit.
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
META.yml
MANIFEST*
!MANIFEST.SKIP
pm_to_blib
__END__
=head1 NAME

Mojo::Command::Generate::Gitignore - Gitignore Generator Command

=head1 SYNOPSIS

    use Mojo::Command::Generate::Gitignore;

    my $gitignore = Mojo::Command::Generate::Gitignore->new;
    $gitignore->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Generate::Gitignore> is a C<.gitignore> generator.

=head1 ATTRIBUTES

L<Mojo::Command::Generate::Gitignore> inherits all attributes from
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

L<Mojo::Command::Generate::Gitignore> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

    $gitignore = $gitignore->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
