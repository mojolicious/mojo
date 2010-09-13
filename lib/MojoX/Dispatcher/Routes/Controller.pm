package MojoX::Dispatcher::Routes::Controller;

use strict;
use warnings;

use base 'MojoX::Session::Cookie::Controller';

__PACKAGE__->attr('match');

# Just make a simple cake. And this time, if someone's going to jump out of
# it make sure to put them in *after* you cook it.
sub param {
    my ($self, $name) = @_;

    # Captures
    my $p = $self->stash->{'mojo.captures'} || {};
    return $p->{$name} if exists $p->{$name};

    # Params
    return $self->req->param($name);
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

L<MojoX::Dispatcher::Routes::Controller> inherits all attributes from
L<MojoX::Session::Cookie::Controller> implements the following attributes.

=head2 C<match>

    my $m = $c->match;

A L<MojoX::Routes::Match> object containing the routes results for the
current request.

=head1 METHODS

L<MojoX::Dispatcher::Routes::Controller> inherits all methods from
L<MojoX::Session::Cookie::Controller> and implements the following new ones.

=head2 C<param>

    my $param  = $c->param('foo');
    my @params = $c->param('foo');

Request parameters and routes captures.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
