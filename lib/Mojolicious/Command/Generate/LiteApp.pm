# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Command::Generate::LiteApp;

use strict;
use warnings;

use base 'Mojo::Command';

__PACKAGE__->attr(description => <<'EOF');
Generate a minimalistic web application.
EOF
__PACKAGE__->attr(usage => <<"EOF");
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
__DATA__
@@ liteapp
%% my $class = shift;
#!/usr/bin/env perl

use Mojolicious::Lite;

get '/' => 'index';

get '/:groovy' => sub {
    my $self = shift;
    $self->render_text($self->param('groovy'));
};

shagadelic;
<%%= '__DATA__' %%>

<%%= '@@ index.html.ep' %%>
% layout 'funky';
Yea baby!

<%%= '@@ layouts/funky.html.ep' %%>
<!doctype html><html>
    <head><title>Funky!</title></head>
    <body><%== content %></body>
</html>
__END__
=head1 NAME

Mojolicious::Command::Generate::LiteApp - Lite App Generator Command

=head1 SYNOPSIS

    use Mojolicious::Command::Generate::LiteApp;

    my $app = Mojolicious::Command::Generate::LiteApp->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Generate::LiteApp> is a application generator.

=head1 ATTRIBUTES

L<Mojolicious::Command::Generate::LiteApp> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $app->description;
    $app            = $app->description('Foo!');

=head2 C<usage>

    my $usage = $app->usage;
    $app      = $app->usage('Foo!');

=head1 METHODS

L<Mojolicious::Command::Generate::LiteApp> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

    $app->run(@ARGV);

=cut
