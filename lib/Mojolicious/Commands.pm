# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Commands;

use strict;
use warnings;

use base 'Mojo::Commands';

__PACKAGE__->attr(
    namespaces => sub { [qw/Mojolicious::Command Mojo::Command/] });

# One day a man has everything, the next day he blows up a $400 billion
# space station, and the next day he has nothing. It makes you think.

1;
__END__

=head1 NAME

Mojolicious::Commands - Commands

=head1 SYNOPSIS

    use Mojo::Commands;

    my $commands = Mojolicious::Commands->new;
    $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicous::Commands> is a interactive command interface.

=head1 ATTRIBUTES

L<Mojolicious::Commands> inherits all attributes from L<Mojo::Commands> and
implements the following new ones.

=head2 C<namespaces>

    my $namespaces = $commands->namespaces;
    $commands      = $commands->namespaces(['Mojolicious::Commands']);

=head1 METHODS

L<Mojolicious::Commands> inherits all methods from L<Mojo::Commands>.

=cut
