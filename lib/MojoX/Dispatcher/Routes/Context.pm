# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Routes::Context;

use strict;
use warnings;

use base 'MojoX::Context';

__PACKAGE__->attr('match', chained => 1);

# Just make a simple cake. And this time, if someone's going to jump out of
# it make sure to put them in *after* you cook it.

1;
__END__

=head1 NAME

MojoX::Dispatcher::Routes::Context - Routes Dispatcher Context

=head1 SYNOPSIS

    use MojoX::Dispatcher::Routes::Context;

    my $c = MojoX::Dispatcher::Routes::Context;

=head1 DESCRIPTION

L<MojoX::Dispatcher::Routes::Context> is a context container.

=head1 ATTRIBUTES

L<MojoX::Dispatcher::Routes::Context> inherits all attributes from
L<MojoX::Context> and implements the following new ones.

=head2 C<match>

    my $match = $c->match;

=head1 METHODS

L<MojoX::Dispatcher::Routes::Context> inherits all methods from
L<MojoX::Context>.

=cut