package Mojolicious::Plugin::JSONConfig;
use Mojo::Base 'Mojolicious::Plugin::Config';

use Mojo::JSON;
use Mojo::Template;
use Mojo::Util 'encode';

# "And so we say goodbye to our beloved pet, Nibbler, who's gone to a place
#  where I, too, hope one day to go. The toilet."
sub parse {
  my ($self, $content, $file, $conf, $app) = @_;

  # Render
  $content = $self->render($content, $file, $conf, $app);

  # Parse
  my $json   = Mojo::JSON->new;
  my $config = $json->decode($content);
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

  # Render
  my $mt = Mojo::Template->new($conf->{template} || {});
  my $json = $mt->prepend($prepend)->render($content, $app);
  return ref $json ? die($json) : encode('UTF-8', $json);
}

1;

=head1 NAME

Mojolicious::Plugin::JSONConfig - JSON configuration plugin

=head1 SYNOPSIS

  # myapp.json
  {
    "foo"       : "bar",
    "music_dir" : "<%= app->home->rel_dir('music') %>"
  }

  # Mojolicious
  my $config = $self->plugin('JSONConfig');

  # Mojolicious::Lite
  my $config = plugin 'JSONConfig';

  # Reads "myapp.json" by default
  my $config = app->config;

  # Everything can be customized with options
  my $config = plugin JSONConfig => {file => '/etc/myapp.conf'};

=head1 DESCRIPTION

L<Mojolicious::Plugin::JSONConfig> is a JSON configuration plugin that
preprocesses it's input with L<Mojo::Template>. The application object can be
accessed via C<$app> or the C<app> function. You can extend the normal config
file C<myapp.json> with C<mode> specific ones like C<myapp.$mode.json>. The
code of this plugin is a good example for learning to build new plugins.

=head1 OPTIONS

L<Mojolicious::Plugin::JSONConfig> inherits all options from
L<Mojolicious::Plugin::Config> and supports the following new ones.

=head2 C<template>

  # Mojolicious::Lite
  plugin JSONConfig => {template => {line_start => '.'}};

Attribute values passed to L<Mojo::Template> object used to preprocess
configuration files.

=head1 METHODS

L<Mojolicious::Plugin::JSONConfig> inherits all methods from
L<Mojolicious::Plugin::Config> and implements the following new ones.

=head2 C<parse>

  $plugin->parse($content, $file, $conf, $app);

Process content with C<render> and parse it with L<Mojo::JSON>.

  sub parse {
    my ($self, $content, $file, $conf, $app) = @_;
    ...
    $content = $self->render($content, $file, $conf, $app);
    ...
    return $hash;
  }

=head2 C<register>

  my $config = $plugin->register($app, $conf);

Register plugin in L<Mojolicious> application.

=head2 C<render>

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
