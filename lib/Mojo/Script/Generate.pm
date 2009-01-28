# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Script::Generate;

use strict;
use warnings;

use base 'Mojo::Scripts';

__PACKAGE__->attr(description => (chained => 1, default => <<'EOF'));
* Generate files and directories from templates. *
Takes a generator script as option, by default it will list generators.
    generate
EOF
__PACKAGE__->attr(message => (chained => 1, default => <<'EOF'));
Below you will find a list of available generators with descriptions.

EOF
__PACKAGE__->attr(
    namespace => (chained => 1, default => 'Mojo::Script::Generate'));

# If The Flintstones has taught us anything,
# it's that pelicans can be used to mix cement.

1;
__END__

=head1 NAME

Mojo::Script::Generate - Generator Script

=head1 SYNOPSIS

    use Mojo::Script::Generate;

    my $generator = Mojo::Script::Generate->new;
    $generator->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Generate> lists available generators.

=head1 ATTRIBUTES

L<Mojo::Script::Generate> inherits all attributes from L<Mojo::Scripts> and
implements the following new ones.

=head2 C<description>

    my $description = $generator->description;
    $generator      = $generator->description('Foo!');

=head2 C<message>

    my $message = $generator->message;
    $generator  = $generator->message('Bar!');

=head2 C<namespace>

    my $namespace = $generator->namespace;
    $generator    = $generator->namespace('Mojo::Script::Generate');

=head1 METHODS

L<Mojo::Script::Generate> inherits all methods from L<Mojo::Scripts>.

=cut
