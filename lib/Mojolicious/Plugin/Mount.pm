package Mojolicious::Plugin::Mount;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Server;

sub register {
  my ($self, $app, $conf) = @_;

  # Load application
  my $path  = (keys %$conf)[0];
  my $embed = Mojo::Server->new->load_app($conf->{$path});

  # Extract host
  my $host;
  if ($path =~ m#^(\*\.)?([^/]+)(/.*)?$#) {
    $host = $1 ? qr/^(?:.*\.)?\Q$2\E$/i : qr/^\Q$2\E$/i;
    $path = $3;
  }

  # Generate route
  my $route = $app->routes->route($path)->detour(app => $embed);
  $route->over(host => $host) if $host;

  return $route;
}

1;

=head1 NAME

Mojolicious::Plugin::Mount - Application mount plugin

=head1 SYNOPSIS

  # Mojolicious
  my $route = $self->plugin(Mount => {'/prefix' => '/home/sri/myapp.pl'});

  # Mojolicious::Lite
  my $route = plugin Mount => {'/prefix' => '/home/sri/myapp.pl'};

  # Adjust the generated route
  my $example = plugin Mount => {'/example' => '/home/sri/example.pl'};
  $example->to(message => 'It works great!');

  # Mount application with host
  plugin Mount => {'mojolicio.us' => '/home/sri/myapp.pl'};

  # Host and path
  plugin Mount => {'mojolicio.us/myapp' => '/home/sri/myapp.pl'};

  # Or even hosts with wildcard subdomains
  plugin Mount => {'*.mojolicio.us/myapp' => '/home/sri/myapp.pl'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::Mount> is a plugin that allows you to mount whole
L<Mojolicious> applications. The code of this plugin is a good example for
learning to build new plugins.

=head1 METHODS

L<Mojolicious::Plugin::Mount> inherits all methods from L<Mojolicious::Plugin>
and implements the following new ones.

=head2 C<register>

  my $route = $plugin->register;

Mount L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
