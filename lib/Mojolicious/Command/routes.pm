package Mojolicious::Command::routes;
use Mojo::Base 'Mojolicious::Command';

use re 'regexp_pattern';
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Util 'encode';

has description => "Show available routes.\n";
has usage       => <<"EOF";
usage: $0 routes [OPTIONS]

These options are available:
  -v, --verbose   Print additional details about routes.
EOF

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args, 'v|verbose' => \my $verbose;

  my $routes = [];
  $self->_walk($_, 0, $routes) for @{$self->app->routes->children};
  $self->_draw($routes, $verbose);
}

sub _draw {
  my ($self, $routes, $verbose) = @_;

  # Calculate column widths
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

  # Draw all routes
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
    my $regex = (regexp_pattern $pattern->regex)[0];
    my $format = (regexp_pattern $pattern->format_regex || '')[0];
    my $optional
      = !$pattern->constraints->{format} || $pattern->defaults->{format};
    $format .= '?' if $format && $optional;
    push @parts, $format ? "$regex$format" : $regex if $verbose;

    say encode('UTF-8', join('  ', @parts));
  }
}

sub _walk {
  my ($self, $node, $depth, $routes) = @_;

  my $prefix = '';
  if (my $i = $depth * 2) { $prefix .= ' ' x $i . '+' }
  push @$routes, [$prefix . ($node->pattern->pattern || '/'), $node];

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

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::routes> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $routes->description;
  $routes         = $routes->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $routes->usage;
  $routes   = $routes->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::routes> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $routes->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
