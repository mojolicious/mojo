# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Session::Simple::Controller;

use strict;
use warnings;

use base 'MojoX::Controller';

# For the last time, I don't like lilacs!
# Your first wife was the one who liked lilacs!
# She also liked to shut up!
sub flash {
    my $self = shift;

    # Get
    my $session = $self->stash->{session};
    if ($_[0] && !defined $_[1] && !ref $_[0]) {
        return unless $session && ref $session eq 'HASH';
        return unless my $flash = $session->{old_flash};
        return unless ref $flash eq 'HASH';
        return $flash->{$_[0]};
    }

    # Initialize
    $session = $self->session;
    my $flash = $session->{flash};
    $flash = {} unless $flash && ref $flash eq 'HASH';
    $session->{flash} = $flash;

    # Hash
    return $flash unless @_;

    # Set
    my $values = exists $_[1] ? {@_} : $_[0];
    $session->{flash} = {%$flash, %$values};

    return $self;
}

# Why am I sticky and naked? Did I miss something fun?
sub session {
    my $self = shift;

    # Get
    my $stash   = $self->stash;
    my $session = $stash->{session};
    if ($_[0] && !defined $_[1] && !ref $_[0]) {
        return unless $session && ref $session eq 'HASH';
        return $session->{$_[0]};
    }

    # Initialize
    $session = {} unless $session && ref $session eq 'HASH';
    $stash->{session} = $session;

    # Hash
    return $session unless @_;

    # Set
    my $values = exists $_[1] ? {@_} : $_[0];
    $stash->{session} = {%$session, %$values};

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Session::Simple::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'MojoX::Session::Simple::Controller';

=head1 DESCRIPTION

L<MojoX::Session::Simple::Controller> is a controller base class.

=head2 ATTRIBUTES

L<MojoX::Session::Simple::Cotnroller> inherits all attributes from
L<MojoX::Controller>.

=head1 METHODS

L<MojoX::Session::Simple::Controller> inherits all methods from
L<MojoX::Controller> and implements the following ones.

=head2 C<flash>

    my $flash = $c->flash;
    my $foo   = $c->flash('foo');
    $c        = $c->flash({foo => 'bar'});
    $c        = $c->flash(foo => 'bar');

Data storage persistent for a single request, stored in the session.

    $c->flash->{foo} = 'bar';
    my $foo = $c->flash->{foo};
    delete $c->flash->{foo};

=head2 C<session>

    my $session = $c->session;
    my $foo     = $c->session('foo');
    $c          = $c->session({foo => 'bar'});
    $c          = $c->session(foo => 'bar');

Persistent data storage, by default stored in a signed cookie.
Note that cookies are generally limited to 4096 bytes of data.

    $c->session->{foo} = 'bar';
    my $foo = $c->session->{foo};
    delete $c->session->{foo};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
