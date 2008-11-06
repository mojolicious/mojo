# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Routes::Context;

use strict;
use warnings;

use base 'Mojo::Base';

__PACKAGE__->attr([qw/match tx/], chained => 1);

# Just make a simple cake. And this time, if someone's going to jump out of
# it make sure to put them in *after* you cook it.
sub req { return shift->tx->req }

sub res { return shift->tx->res }

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

=head2 C<match>

    my $match = $c->match;

=head2 C<req>

    my $req = $c->req;

=head2 C<res>

    my $res = $c->res;

=head2 C<tx>

    my $tx = $c->tx;

=head1 METHODS

L<MojoX::Dispatcher::Routes::Context> inherits all methods from
L<Mojo::Base>.

=cut