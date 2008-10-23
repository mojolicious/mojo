# Copyright (C) 2008, Sebastian Riedel.

package Mojo;

use strict;
use warnings;

use base 'Mojo::Base';

# No imports to make subclassing a bit easier
require Carp;

use Mojo::Transaction;

# Oh, so they have internet on computers now!
our $VERSION = '0.8';

*build_tx = \&build_transaction;

sub build_transaction { return Mojo::Transaction->new }

sub handler { Carp::croak('Method "handler" not implemented in subclass') }

1;
__END__

=head1 NAME

Mojo - The Web In A Box!

=head1 SYNOPSIS

    use base 'Mojo';

    sub handler {
        my ($self, $tx) = @_;

        # Do magic things!

        return $tx;
    }

=head1 DESCRIPTION

L<Mojo> is a collection of libraries for web framework developers and example
web frameworks.

For userfriendly documentation see L<Mojo::Manual>.

=head1 METHODS

L<Mojo> inherits all methods from L<Mojo::Base> and implements the following
new ones.

=head2 C<build_tx>

=head2 C<build_transaction>

    my $tx = $mojo->build_tx;
    my $tx = $mojo->build_transaction;

=head2 C<handler>

    $tx = $mojo->handler($tx);

=head1 SUPPORT

=head2 Web

    http://mojolicious.org

=head2 IRC

    #mojo on irc.freenode.org

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

Andy Grundman

Aristotle Pagaltzis

Audrey Tang

Christian Hansen

Gisle Aas

Jesse Vincent

Marcus Ramberg

Pedro Melo

Shu Cho

And thanks to everyone else i might have forgotten. (Please send me a mail)

=head1 COPYRIGHT

Copyright (C) 2008, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl 5.10.

=cut