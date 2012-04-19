package Mojolicious::Plugin::Mount;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Server;

sub register {
  my ($self, $app, $conf) = @_;

  # Extract host and path
  my $prefix = (keys %$conf)[0];
  my ($host, $path);
  if ($prefix =~ m#^(\*\.)?([^/]+)(/.*)?$#) {
    $host = quotemeta $2;
    $host = "(?:.*\\.)?$host" if $1;
    $path = defined $3 ? $3 : '/';
    $host = qr/^$host$/i;
  }
  else { $path = $prefix }

  # Generate route
  my $embed = Mojo::Server->new->load_app($conf->{$prefix});
  my $route = $app->routes->route($path)->detour(app => $embed);
  $route->over(host => $host) if $host;

  return $route;
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::Mount - Application mount plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin(Mount => {'/prefix' => '/home/sri/myapp.pl'});

  # Mojolicious::Lite
  plugin Mount => {'/prefix' => '/home/sri/myapp.pl'};

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

  $plugin->register;

Mount L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
