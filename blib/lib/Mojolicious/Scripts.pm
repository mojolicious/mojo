# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious::Scripts;

use strict;
use warnings;

use base 'Mojo::Scripts';

__PACKAGE__->attr('message', chained => 1, default => <<'EOF');
Welcome to the Mojolicious Web Framework!

HINT: In case you don't know what you are doing here try the manual!
    perldoc Mojo::Manual
    perldoc Mojo::Manual::GettingStarted

This is the interactive script interface, the syntax is very simple.
    mojolicious <script> <options>

Below you will find a list of available scripts with descriptions.

EOF
__PACKAGE__->attr('namespace',
    chained => 1,
    default => 'Mojolicious::Script'
);

# One day a man has everything, the next day he blows up a $400 billion
# space station, and the next day he has nothing. It makes you think.

1;
__END__

=head1 NAME

Mojolicious::Scripts - Scripts

=head1 SYNOPSIS

    use Mojo::Scripts;

    my $scripts = Mojolicious::Scripts->new;
    $scripts->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicous::Scripts> is a interactive script interface.

=head1 ATTRIBUTES

L<Mojolicious::Scripts> inherits all attributes from L<Mojo::Scripts> and
implements the following new ones.

=head2 C<message>

    my $message = $scripts->message;
    $scripts    = $scripts->message('Mojolicious!');

=head2 C<namespace>

    my $namespace = $scripts->namespace;
    $scripts      = $scripts->namespace('Mojolicious::Scripts');

=head1 METHODS

L<Mojolicious::Scripts> inherits all methods from L<Mojo::Scripts>.

=cut