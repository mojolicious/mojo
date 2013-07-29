package Mojolicious::Command::routes;
use Mojo::Base 'Mojolicious::Command';

use re 'regexp_pattern';
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Util 'encode';

has description => "Show available routes.\n";
has usage       => <<EOF;
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

  my @table = (0, 0, 0);
  for my $node (@$routes) {

    # Methods
    my $via = $node->[0]->via;
    $node->[2] = !$via ? '*' : uc join ',', @$via;

    # Name
    my $name = $node->[0]->name;
    $node->[3] = $node->[0]->has_custom_name ? qq{"$name"} : $name;

    # Check column width
    $table[$_] = _max($table[$_], length $node->[$_ + 1]) for 0 .. 2;
  }

  for my $node (@$routes) {
    my @parts = map { _padding($node->[$_ + 1], $table[$_]) } 0 .. 2;

    # Regex (verbose)
    my $pattern = $node->[0]->pattern;
    $pattern->match('/', $node->[0]->is_endpoint);
    my $regex = (regexp_pattern $pattern->regex)[0];
    my $format = (regexp_pattern($pattern->format_regex || ''))[0];
    my $optional
      = !$pattern->constraints->{format} || $pattern->defaults->{format};
    $regex .= $optional ? "(?:$format)?" : $format if $format;
    push @parts, $regex if $verbose;

    say encode('UTF-8', join('  ', @parts));
  }
}

sub _max { $_[1] > $_[0] ? $_[1] : $_[0] }

sub _padding { $_[0] . ' ' x ($_[1] - length $_[0]) }

sub _walk {
  my ($self, $route, $depth, $routes) = @_;

  my $prefix = '';
  if (my $i = $depth * 2) { $prefix .= ' ' x $i . '+' }
  push @$routes, [$route, $prefix . ($route->pattern->pattern || '/')];

  $depth++;
  $self->_walk($_, $depth, $routes) for @{$route->children};
  $depth--;
}

1;

=encoding utf8

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
