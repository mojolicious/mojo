package Mojolicious::Plugin::Mount;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Server;

sub register {
  my ($self, $app, $conf) = @_;

  # Extract host and path
  my $prefix = (keys %$conf)[0];
  my ($host, $path);
  if ($prefix =~ /^(\*\.)?([^\/]+)(\/.*)?$/) {
    $host = quotemeta $2;
    $host = "(?:.*\\.)?$host" if $1;
    $path = $3;
    $path = '/' unless defined $path;
    $host = qr/^$host$/i;
    $app->routes->cache(0);
  }
  else { $path = $prefix }

  # Generate route
  my $route =
    $app->routes->route($path)
    ->detour(app => Mojo::Server->new->load_app($conf->{$prefix}));
  $route->over(host => $host) if $host;

  $route;
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::Mount - Application Mount Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin(mount => {'/prefix' => '/home/sri/myapp.pl'});

  # Mojolicious::Lite
  plugin mount => {'/prefix' => '/home/sri/myapp.pl'};

  # Adjust the generated route
  my $example = plugin mount => {'/example' => '/home/sri/example.pl'};
  $example->to(message => 'It works great!');

  # Mount application with host (automatically disables route caching)
  plugin mount => {'mojolicio.us' => '/home/sri/myapp.pl'};

  # Host and path
  plugin mount => {'mojolicio.us/myapp' => '/home/sri/myapp.pl'};

  # Or even hosts with wildcard subdomains
  plugin mount => {'*.mojolicio.us/myapp' => '/home/sri/myapp.pl'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::Mount> is a plugin that allows you to mount whole
L<Mojolicious> applications.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojolicious::Plugin::Mount> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Mount L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
