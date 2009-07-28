# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Scripts;

use strict;
use warnings;

use base 'Mojo::Scripts';

__PACKAGE__->attr('namespaces',
    default => sub { [qw/Mojolicious::Script Mojo::Script/] });

# One day a man has everything, the next day he blows up a $400 billion
# space station, and the next day he has nothing. It makes you think.

1;
__END__

=head1 NAME

Mojolicious::Scripts - Scripts

=head1 SYNOPSIS

    use Mojo::Scripts;

    my $scripts = Mojolicious::Scripts->new;
    $scripts->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicous::Scripts> is a interactive script interface.

=head1 ATTRIBUTES

L<Mojolicious::Scripts> inherits all attributes from L<Mojo::Scripts> and
implements the following new ones.

=head2 C<namespaces>

    my $namespaces = $scripts->namespaces;
    $scripts       = $scripts->namespaces(['Mojolicious::Scripts']);

=head1 METHODS

L<Mojolicious::Scripts> inherits all methods from L<Mojo::Scripts>.

=cut
