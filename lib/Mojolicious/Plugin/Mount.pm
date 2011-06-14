package Mojolicious::Plugin::Mount;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Server;

sub register {
  my ($self, $app, $conf) = @_;
  my $prefix = (keys %$conf)[0];
  $app->routes->route($prefix)
    ->detour(app => Mojo::Server->new->load_app($conf->{$prefix}));
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
