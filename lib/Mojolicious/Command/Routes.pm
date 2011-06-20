package Mojolicious::Command::Routes;
use Mojo::Base 'Mojo::Command';

use Mojo::Server;

has description => <<'EOF';
Show available routes.
EOF
has usage => <<"EOF";
usage: $0 routes
EOF

# "I'm finally richer than those snooty ATM machines."
sub run {
  my $self = shift;

  # Check if application has routes
  my $app = Mojo::Server->new->app;
  die "Application has no routes.\n" unless $app->can('routes');

  # Walk and draw
  my $routes = [];
  $self->_walk($_, 0, $routes) for @{$app->routes->children};
  $self->_draw($routes);

  $self;
}

sub _draw {
  my ($self, $routes) = @_;

  # Length
  my $pl = my $nl = my $ml = 0;
  for my $node (@$routes) {

    # Path
    my $l = length $node->[0];
    $pl = $l if $l > $pl;

    # Name
    my $l2 = length($node->[1]->name);
    $l2 += 2 if $node->[1]->has_custom_name;
    $nl = $l2 if $l2 > $nl;

    # Methods
    my $l3 =
      defined($node->[1]->via)
      ? length(join ',', @{$node->[1]->via})
      : length('*');
    $ml = $l3 if $l3 > $ml;
  }

  # Draw
  foreach my $node (@$routes) {

    # Regex
    $node->[1]->pattern->_compile;
    my $regex = $node->[1]->pattern->regex;

    # Pattern
    my $pattern = $node->[0];
    my $pp = ' ' x ($pl - length $pattern);

    # Name
    my $name = $node->[1]->name;
    $name = qq/"$name"/ if $node->[1]->has_custom_name;
    my $np = ' ' x ($nl - length $name);

    # Methods
    my $methods =
      defined $node->[1]->via
      ? uc join ',', @{$node->[1]->via}
      : '*';
    my $mp = ' ' x ($ml - length $methods);

    # Route
    print "$pattern$pp  $methods$mp  $name$np  $regex\n";
  }
}

# "I surrender, and volunteer for treason!"
sub _walk {
  my ($self, $node, $depth, $routes) = @_;

  # Line
  my $pattern = $node->pattern->pattern || '/';
  my $line    = '';
  my $i       = $depth * 2;
  if ($i) {
    $line .= ' ' x $i;
    $line .= '+';
  }
  $line .= $pattern;
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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
