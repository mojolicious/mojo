# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Dispatcher::Routes::Controller;

use strict;
use warnings;

use base 'Mojo::Base';

require Carp;
require Scalar::Util;

__PACKAGE__->attr([qw/app match tx/]);

# Just make a simple cake. And this time, if someone's going to jump out of
# it make sure to put them in *after* you cook it.
sub param {
    my $self = shift;

    # Parameters
    my $params = $self->stash->{params};
    Carp::croak(
        qq/Stash value "params" is not a valid "Mojo::Parameters" object./)
      unless ref $params
          && Scalar::Util::blessed($params)
          && $params->isa('Mojo::Parameters');

    # Values
    return wantarray ? ($params->param(@_)) : scalar $params->param(@_);
}

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

MojoX::Dispatcher::Routes::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'MojoX::Dispatcher::Routes::Controller';

=head1 DESCRIPTION

L<MojoX::Dispatcher::Routes::Controller> is a controller base class.

=head1 ATTRIBUTES

L<MojoX::Dispatcher::Routes::Controller> implements the following attributes.

=head2 C<app>

    my $app = $c->app;
    $c      = $c->app(MojoSubclass->new);

A reference back to the application that dispatched to this controller.

=head2 C<match>

    my $match = $c->match;

A L<MojoX::Routes::Match> object containing the routes results for the
current request.

=head2 C<tx>

    my $tx = $c->tx;

The transaction that is currently being processed.

=head1 METHODS

L<MojoX::Dispatcher::Routes::Controller> inherits all methods from
L<Mojo::Base> and implements the following new ones.

=head2 C<param>

    my $param  = $c->param('foo');
    my @params = $c->param('foo');

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

    $c->stash->{foo} = 'bar';
    my $foo = $c->stash->{foo};
    delete $c->stash->{foo};

=cut
