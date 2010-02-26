# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Command::Generate;

use strict;
use warnings;

use base 'Mojo::Commands';

__PACKAGE__->attr(description => <<'EOF');
Generate files and directories from templates.
EOF
__PACKAGE__->attr(hint => <<"EOF");

See '$0 generate help GENERATOR' for more information on a specific generator.
EOF
__PACKAGE__->attr(message => <<"EOF");
usage: $0 generate GENERATOR [OPTIONS]

These generators are currently available:
EOF
__PACKAGE__->attr(namespaces => sub { ['Mojo::Command::Generate'] });
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 generate GENERATOR [OPTIONS]
EOF

# If The Flintstones has taught us anything,
# it's that pelicans can be used to mix cement.

1;
__END__

=head1 NAME

Mojo::Command::Generate - Generator Command

=head1 SYNOPSIS

    use Mojo::Command::Generate;

    my $generator = Mojo::Command::Generate->new;
    $generator->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Command::Generate> lists available generators.

=head1 ATTRIBUTES

L<Mojo::Command::Generate> inherits all attributes from L<Mojo::Commands> and
implements the following new ones.

=head2 C<description>

    my $description = $generator->description;
    $generator      = $generator->description('Foo!');

Short description of this command, used for the command list.

=head2 C<hint>

    my $hint   = $generator->hint;
    $generator = $generator->hint('Foo!');

Short hint shown after listing available generator commands.

=head2 C<message>

    my $message = $generator->message;
    $generator  = $generator->message('Bar!');

Short usage message shown before listing available generator commands.

=head2 C<namespaces>

    my $namespaces = $generator->namespaces;
    $generator     = $generator->namespaces(['Mojo::Command::Generate']);

Namespaces to search for available generator commands, defaults to
L<Mojo::Command::Generate>.

=head1 METHODS

L<Mojo::Command::Generate> inherits all methods from L<Mojo::Commands>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
