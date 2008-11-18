# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious::Script::Daemon;

use strict;
use warnings;

use base 'Mojo::Script::Daemon';

# I'm finally richer than those snooty ATM machines.

1;
__END__

=head1 NAME

Mojolicious::Script::Daemon - Daemon Script

=head1 SYNOPSIS

    use Mojolicious::Script::Daemon;
    my $daemon = Mojolicious::Script::Daemon->new;
    $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Script::Daemon> is a script interface to
L<Mojo::Server::Daemon>.

=head1 ATTRIBUTES

L<Mojolicious::Script::Daemon> inherits all attributes from
L<Mojo::Script::Daemon>.

=head1 METHODS

L<Mojolicious::Script::Daemon> inherits all methods from
L<Mojo::Script::Daemon>.

=cut
