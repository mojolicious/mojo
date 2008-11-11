# Copyright (C) 2008, Sebastian Riedel.

package Mojo;

use strict;
use warnings;

use base 'Mojo::Base';

# No imports to make subclassing a bit easier
require Carp;

use Mojo::Home;
use Mojo::Transaction;

__PACKAGE__->attr('home', chained => 1, default => sub { Mojo::Home->new });

# Oh, so they have internet on computers now!
our $VERSION = '0.8010';

sub build_tx { return Mojo::Transaction->new }

sub handler { Carp::croak('Method "handler" not implemented in subclass') }

1;
__END__

=head1 NAME

Mojo - The Web In A Box!

=head1 SYNOPSIS

    use base 'Mojo';

    sub handler {
        my ($self, $tx) = @_;

        # Hello world!
        $tx->res->code(200);
        $tx->res->headers->content_type('text/plain');
        $tx->res->body('Congratulations, your Mojo is working!');

        return $tx;
    }

=head1 DESCRIPTION

L<Mojo> is a collection of libraries and example web frameworks for web
framework developers.

If you are searching for a higher level MVC web framework you should take a
look at L<Mojolicious>.

Don't be scared by the amount of different modules in the distribution, they
are all very loosely coupled.
You can just pick the ones you like and ignore the rest, there is no
tradeoff.

For userfriendly documentation see L<Mojo::Manual>.

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

=head2 C<home>

    my $home = $mojo->home;
    $mojo    = $mojo->home(Mojo::Home->new);

=head1 METHODS

L<Mojo> inherits all methods from L<Mojo::Base> and implements the following
new ones.

=head2 C<build_tx>

    my $tx = $mojo->build_tx;

Returns a new L<Mojo::Transaction> object;
Meant to be overloaded in subclasses.

=head2 C<handler>

    $tx = $mojo->handler($tx);

Returns and takes a L<Mojo::Transaction> object as first argument.
Meant to be overloaded in subclasses.

    sub handler {
        my ($self, $tx) = @_;

        # Hello world!
        $tx->res->code(200);
        $tx->res->headers->content_type('text/plain');
        $tx->res->body('Congratulations, your Mojo is working!');

        return $tx;
    }

=head1 SUPPORT

=head2 Web

    http://mojolicious.org

=head2 IRC

    #mojo on irc.perl.org

=head2 Mailing-List

    http://lists.kraih.com/listinfo/mojo

=head1 DEVELOPMENT

=head2 Repository

    http://github.com/kraih/mojo/commits/master

=head1 SEE ALSO

L<Mojolicious>

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>.

=head1 CREDITS

In alphabetical order:

Andreas Koenig.

Andy Grundman

Aristotle Pagaltzis

Ask Bjoern Hansen

Audrey Tang

Ch Lamprecht

Christian Hansen

Gisle Aas

Jesse Vincent

Lars Balker Rasmussen

Leon Brocard

Marcus Ramberg

Mark Stosberg

Pedro Melo

Robert Hicks

Shu Cho

Uwe Voelker

vti

And thanks to everyone else i might have forgotten. (Please send me a mail)

=head1 COPYRIGHT

Copyright (C) 2008, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl 5.10.

=cut
