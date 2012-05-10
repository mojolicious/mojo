package Mojolicious::Command::routes;
use Mojo::Base 'Mojo::Command';

use re 'regexp_pattern';
use Getopt::Long qw(GetOptions :config no_auto_abbrev no_ignore_case);

has description => "Show available routes.\n";
has usage       => <<"EOF";
usage: $0 routes [OPTIONS]

These options are available:
  -v, --verbose   Print additional details about routes.
EOF

# "I'm finally richer than those snooty ATM machines."
sub run {
  my $self = shift;

  # Options
  local @ARGV = @_;
  my $verbose;
  GetOptions('v|verbose' => sub { $verbose = 1 });

  # Walk and draw
  my $routes = [];
  $self->_walk($_, 0, $routes) for @{$self->app->routes->children};
  $self->_draw($routes, $verbose);
}

sub _draw {
  my ($self, $routes, $verbose) = @_;

  # Length
  my @length = (0, 0, 0);
  for my $node (@$routes) {

    # Pattern
    my $len = length $node->[0];
    $length[0] = $len if $len > $length[0];

    # Methods
    unless (defined $node->[1]->via) { $len = length '*' }
    else { $len = length(join ',', @{$node->[1]->via}) }
    $length[1] = $len if $len > $length[1];

    # Name
    $len = length $node->[1]->name;
    $len += 2 if $node->[1]->has_custom_name;
    $length[2] = $len if $len > $length[2];
  }

  # Draw
  for my $node (@$routes) {
    my @parts;

    # Pattern
    push @parts, $node->[0];
    $parts[-1] .= ' ' x ($length[0] - length $parts[-1]);

    # Methods
    my $methods;
    unless (defined $node->[1]->via) { $methods = '*' }
    else { $methods = uc join ',', @{$node->[1]->via} }
    push @parts, $methods . ' ' x ($length[1] - length $methods);

    # Name
    my $name = $node->[1]->name;
    $name = qq{"$name"} if $node->[1]->has_custom_name;
    push @parts, $name . ' ' x ($length[2] - length $name);

    # Regex
    my $pattern = $node->[1]->pattern;
    $pattern->match('/', $node->[1]->is_endpoint);
    my $regex    = (regexp_pattern $pattern->regex)[0];
    my $format   = (regexp_pattern $pattern->format || '')[0];
    my $optional = !$pattern->reqs->{format} || $pattern->defaults->{format};
    $format .= '?' if $format && $optional;
    push @parts, $format ? "$regex$format" : $regex if $verbose;

    # Route
    say join('  ', @parts);
  }
}

# "I surrender, and volunteer for treason!"
sub _walk {
  my ($self, $node, $depth, $routes) = @_;

  # Pattern
  my $prefix = '';
  if (my $i = $depth * 2) { $prefix .= ' ' x $i . '+' }
  push @$routes, [$prefix . ($node->pattern->pattern || '/'), $node];

  # Walk
  $depth++;
  $self->_walk($_, $depth, $routes) for @{$node->children};
  $depth--;
}

1;

=head1 NAME

Mojolicious::Command::routes - Routes command

=head1 SYNOPSIS

  use Mojolicious::Command::routes;

  my $routes = Mojolicious::Command::routes->new;
  $routes->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::routes> lists all your application routes.

=head1 ATTRIBUTES

L<Mojolicious::Command::routes> inherits all attributes from L<Mojo::Command>
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

L<Mojolicious::Command::routes> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $routes->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
