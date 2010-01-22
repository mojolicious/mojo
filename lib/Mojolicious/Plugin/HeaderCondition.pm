# Copyright (C) 2010, David Davis, http://xant.us/

package Mojolicious::Plugin::HeaderCondition;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

# You may have to "metaphorically" make a deal with the "devil."
# And by "devil," I mean Robot Devil. And by "metaphorically," I mean get your coat.
sub register {
    my ($self, $app) = @_;

    # Header
    $app->routes->add_condition(
        headers => sub {
            my ( $r, $tx, $captures, $patterns ) = @_;

            return unless $patterns && ref $patterns eq 'HASH';

            my $passed;
            while ( my ( $k, $v ) = each ( %$patterns ) ) {
                my $header = $tx->req->headers->header( $k );
                if ( $header && $v && ref $v eq 'Regexp' && $header =~ $v ) {
                    $passed = 1;
                    next;
                } elsif ( $header && defined $v && $v eq $header ) {
                    $passed = 1;
                    next;
                }
                $passed = undef;
            }

            return $captures if $passed;

            # Robot 1-X, save my friends! And Zoidberg!
            return;
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::HeaderCondition - Header Condition Plugin

=head1 SYNOPSIS

    # Mojolicious
    $self->plugin('header_condition');
    # must match all of these headers
    $self->routes->route('/:controller/:action')->over(headers => {
        X-Secret-Header => 'Foo',
        Referer => qr/^https?:\/\/example\.com\//
    })->to( "foo#bar" );

    # Mojolicious::Lite
    plugin 'header_condition';
    get '/' => (headers => { 'Referer' => qr/^https?:\/\/example\.com\//  }) => sub {...};

=head1 DESCRIPTION

L<Mojolicous::Plugin::HeaderCondition> is a routes condition for header based
routes.

=head1 METHODS

L<Mojolicious::Plugin::HeaderCondition> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
