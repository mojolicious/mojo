package Mojolicious::Plugin::JSONConfig;
use Mojo::Base 'Mojolicious::Plugin::Config';

use Mojo::JSON;
use Mojo::Template;
use Mojo::Util 'encode';

sub parse {
  my ($self, $content, $file, $conf, $app) = @_;

  my $json   = Mojo::JSON->new;
  my $config = $json->decode($self->render($content, $file, $conf, $app));
  my $err    = $json->error;
  die qq{Couldn't parse config "$file": $err} if !$config && $err;
  die qq{Invalid config "$file".} if !$config || ref $config ne 'HASH';

  return $config;
}

sub register { shift->SUPER::register(shift, {ext => 'json', %{shift()}}) }

sub render {
  my ($self, $content, $file, $conf, $app) = @_;

  # Application instance and helper
  my $prepend = q[my $app = shift; no strict 'refs'; no warnings 'redefine';];
  $prepend .= q[sub app; *app = sub { $app }; use Mojo::Base -strict;];

  # Render and encode for JSON decoding
  my $mt = Mojo::Template->new($conf->{template} || {})->name($file);
  my $json = $mt->prepend($prepend . $mt->prepend)->render($content, $app);
  return ref $json ? die $json : encode 'UTF-8', $json;
}

1;

=head1 NAME

Mojolicious::Plugin::JSONConfig - JSON configuration plugin

=head1 SYNOPSIS

  # myapp.json (it's just JSON with embedded Perl)
  {
    "foo"       : "bar",
    "music_dir" : "<%= app->home->rel_dir('music') %>"
  }

  # Mojolicious
  my $config = $self->plugin('JSONConfig');
  say $config->{foo};

  # Mojolicious::Lite
  my $config = plugin 'JSONConfig';
  say $config->{foo};

  # foo.html.ep
  %= $config->{foo}

  # The configuration is available application wide
  my $config = app->config;
  say $config->{foo};

  # Everything can be customized with options
  my $config = plugin JSONConfig => {file => '/etc/myapp.conf'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::JSONConfig> is a JSON configuration plugin that
preprocesses its input with L<Mojo::Template>.

The application object can be accessed via C<$app> or the C<app> function. You
can extend the normal config file C<myapp.json> with C<mode> specific ones
like C<myapp.$mode.json>. A default configuration filename will be generated
from the value of L<Mojolicious/"moniker">.

The code of this plugin is a good example for learning to build new plugins,
you're welcome to fork it.

=head1 OPTIONS

L<Mojolicious::Plugin::JSONConfig> inherits all options from
L<Mojolicious::Plugin::Config> and supports the following new ones.

=head2 template

  # Mojolicious::Lite
  plugin JSONConfig => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> object used to preprocess
configuration files.

=head1 METHODS

L<Mojolicious::Plugin::JSONConfig> inherits all methods from
L<Mojolicious::Plugin::Config> and implements the following new ones.

=head2 parse

  $plugin->parse($content, $file, $conf, $app);

Process content with C<render> and parse it with L<Mojo::JSON>.

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
