package Mojolicious::Plugin::Mount;
use Mojo::Base 'Mojolicious::Plugin';
use Mojolicious::Plugin::HeaderCondition;

use Mojo::Server;

sub register {
  my ($self, $app, $conf) = @_;
  
  # require header condition
  $app->plugin('header_condition');
  
  # get app routes
  my $routes = $app->routes;
  
  while (my ($key, $value) = each (%$conf)) {
    my $route  = $key;
    my $script = $conf->{$route};
    my $domain = undef ;
    
    if ($route !~ /^\//) {
      # assumed to be a domain (w/wo route)
      ($domain, $route) = split /\//, $route;
      $domain =~ s/\./\\\./g;
      $domain =~ s/\*\\\./\(\.\*\\\.\)\?/g;
      $route = $route ? "/$route" : '/';
    }
    
    my $goto = $routes->route($route)->detour(
        app => Mojo::Server->new->load_app($script));
    
       $goto->over(headers => { HOST => qr/^$domain$/ }) if $domain;
  }
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
