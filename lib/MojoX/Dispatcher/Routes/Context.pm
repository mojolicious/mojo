# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Dispatcher::Routes::Context;

use strict;
use warnings;

use base 'Mojo::Base';

__PACKAGE__->attr([qw/match transaction/], chained => 1);

*req  = \&request;
*res  = \&response;
*tx   = \&transaction;

# Just make a simple cake. And this time, if someone's going to jump out of
# it make sure to put them in *after* you cook it.
sub request { return shift->tx->req }

sub response { return shift->tx->res }

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

=head2 C<request>

    my $req = $c->req;
    my $req = $c->request;

=head2 C<res>

=head2 C<response>

    my $res = $c->res;
    my $res = $c->response;

=head2 C<tx>

=head2 C<transaction>

    my $tx = $c->tx;
    my $tx = $c->transaction;

=head1 METHODS

L<MojoX::Dispatcher::Routes::Context> inherits all methods from
L<Mojo::Base>.

=cut