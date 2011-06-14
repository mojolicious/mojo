package Mojolicious::Plugin::Embed;
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

Mojolicious::Plugin::Embed - Application Embedding Plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('embed', '/prefix' => '/Users/sri/myapp.pl');

  # Mojolicious::Lite
  plugin 'embed', '/prefix' => '/Users/sri/myapp.pl';

=head1 DESCRIPTION

L<Mojolicious::Plugin::Embed> is a simple application embeddign plugin.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojolicious::Plugin::Embed> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

  $plugin->register;

Embed L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
