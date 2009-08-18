# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Command::Generate;

use strict;
use warnings;

use base 'Mojo::Command::Generate';

__PACKAGE__->attr(namespaces =>
      sub { [qw/Mojolicious::Command::Generate Mojo::Command::Generate/] });

# Ah, nothing like a warm fire and a SuperSoaker of fine cognac.

1;
__END__

=head1 NAME

Mojolicious::Command::Generate - Generator Command

=head1 SYNOPSIS

    use Mojolicious::Command::Generate;

    my $generator = Mojolicious::Command::Generate->new;
    $generator->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Generate> lists available generators.

=head1 ATTRIBUTES

L<Mojolicious::Command::Generate> inherits all attributes from
L<Mojo::Command::Generate> and implements the following new ones.

=head2 C<namespaces>

    my $namespaces = $generator->namespaces;
    $generator     = $generator->namespaces(
        ['Mojolicious::Command::Generate']
    );

=head1 METHODS

L<Mojolicious::Command::Generate> inherits all methods from
L<Mojo::Command::Generate>.

=cut
