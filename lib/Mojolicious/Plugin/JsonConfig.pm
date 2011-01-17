package Mojolicious::Plugin::JsonConfig;
use Mojo::Base 'Mojolicious::Plugin';

require File::Basename;
require File::Spec;

use Mojo::JSON;
use Mojo::Template;

use constant DEBUG => $ENV{MOJO_JSON_CONFIG_DEBUG} || 0;

# And so we say goodbye to our beloved pet, Nibbler, who's gone to a place
# where I, too, hope one day to go. The toilet.
sub register {
    my ($self, $app, $conf) = @_;

    # Plugin config
    $conf ||= {};

    # File
    my $file = $conf->{file} || $ENV{MOJO_JSON_CONFIG};
    unless ($file) {

        # Basename
        $file = File::Basename::basename($0);

        # Remove .pl, .p6 and .t extentions
        $file =~ s/(?:\.p(?:l|6))|\.t$//i;

        # Default extension
        $file .= '.' . ($conf->{ext} || 'json');
    }

    # Debug
    warn "JSON CONFIG FILE $file\n" if DEBUG;

    # Mode specific config file
    my $mode;
    if ($file =~ /^(.*)\.([^\.]+)$/) {
        $mode = join '.', $1, $app->mode, $2;

        # Debug
        warn "MODE SPECIFIC JSON CONFIG FILE $mode\n" if DEBUG;
    }

    # Absolute path
    $file = $app->home->rel_file($file)
      unless File::Spec->file_name_is_absolute($file);
    $mode = $app->home->rel_file($mode)
      if defined $mode && !File::Spec->file_name_is_absolute($mode);

    # Read config file
    my $config = {};
    my $template = $conf->{template} || {};
    if (-e $file) { $config = $self->_read_config($file, $template, $app) }

    # Check for default
    else {

        # All missing
        die qq/Config file "$file" missing, maybe you need to create it?\n/
          unless $conf->{default};

        # Debug
        $app->log->debug(
            qq/Config file "$file" missing, using default config./);
    }

    # Merge with mode specific config file
    if (defined $mode && -e $mode) {
        $config = {%$config, %{$self->_read_config($mode, $template, $app)}};
    }

    # Merge
    $config = {%{$conf->{default}}, %$config} if $conf->{default};

    # Default
    $app->defaults(($conf->{stash_key} || 'config') => $config);

    return $config;
}

sub _parse_config {
    my ($self, $encoded, $name) = @_;

    # Parse
    my $json   = Mojo::JSON->new;
    my $config = $json->decode($encoded);
    my $error  = $json->error;
    die qq/Couldn't parse config "$name": $error/ if !$config && $error;
    die qq/Invalid config "$name"./ if !$config || ref $config ne 'HASH';

    return $config;
}

sub _read_config {
    my ($self, $file, $template, $app) = @_;

    # Debug
    $app->log->debug(qq/Reading config file "$file"./);

    # Slurp UTF-8 file
    open FILE, "<:encoding(UTF-8)", $file
      or die qq/Couldn't open config file "$file": $!/;
    my $encoded = do { local $/; <FILE> };
    close FILE;

    # Process
    $encoded = $self->_render_config($encoded, $template, $app);
    return $self->_parse_config($encoded, $file, $app);
}

sub _render_config {
    my ($self, $encoded, $template, $app) = @_;

    # Instance
    my $prepend = 'my $app = shift;';

    # Be less strict
    $prepend .= q/no strict 'refs'; no warnings 'redefine';/;

    # Helper
    $prepend .= "sub app; *app = sub { \$app };";

    # Be strict again
    $prepend .= q/use strict; use warnings;/;

    # Render
    my $mt = Mojo::Template->new($template);
    $mt->prepend($prepend);
    $encoded = $mt->render($encoded, $app);
    utf8::encode $encoded;

    return $encoded;
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
    $self->plugin('json_config');

    # Mojolicious::Lite
    plugin 'json_config';

    # Reads myapp.json by default and puts the parsed version into the stash
    my $config = $self->stash('config');

    # Everything can be customized with options
    my $config = plugin json_config => {
        file      => '/etc/myapp.conf',
        stash_key => 'conf'
    };

=head1 DESCRIPTION

L<Mojolicous::Plugin::JsonConfig> is a JSON configuration plugin that
preprocesses it's input with L<Mojo::Template>.

The application object can be accessed via C<$app> or the C<app> helper.
You can extend the normal config file C<myapp.json> with C<mode> specific
ones like C<myapp.$mode.json>.

=head1 OPTIONS

=head2 C<default>

    # Mojolicious::Lite
    plugin json_config => {default => {foo => 'bar'}};

Default configuration.

=head2 C<ext>

    # Mojolicious::Lite
    plugin json_config => {ext => 'conf'};

File extension of config file, defaults to C<json>.

=head2 C<file>

    # Mojolicious::Lite
    plugin json_config => {file => 'myapp.conf'};
    plugin json_config => {file => '/etc/foo.json'};

Configuration file, defaults to the value of C<MOJO_JSON_CONFIG> or
C<myapp.json> in the application home directory.

=head2 C<stash_key>

    # Mojolicious::Lite
    plugin json_config => {stash_key => 'conf'};

Configuration stash key.

=head2 C<template>

    # Mojolicious::Lite
    plugin json_config => {template => {line_start => '.'}};

Template options.

=head1 METHODS

L<Mojolicious::Plugin::JsonConfig> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
