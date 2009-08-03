# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Script::Routes;

use strict;
use warnings;

use base 'Mojo::Script';

use Mojo::Server;

__PACKAGE__->attr('description', default => <<'EOF');
Show available routes.
EOF
__PACKAGE__->attr('usage', default => <<"EOF");
usage: $0 routes
EOF

# I'm finally richer than those snooty ATM machines.
sub run {
    my $self = shift;

    # App
    my $app = Mojo::Server->new->app;
    die "Application has no routes.\n" unless $app->can('routes');

    # Walk
    $self->_walk($_, 0) for @{$app->routes->children};

    return $self;
}

sub _walk {
    my ($self, $node, $depth) = @_;

    # Show
    my $pattern = $node->pattern->pattern;
    my $name    = $node->name;
    my $line    = ' ' x ($depth * 2);
    $line .= $pattern;
    $line .= " -> $name" if $name;
    print "$line\n";

    # Walk
    $depth++;
    $self->_walk($_, $depth) for @{$node->children};
    $depth--;
}

1;
__END__

=head1 NAME

Mojolicious::Script::Routes - Routes Script

=head1 SYNOPSIS

    use Mojolicious::Script::Routes;

    my $routes = Mojolicious::Script::Routes->new;
    $routes->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Script::Routes> is a routes script.

=head1 ATTRIBUTES

L<Mojolicious::Script::Routes> inherits all attributes from L<Mojo::Script>
and implements the following new ones.

=head2 C<description>

    my $description = $routes->description;
    $routes         = $routes->description('Foo!');

=head2 C<usage>

    my $usage = $routes->usage;
    $routes   = $routes->usage('Foo!');

=head1 METHODS

L<Mojolicious::Script::Routes> inherits all methods from L<Mojo::Script> and
implements the following new ones.

=head2 C<run>

    $routes = $routes->run(@ARGV);

=cut
