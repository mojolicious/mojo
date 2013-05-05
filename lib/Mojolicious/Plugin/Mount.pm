package Mojolicious::Plugin::Mount;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Server;

sub register {
  my ($self, $app, $conf) = @_;

  my $path  = (keys %$conf)[0];
  my $embed = Mojo::Server->new->load_app($conf->{$path});

  # Extract host
  my $host;
  if ($path =~ m!^(\*\.)?([^/]+)(/.*)?$!) {
    $host = $1 ? qr/^(?:.*\.)?\Q$2\E$/i : qr/^\Q$2\E$/i;
    $path = $3;
  }

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
  plugin Mount => {'example.com' => '/home/sri/myapp.pl'};

  # Host and path
  plugin Mount => {'example.com/myapp' => '/home/sri/myapp.pl'};

  # Or even hosts with wildcard subdomains
  plugin Mount => {'*.example.com/myapp' => '/home/sri/myapp.pl'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::Mount> is a plugin that allows you to mount whole
L<Mojolicious> applications.

The code of this plugin is a good example for learning to build new plugins,
you're welcome to fork it.

=head1 METHODS

L<Mojolicious::Plugin::Mount> inherits all methods from L<Mojolicious::Plugin>
and implements the following new ones.

=head2 register

  my $route = $plugin->register(Mojolicious->new, {'/foo' => '/some/app.pl'});

Mount L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
