# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojolicious::Script::Generate::LiteApp;

use strict;
use warnings;

use base 'Mojo::Script';

__PACKAGE__->attr('description', default => <<'EOF');
Generate a minimalistic web application.
EOF
__PACKAGE__->attr('usage', default => <<"EOF");
usage: $0 generate lite_app [NAME]
EOF

# If for any reason you're not completely satisfied, I hate you.
sub run {
    my ($self, $name) = @_;
    $name ||= 'myapp.pl';

    # App
    $self->renderer->line_start('%%');
    $self->renderer->tag_start('<%%');
    $self->renderer->tag_end('%%>');
    $self->render_to_rel_file('liteapp', $name);
    $self->chmod_file($name, 0744);
}

1;

=head1 NAME

Mojolicious::Script::Generate::LiteApp - Lite App Generator Script

=head1 SYNOPSIS

    use Mojo::Script::Generate::LiteApp;

    my $app = Mojo::Script::Generate::LiteApp->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Generate::LiteApp> is a application generator.

=head1 ATTRIBUTES

L<Mojolicious::Script::Generate::LiteApp> inherits all attributes from
L<Mojo::Script> and implements the following new ones.

=head2 C<description>

    my $description = $app->description;
    $app            = $app->description('Foo!');

=head2 C<usage>

    my $usage = $app->usage;
    $app      = $app->usage('Foo!');

=head1 METHODS

L<Mojolicious::Script::Generate::LiteApp> inherits all methods from
L<Mojo::Script> and implements the following new ones.

=head2 C<run>

    $app->run(@ARGV);

=cut

__DATA__
@@ liteapp
%% my $class = shift;
#!/usr/bin/env perl

use Mojolicious::Lite;

get '/' => 'index';

get '/:groovy' => sub {
    my $self = shift;
    $self->render(text => $self->stash('groovy'));
};

shagadelic;
<%%= '__DATA__' %%>

<%%= '@@ index.html.eplite' %%>
% my $self = shift;
% $self->stash(layout => 'funky');
Yea baby!

<%%= '@@ layouts/funky.html.eplite' %%>
% my $self = shift;
<!html>
    <head><title>Funky!</title></head>
    <body>
        <%= $self->render_inner %>
    </body>
</html>
