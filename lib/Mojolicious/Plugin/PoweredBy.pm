package Mojolicious::Plugin::PoweredBy;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app, $conf) = @_;
  my $name = $conf->{name} || 'Mojolicious (Perl)';
  $app->hook(before_dispatch =>
      sub { shift->res->headers->header('X-Powered-By' => $name) });
}

1;

=head1 NAME

Mojolicious::Plugin::PoweredBy - Powered by plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('PoweredBy');
  $self->plugin(PoweredBy => (name => 'MyApp 1.0'));

  # Mojolicious::Lite
  plugin 'PoweredBy';
  plugin PoweredBy => (name => 'MyApp 1.0');

=head1 DESCRIPTION

L<Mojolicious::Plugin::PoweredBy> is a plugin that adds an C<X-Powered-By>
header which defaults to C<Mojolicious (Perl)>.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

=head1 OPTIONS

L<Mojolicious::Plugin::PoweredBy> supports the following options.

=head2 name

  plugin PoweredBy => (name => 'MyApp 1.0');

Value for C<X-Powered-By> header, defaults to C<Mojolicious (Perl)>.

=head1 METHODS

L<Mojolicious::Plugin::PoweredBy> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);
  $plugin->register(Mojolicious->new, {name => 'MyFramework 1.0'});

Register hooks in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
