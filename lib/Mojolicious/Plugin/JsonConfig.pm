package Mojolicious::Plugin::JsonConfig;
use Mojo::Base 'Mojolicious::Plugin::Config';

use Mojo::JSON;
use Mojo::Template;

use constant DEBUG => $ENV{MOJO_CONFIG_DEBUG} || 0;

# "And so we say goodbye to our beloved pet, Nibbler, who's gone to a place
#  where I, too, hope one day to go. The toilet."
sub parse {
  my ($self, $content, $file, $conf, $app) = @_;

  # Render
  $content = $self->render($content, $file, $conf, $app);

  # Parse
  my $json   = Mojo::JSON->new;
  my $config = $json->decode($content);
  my $error  = $json->error;
  die qq/Couldn't parse config "$file": $error/ if !$config && $error;
  die qq/Invalid config "$file"./ if !$config || ref $config ne 'HASH';

  return $config;
}

sub register {
  my ($self, $app, $conf) = @_;

  # "json" extension
  $conf->{ext} = 'json' unless exists $conf->{ext};

  # DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
  warn <<EOF if $ENV{MOJO_JSON_CONFIG};
The MOJO_JSON_CONFIG environment variable is DEPRECATED in favor of
MOJO_CONFIG!!!
EOF
  $conf->{file} = $ENV{MOJO_JSON_CONFIG}
    if !exists $conf->{file} && exists $ENV{MOJO_JSON_CONFIG};

  $self->SUPER::register($app, $conf);
}

sub render {
  my ($self, $content, $file, $conf, $app) = @_;

  # Instance
  my $prepend = 'my $app = shift;';

  # Be less strict
  $prepend .= q/no strict 'refs'; no warnings 'redefine';/;

  # Helper
  $prepend .= "sub app; *app = sub { \$app };";

  # Be strict again
  $prepend .= q/use strict; use warnings;/;

  # Render
  my $mt = Mojo::Template->new($conf->{template} || {});
  $mt->prepend($prepend);
  $content = $mt->render($content, $app);
  utf8::encode $content;

  return $content;
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::JsonConfig - JSON Configuration Plugin

=head1 SYNOPSIS

  # myapp.json
  {
    "foo"       : "bar",
    "music_dir" : "<%= app->home->rel_dir('music') %>"
  }

  # Mojolicious
  my $config = $self->plugin('json_config');

  # Mojolicious::Lite
  my $config = plugin 'json_config';

  # Reads myapp.json by default and puts the parsed version into the stash
  my $config = $self->stash('config');

  # Everything can be customized with options
  my $config = plugin json_config => {
    file      => '/etc/myapp.conf',
    stash_key => 'conf'
  };

=head1 DESCRIPTION

L<Mojolicious::Plugin::JsonConfig> is a JSON configuration plugin that
preprocesses it's input with L<Mojo::Template>.
The application object can be accessed via C<$app> or the C<app> helper.
You can extend the normal config file C<myapp.json> with C<mode> specific
ones like C<myapp.$mode.json>.

=head1 OPTIONS

L<Mojolicious::Plugin::JsonConfig> accepts the same options as
L<Mojolicious::Plugin::Config> and the following new ones.

=head2 C<template>

  # Mojolicious::Lite
  plugin json_config => {template => {line_start => '.'}};

Template options.

=head1 HELPERS

L<Mojolicious::Plugin::JsonConfig> defines the same helpers as
L<Mojolicious::Plugin::Config>.

=head1 METHODS

L<Mojolicious::Plugin::JsonConfig> inherits all methods from
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

  $plugin->register;

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
