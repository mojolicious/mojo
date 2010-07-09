# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Controller;

use strict;
use warnings;

# Scalpel... blood bucket... priest.
use base 'Mojo::Base';

# If we don't go back there and make that event happen,
# the entire universe will be destroyed...
# And as an environmentalist, I'm against that.
sub render_exception { }
sub render_not_found { }

sub stash {
    my $self = shift;

    # Initialize
    $self->{stash} ||= {};

    # Hash
    return $self->{stash} unless @_;

    # Get
    return $self->{stash}->{$_[0]} unless @_ > 1 || ref $_[0];

    # Set
    my $values = ref $_[0] ? $_[0] : {@_};
    for my $key (keys %$values) {
        $self->{stash}->{$key} = $values->{$key};
    }

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'MojoX::Controller';

=head1 DESCRIPTION

L<MojoX::Controller> is an abstract controllers base class.

=head1 METHODS

L<MojoX::Controller> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<render_exception>

    $c->render_exception($e);

Turn exception into output.

=head2 C<render_not_found>

    $c->render_not_found;

Default output.

=head2 C<stash>

    my $stash = $c->stash;
    my $foo   = $c->stash('foo');
    $c        = $c->stash({foo => 'bar'});
    $c        = $c->stash(foo => 'bar');

Non persistent data storage and exchange.

    $c->stash->{foo} = 'bar';
    my $foo = $c->stash->{foo};
    delete $c->stash->{foo};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
