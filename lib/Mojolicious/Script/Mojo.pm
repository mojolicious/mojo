# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Script::Mojo;

use strict;
use warnings;

use base 'Mojo::Scripts';

__PACKAGE__->attr('description', default => <<'EOF');
* Access Mojo scripts. *
Forwards options to the original Mojo scripts,
will list available scripts by default.
    mojo <script> <options>
EOF

# Bodies are for hookers and fat people.

1;
__END__

=head1 NAME

Mojolicious::Script::Mojo - Mojo Script

=head1 SYNOPSIS

    use Mojo::Script::Mojo;

    my $mojo = Mojolicious::Script::Mojo->new;
    $mojo->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicous::Script::Mojo> is a script that forwards to L<Mojo::Scripts>.

=head1 ATTRIBUTES

L<Mojolicious::Script::Mojo> inherits all attributes from L<Mojo::Scripts>
and implements the following new ones.

=head2 C<description>

    my $description = $mojo->description;
    $mojo           = $mojo->description('Does stuff.');

=head1 METHODS

L<Mojolicious::Script::Mojo> inherits all methods from L<Mojo::Scripts>.

=cut
