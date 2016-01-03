package Mojolicious::Plugin::Charset;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app, $conf) = @_;

  return unless my $c = $conf->{charset};
  $app->types->type(html => "text/html;charset=$c");
  $app->renderer->encoding($c);
  $app->hook(before_dispatch =>
      sub { shift->req->default_charset($c)->url->query->charset($c) });
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Charset - Charset plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin(Charset => {charset => 'Shift_JIS'});

  # Mojolicious::Lite
  plugin Charset => {charset => 'Shift_JIS'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::Charset> is a plugin to easily set the default charset
and encoding on all layers of L<Mojolicious>.

The code of this plugin is a good example for learning to build new plugins,
you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available
by default.

=head1 OPTIONS

L<Mojolicious::Plugin::Charset> supports the following options.

=head2 charset

  # Mojolicious::Lite
  plugin Charset => {charset => 'Shift_JIS'};

Application charset.

=head1 METHODS

L<Mojolicious::Plugin::Charset> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new, {charset => 'Shift_JIS'});

Register hook L<Mojolicious/"before_dispatch"> in application and change a few
defaults.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
