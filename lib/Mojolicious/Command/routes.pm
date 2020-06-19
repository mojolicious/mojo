package Mojolicious::Command::routes;
use Mojo::Base 'Mojolicious::Command';

use re qw(regexp_pattern);
use Mojo::Util qw(encode getopt tablify);

has description => 'Show available routes';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  getopt \@args, 'v|verbose' => \my $verbose;

  my $rows = [];
  _walk($_, 0, $rows, $verbose) for @{$self->app->routes->children};
  print encode('UTF-8', tablify($rows));
}

sub _walk {
  my ($route, $depth, $rows, $verbose) = @_;

  # Pattern
  my $prefix = '';
  if (my $i = $depth * 2) { $prefix .= ' ' x $i . '+' }
  push @$rows, my $row = [$prefix . ($route->pattern->unparsed || '/')];

  # Flags
  my @flags;
  push @flags, @{$route->over || []} ? 'C' : '.';
  push @flags, (my $partial = $route->partial) ? 'D' : '.';
  push @flags, $route->inline       ? 'U' : '.';
  push @flags, $route->is_websocket ? 'W' : '.';
  push @$row,  join('', @flags) if $verbose;

  # Methods
  my $via = $route->via;
  push @$row, !$via ? '*' : uc join ',', @$via;

  # Name
  my $name = $route->name;
  push @$row, $route->has_custom_name ? qq{"$name"} : $name;

  # Regex (verbose)
  my $pattern = $route->pattern;
  $pattern->match('/', $route->is_endpoint && !$partial);
  push @$row, (regexp_pattern $pattern->regex)[0] if $verbose;

  $depth++;
  _walk($_, $depth, $rows, $verbose) for @{$route->children};
  $depth--;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::routes - Routes command

=head1 SYNOPSIS

  Usage: APPLICATION routes [OPTIONS]

    ./myapp.pl routes
    ./myapp.pl routes -v

  Options:
    -h, --help          Show this summary of available options
        --home <path>   Path to home directory of your application, defaults to
                        the value of MOJO_HOME or auto-detection
    -m, --mode <name>   Operating mode for your application, defaults to the
                        value of MOJO_MODE/PLACK_ENV or "development"
    -v, --verbose       Print additional details about routes, flags indicate
                        C=Conditions, D=Detour, U=Under and W=WebSocket

=head1 DESCRIPTION

L<Mojolicious::Command::routes> lists all your application routes.

This is a core command, that means it is always enabled and its code a good example for learning to build new commands,
you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::routes> inherits all attributes from L<Mojolicious::Command> and implements the following new
ones.

=head2 description

  my $description = $routes->description;
  $routes         = $routes->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $routes->usage;
  $routes   = $routes->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::routes> inherits all methods from L<Mojolicious::Command> and implements the following new
ones.

=head2 run

  $routes->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
