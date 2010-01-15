# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Plugin::JsonConfig;

use strict;
use warnings;

use base 'Mojolicious::Plugin';

use Mojo::JSON;
use Mojo::Template;
use File::Basename ();
use File::Spec     ();

sub register {
    my ($self, $app, $conf) = @_;

    # Config
    $conf ||= {};

    my $file = $conf->{file};

    # Default configuration file
    unless ($file) {

        # Get the app script basename
        $file = File::Basename::basename($0);

        # Remove .pl and .p6 extentions
        $file =~ s/\.p(?:l|6)$//i;

        # Default extension
        $file .= '.json';
    }

    # Make path absolute unless otherwise
    $file = $app->home->rel_file($file)
      unless File::Spec->file_name_is_absolute($file);

    die "Configuration file '$file' not found" unless -e $file;

    $app->log->debug("Reading configuration file '$file'");

    open FILE, "<:encoding(UTF-8)", $file
      or die "Can't read configuration file '$file': $!";
    my $config = do { local $/; <FILE> };
    close FILE;

    # $app
    my $prepend = 'my $app = shift;';

    # Be less strict
    $prepend .= q/no strict 'refs'; no warnings 'redefine';/;

    # app() helper
    $prepend .= "sub app; *app = sub { \$app };";

    # Be strict again
    $prepend .= q/use strict; use warnings;/;

    my $mt = Mojo::Template->new;
    $mt->prepend($prepend);

    # Render through template engine first
    $config = $mt->render($config, $app);

    my $json = Mojo::JSON->new;
    $config = $json->decode($config);
    die "Can't parse configuration: " . $json->error
      if !$config && $json->error;

    # Add config to the stash
    my $stash_key = $conf->{stash_key} || 'config';

    $app->plugins->add_hook(
        before_dispatch => sub {
            my ($self, $c) = @_;

            $c->stash($stash_key => $config);
        }
    );
}

1;
__END__

=head1 NAME

Mojolicious::Plugin::JsonConfig - JSON Configuration Plugin

=head1 SYNOPSIS

    # Given configuration
    {
        "foo"       : "bar"
        "music_dir" : "<%= app->home->rel_dir('music') %>"
    }

    # Mojolicious
    $self->plugin('json_config');

    # Mojolicious::Lite
    plugin 'json_config';

    # Reads myapp.json by default on startup and puts it into the stash
    # ('config' key is default)
    my $config = $self->stash('config');

    # or with options
    plugin 'json_config' => {
        file      => '/etc/myapp.conf',
        stash_key => 'conf'
    };

=head1 DESCRIPTION

L<Mojolicous::Plugin::JsonConfig> is a JSON configuration plugin that first is
parsed by L<Mojo::Template> and then by L<Mojo::JSON>.

To get to the application object L<$app> variable or L<app> helper can be used.

=head1 CONFIGURATION OPTIONS

=head2 C<file>

    # Mojolicious::Lite
    plugin 'json_config' => {file => 'myapp.conf'};
    plugin 'json_config' => {file => '/etc/foo.json'};

By default C<myapp.json> file is searched under the current application home
directory.

=head2 C<stash_key>

    # Mojolicious::Lite
    plugin 'json_config' => {stash_key => 'conf'};

=head1 METHODS

L<Mojolicious::Plugin::JsonConfig> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 C<register>

    $plugin->register;

=cut
