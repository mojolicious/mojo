# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Controller;

use strict;
use warnings;

# Scalpel... blood bucket... priest.
use base 'Mojo::Base';

__PACKAGE__->attr([qw/app tx/]);

# If we don't go back there and make that event happen,
# the entire universe will be destroyed...
# And as an environmentalist, I'm against that.
sub req { shift->tx->req }
sub res { shift->tx->res }

# This is my first visit to the Galaxy of Terror and I'd like it to be a pleasant one.
sub stash {
    my $self = shift;

    # Initialize
    $self->{stash} ||= {};

    # Hash
    return $self->{stash} unless @_;

    # Get
    return $self->{stash}->{$_[0]} unless defined $_[1] || ref $_[0];

    # Set
    my $values = exists $_[1] ? {@_} : $_[0];
    $self->{stash} = {%{$self->{stash}}, %$values};

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Controller - Controller

=head1 SYNOPSIS

    use base 'MojoX::Controller';

=head1 DESCRIPTION

L<MojoX::Controller> is a controllers base class.

=head2 ATTRIBUTES

L<MojoX::Controller> implements the following attributes.

=head2 C<app>

    my $app = $c->app;
    $c      = $c->app(MojoSubclass->new);

A reference back to the application that dispatched to this controller.

=head2 C<tx>

    my $tx = $c->tx;

The transaction that is currently being processed.

=head1 METHODS

L<MojoX::Controller> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<req>

    my $req = $c->req;

Alias for C<$c->tx->req>.
Usually refers to a L<Mojo::Message::Request> object.

=head2 C<res>

    my $res = $c->res;

Alias for C<$c->tx->res>.
Usually refers to a L<Mojo::Message::Response> object.

=head2 C<stash>

    my $stash = $c->stash;
    my $foo   = $c->stash('foo');
    $c        = $c->stash({foo => 'bar'});
    $c        = $c->stash(foo => 'bar');

Non persistent data storage and exchange.

    $c->stash->{foo} = 'bar';
    my $foo = $c->stash->{foo};
    delete $c->stash->{foo};

=cut
