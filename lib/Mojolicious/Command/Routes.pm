package Mojolicious::Command::Routes;

use strict;
use warnings;

use base 'Mojo::Command';

use Mojo::Server;

__PACKAGE__->attr(description => <<'EOF');
Show available routes.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 routes
EOF

# I'm finally richer than those snooty ATM machines.
sub run {
    my $self = shift;

    # App
    my $app = Mojo::Server->new->app;
    die "Application has no routes.\n" unless $app->can('routes');

    # Walk
    my $routes = [];
    $self->_walk($_, 0, $routes) for @{$app->routes->children};

    # Draw
    $self->_draw($routes);

    return $self;
}

sub _draw {
    my ($self, $routes) = @_;

    # Length
    my $length = 0;
    for my $node (@$routes) {
        my $l = length $node->[0];
        $length = $l if $l > $length;
    }

    # Draw
    foreach my $node (@$routes) {

        # Regex
        $node->[1]->pattern->_compile;
        my $regex = $node->[1]->pattern->regex;

        # Padding
        my $name = $node->[0];
        my $padding = ' ' x ($length - length $name);

        # Print
        print "$name$padding   $regex\n";
    }
}

# I surrender, and volunteer for treason!
sub _walk {
    my ($self, $node, $depth, $routes) = @_;

    # Line
    my $pattern = $node->pattern->pattern || '/';
    my $name    = $node->name;
    my $line    = ' ' x ($depth * 4);
    $line .= $pattern;

    # Store
    push @$routes, [$line, $node];

    # Walk
    $depth++;
    $self->_walk($_, $depth, $routes) for @{$node->children};
    $depth--;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Routes - Routes Command

=head1 SYNOPSIS

    use Mojolicious::Command::Routes;

    my $routes = Mojolicious::Command::Routes->new;
    $routes->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Routes> prints all your application routes.

=head1 ATTRIBUTES

L<Mojolicious::Command::Routes> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

    my $description = $routes->description;
    $routes         = $routes->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

    my $usage = $routes->usage;
    $routes   = $routes->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::Routes> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

    $routes = $routes->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
