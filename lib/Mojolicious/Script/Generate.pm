# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Script::Generate;

use strict;
use warnings;

use base 'Mojo::Script::Generate';

__PACKAGE__->attr(namespaces =>
      sub { [qw/Mojolicious::Script::Generate Mojo::Script::Generate/] });

# Ah, nothing like a warm fire and a SuperSoaker of fine cognac.

1;
__END__

=head1 NAME

Mojolicious::Script::Generate - Generator Script

=head1 SYNOPSIS

    use Mojolicious::Script::Generate;

    my $generator = Mojolicious::Script::Generate->new;
    $generator->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Script::Generate> lists available generators.

=head1 ATTRIBUTES

L<Mojolicious::Script::Generate> inherits all attributes from
L<Mojo::Script::Generate> and implements the following new ones.

=head2 C<namespaces>

    my $namespaces = $generator->namespaces;
    $generator     = $generator->namespaces(['Mojolicious::Script::Generate']);

=head1 METHODS

L<Mojolicious::Script::Generate> inherits all methods from
L<Mojo::Script::Generate>.

=cut
