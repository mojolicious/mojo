package Mojolicious::Plugin::JSONConfig;
use Mojo::Base 'Mojolicious::Plugin::Config';

use Mojo::JSON qw(from_json);
use Mojo::Template;

sub parse {
  my ($self, $content, $file, $conf, $app) = @_;

  my $config = eval { from_json $self->render($content, $file, $conf, $app) };
  die qq{Can't parse config "$file": $@} if $@;
  die qq{Invalid config "$file"} unless ref $config eq 'HASH';

  return $config;
}

sub register { shift->SUPER::register(shift, {ext => 'json', %{shift()}}) }

sub render {
  my ($self, $content, $file, $conf, $app) = @_;

  # Application instance and helper
  my $prepend = q[no strict 'refs'; no warnings 'redefine';];
  $prepend .= q[my $app = shift; sub app; local *app = sub { $app };];
  $prepend .= q[use Mojo::Base -strict; no warnings 'ambiguous';];

  my $mt     = Mojo::Template->new($conf->{template} || {})->name($file);
  my $output = $mt->prepend($prepend . $mt->prepend)->render($content, $app);
  return ref $output ? die $output : $output;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::JSONConfig - JSON configuration plugin

=head1 SYNOPSIS

  # myapp.json (it's just JSON with embedded Perl)
  {
    %# Just a value
    "foo": "bar",

    %# Nested data structures are fine too
    "baz": ["♥"],

    %# You have full access to the application
    "music_dir": "<%= app->home->child('music') %>"
  }

  # Mojolicious
  my $config = $app->plugin('JSONConfig');
  say $config->{foo};

  # Mojolicious::Lite
  my $config = plugin 'JSONConfig';
  say $config->{foo};

  # foo.html.ep
  %= config->{foo}

  # The configuration is available application-wide
  my $config = app->config;
  say $config->{foo};

  # Everything can be customized with options
  my $config = plugin JSONConfig => {file => '/etc/myapp.conf'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::JSONConfig> is a JSON configuration plugin that preprocesses its input with L<Mojo::Template>.

The application object can be accessed via C<$app> or the C<app> function. A default configuration filename in the
application home directory will be generated from the value of L<Mojolicious/"moniker"> (C<$moniker.json>). You can
extend the normal configuration file C<$moniker.json> with C<mode> specific ones like C<$moniker.$mode.json>, which
will be detected automatically.

If the configuration value C<config_override> has been set in L<Mojolicious/"config"> when this plugin is loaded, it
will not do anything.

The code of this plugin is a good example for learning to build new plugins, you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available by default.

=head1 OPTIONS

L<Mojolicious::Plugin::JSONConfig> inherits all options from L<Mojolicious::Plugin::Config> and supports the following
new ones.

=head2 template

  # Mojolicious::Lite
  plugin JSONConfig => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> object used to preprocess configuration files.

=head1 METHODS

L<Mojolicious::Plugin::JSONConfig> inherits all methods from L<Mojolicious::Plugin::Config> and implements the
following new ones.

=head2 parse

  $plugin->parse($content, $file, $conf, $app);

Process content with L</"render"> and parse it with L<Mojo::JSON>.

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

=head2 render

  $plugin->render($content, $file, $conf, $app);

Process configuration file with L<Mojo::Template>.

  sub render {
    my ($self, $content, $file, $conf, $app) = @_;
    ...
    return $content;
  }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
