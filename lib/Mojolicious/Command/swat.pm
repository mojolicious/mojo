package Mojolicious::Command::swat;
use Mojo::Base 'Mojolicious::Command';
#use Data::Dumper;

use re 'regexp_pattern';
use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Util qw(encode tablify);

has description => 'Generate swat tests for mojo routes';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  GetOptionsFromArray \@args, 'v|verbose' => \my $verbose;

  my $rows = [];
  _walk($_, 0, $rows, $verbose) for @{$self->app->routes->children};
#  print encode('UTF-8', tablify($rows));
    ROUTE: for my $i (@$rows){

        my $http_method = $i->[1];
        my $route  = $i->[0];

        unless ($http_method=~/GET|POST/i){
            warn "sorry, swat does not support $http_method methods yet ...";
            next ROUTE;
        }

        print "generate swat route for $route ... \n";
        mkdir "swat/$route";

        print "generate swat data for $http_method $route ... \n";
        my $filename = "swat/$route/"; 
        $filename.=lc($http_method); $filename.=".txt";
        open(my $fh, '>', $filename) or die "Could not open file '$filename' $!";
        print $fh "200 OK\n";
        close $fh;

   }
        print "\n---\nswat is ready to run: swat ./swat http://127.0.0.1:3000\n";        

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
  push @$row, join('', @flags) if $verbose;

  # Methods
  my $via = $route->via;
  push @$row, !$via ? '*' : uc join ',', @$via;

  # Name
  my $name = $route->name;
  push @$row, $route->has_custom_name ? qq{"$name"} : $name;

  # Regex (verbose)
  my $pattern = $route->pattern;
  $pattern->match('/', $route->is_endpoint && !$partial);
  my $regex  = (regexp_pattern $pattern->regex)[0];
  my $format = (regexp_pattern($pattern->format_regex))[0];
  push @$row, $regex, $format ? $format : '' if $verbose;

  $depth++;
  _walk($_, $depth, $rows, $verbose) for @{$route->children};
  $depth--;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::swat - Generate swat tests for mojo routes

=head1 DESCRIPTION

L<Mojolicious::Command::swat> generate swat tests for mojo routes.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut

