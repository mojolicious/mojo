# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious::Dispatcher;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes';

__PACKAGE__->attr([qw/method user_agent/], chained => 1);

*ua = \&user_agent;

# That's not why people watch TV.
# Clever things make people feel stupid and unexpected things make them feel
# scared.
sub match {
    my ($self, $match) = @_;

    # Method
    if (my $regex = $self->method) {
        return undef unless $match->tx->req->method =~ /$regex/;
    }

    # User-Agent header
    if (my $regex = $self->ua) {
        my $ua = $match->tx->req->headers->user_agent || '';
        return undef unless $ua =~ /$regex/;
    }

    return $self->SUPER::match($match);
}

1;
__END__

=head1 NAME

Mojolicious::Dispatcher - Dispatcher

=head1 SYNOPSIS

    use Mojolicious::Dispatcher;

    my $routes = Mojolicious::Dispatcher->new;

=head1 DESCRIPTION

L<Mojolicous::Dispatcher> is the default L<Mojolicious> dispatcher.

=head1 ATTRIBUTES

L<Mojolicious::Dispatcher> inherits all attributes from
L<MojoX::Dispatcher::Routes>.

=head1 METHODS

L<Mojolicious::Dispatcher> inherits all methods from
L<MojoX::Dispatcher::Routes> and implements the following new ones.

=head2 C<match>

    my $match = $routes->match($tx);

=cut