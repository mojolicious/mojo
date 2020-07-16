package Mojolicious::Plugin::NotYAMLConfig;
use Mojo::Base 'Mojolicious::Plugin::JSONConfig';

use CPAN::Meta::YAML;
use Mojo::Util qw(decode encode);

sub register {
  my ($self, $app, $conf) = @_;

  $conf->{ext} //= 'yml';
  $self->{yaml} = sub { CPAN::Meta::YAML::Load(decode 'UTF-8', shift) };
  if (my $mod = $conf->{module}) {
    die qq{YAML module $mod has no Load function} unless $self->{yaml} = $mod->can('Load');
  }

  return $self->SUPER::register($app, $conf);
}

sub parse {
  my ($self, $content, $file, $conf, $app) = @_;
  my $config = eval { $self->{yaml}->(encode('UTF-8', $self->render($content, $file, $conf, $app))) };
  die qq{Can't parse config "$file": $@} if $@;
  die qq{Invalid config "$file"} unless ref $config eq 'HASH';
  return $config;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::NotYAMLConfig - Not quite YAML configuration plugin

=head1 SYNOPSIS

  # myapp.yml (it's just YAML with embedded Perl)
  ---
  foo: bar
  baz:
    - ♥
  music_dir: <%= app->home->child('music') %>

  # Mojolicious
  my $config = $app->plugin('NotYAMLConfig');
  say $config->{foo};

  # Mojolicious::Lite
  my $config = plugin 'NotYAMLConfig';
  say $config->{foo};

  # foo.html.ep
  %= config->{foo}

  # The configuration is available application-wide
  my $config = app->config;
  say $config->{foo};

  # Everything can be customized with options
  my $config = plugin NotYAMLConfig => {file => '/etc/myapp.conf'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::NotYAMLConfig> is a YAML configuration plugin that preprocesses its input with L<Mojo::Template>.
By default it uses L<CPAN::Meta::YAML> for parsing, which is not the best YAML module available, but good enough for
most config files. If you need something more correct you can use a different module like L<YAML::XS> with the
L</"module"> option.

The application object can be accessed via C<$app> or the C<app> function. A default configuration filename in the
application home directory will be generated from the value of L<Mojolicious/"moniker"> (C<$moniker.yml>). You can
extend the normal configuration file C<$moniker.yml> with C<mode> specific ones like C<$moniker.$mode.yml>, which will
be detected automatically.

If the configuration value C<config_override> has been set in L<Mojolicious/"config"> when this plugin is loaded, it
will not do anything.

The code of this plugin is a good example for learning to build new plugins, you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available by default.

=head1 OPTIONS

L<Mojolicious::Plugin::NotYAMLConfig> inherits all options from L<Mojolicious::Plugin::JSONConfig> and supports the
following new ones.

=head2 module

  # Mojolicious::Lite
  plugin NotYAMLConfig => {module => 'YAML::PP'};

Alternative YAML module to use for parsing.

=head1 METHODS

L<Mojolicious::Plugin::NotYAMLConfig> inherits all methods from L<Mojolicious::Plugin::JSONConfig> and implements the
following new ones.

=head2 parse

  $plugin->parse($content, $file, $conf, $app);

Process content with L<Mojolicious::Plugin::JSONConfig/"render"> and parse it with L<CPAN::Meta::YAML>.

  sub parse {
    my ($self, $content, $file, $conf, $app) = @_;
    ...
    $content = $self->render($content, $file, $conf, $app);
    ...
    return $hash;
  }

=head2 register

  my $config = $plugin->register(Mojolicious->new);
  my $config = $plugin->register(Mojolicious->new, {file => '/etc/foo.conf'});

Register plugin in L<Mojolicious> application and merge configuration.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
