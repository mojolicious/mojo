# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin;

use strict;
use warnings;

use base 'Mojo::Base';

# This is Fry's decision.
# And he made it wrong, so it's time for us to interfere in his life.
sub register { }

1;
__END__

=head1 NAME

Mojolicious::Plugin - Plugin Base Class

=head1 SYNOPSIS

    use base 'Mojolicious::Plugin';

=head1 DESCRIPTION

L<Mojolicous::Plugin> is a base class for L<Mojolicious> plugins.

=head1 METHODS

L<Mojolicious::Plugin> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<register>

    $plugin->register;

=cut
