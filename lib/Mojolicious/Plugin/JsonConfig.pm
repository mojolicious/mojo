# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::JsonConfig;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

require File::Basename;
require File::Spec;

use Mojo::JSON;
use Mojo::Template;

# And so we say goodbye to our beloved pet, Nibbler, who's gone to a place
# where I, too, hope one day to go. The toilet.
sub register {
    my ($self, $app, $conf) = @_;

    # Plugin config
    $conf ||= {};

    # File
    my $file = $conf->{file};
    unless ($file) {

        # Basename
        $file = File::Basename::basename($0);

        # Remove .pl, .p6 and .t extentions
        $file =~ s/(?:\.p(?:l|6))|\.t$//i;

        # Default extension
        $file .= '.json';
    }

    # Absolute path
    $file = $app->home->rel_file($file)
      unless File::Spec->file_name_is_absolute($file);

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

    # Stash key
    my $stash_key = $conf->{stash_key} || 'config';

    # Merge
    $config = {%{$conf->{default}}, %$config} if $conf->{default};

    # Add hook
    $app->plugins->add_hook(
        before_dispatch => sub {
            my ($self, $c) = @_;

            # Stash
            $c->stash($stash_key => $config);
        }
    );

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

    # Parse
    my $json   = Mojo::JSON->new;
    my $config = $json->decode($encoded);
    my $error  = $json->error;
    die qq/Couldn't parse config file "$file": $error/ if !$config && $error;

    return $config;
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

=head1 OPTIONS

=head2 C<default>

    # Mojolicious::Lite
    plugin json_config => {default => {foo => 'bar'}};

=head2 C<file>

    # Mojolicious::Lite
    plugin json_config => {file => 'myapp.conf'};
    plugin json_config => {file => '/etc/foo.json'};

By default C<myapp.json> is searched in the application home directory.

=head2 C<stash_key>

    # Mojolicious::Lite
    plugin json_config => {stash_key => 'conf'};

=head2 C<template>

    # Mojolicious::Lite
    plugin json_config => {template => {line_start => '.'}};

=head1 METHODS

L<Mojolicious::Plugin::JsonConfig> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

Register plugin hooks in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
