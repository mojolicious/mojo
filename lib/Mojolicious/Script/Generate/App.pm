# Copyright (C) 2008, Sebastian Riedel.

package Mojolicious::Script::Generate::App;

use strict;
use warnings;

use base 'Mojo::Script';

__PACKAGE__->attr('description', chained => 1, default => <<'EOF');
* Generate application directory structure. *
Takes a name as option, by default MyMojoliciousApp will be used.
    generate app TestApp
EOF

# Why can't she just drink herself happy like a normal person?
sub run {
    my ($self, $class) = @_;
    $class ||= 'MyMojoliciousApp';

    my $name = $self->class_to_file($class);

    # Script
    $self->render_to_rel_file('mojo', "$name/bin/$name", $class);
    $self->chmod_file("$name/bin/$name", 0744);

    # Appclass
    my $app = $self->class_to_path($class);
    $self->render_to_rel_file('appclass', "$name/lib/$app", $class);

    # Controller
    my $controller = "${class}::Example";
    my $path = $self->class_to_path($controller);
    $self->render_to_rel_file('controller', "$name/lib/$path", $controller);

    # Test
    $self->render_to_rel_file('test', "$name/t/basic.t", $class);

    # Static
    $self->render_to_rel_file('404', "$name/public/404.html");
    $self->render_to_rel_file('static', "$name/public/index.html");

    # Template
    $self->renderer->line_start('%%');
    $self->renderer->tag_start('<%%');
    $self->renderer->tag_end('%%>');
    $self->render_to_rel_file(
        'welcome', "$name/templates/example/welcome.phtml"
    );
}

1;

=head1 NAME

Mojolicious::Script::Generate::App - App Generator Script

=head1 SYNOPSIS

    use Mojo::Script::Generate::App;

    my $app = Mojo::Script::Generate::App->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojo::Script::Generate::App> is a application generator.

=head1 ATTRIBUTES

L<Mojolicious::Script::Generate::App> inherits all attributes from
L<Mojo::Script>.

=head1 METHODS

L<Mojolicious::Script::Generate::App> inherits all methods from
L<Mojo::Script> and implements the following new ones.

=head2 C<run>

    $app->run(@ARGV);

=cut

__DATA__
__404__
<!doctype html>
    <head><title>Document not found.</title></head>
    <body><h2>Document not found.</h2></body>
</html>
__mojo__
% my $class = shift;
#!<%= $^X %>

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/lib";
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";

$ENV{MOJO_APP} = '<%= $class %>';

# Check if Mojo is installed
eval 'use Mojolicious::Scripts';
if ($@) {
    print <<EOF;
It looks like you don't have the Mojo Framework installed.
Please visit http://mojolicious.org for detailed installation instructions.

EOF
    exit;
}

# Start the script system
my $scripts = Mojolicious::Scripts->new;
$scripts->run(@ARGV);
__appclass__
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojolicious';

# This method will run for each request
sub dispatch {
    my ($self, $c) = @_;

    # Try to find a static file
    $self->static->dispatch($c);

    # Use routes if we don't have a response code yet
    $self->routes->dispatch($c) unless $c->res->code;

    # Nothing found, serve static file "public/404.html"
    unless ($c->res->code) {
        $self->static->serve($c, '/404.html');
        $c->res->code(404);
    }
}

# This method will run once at server start
sub startup {
    my $self = shift;

    # Routes
    my $r = $self->routes;

    # Default route
    $r->route('/:controller/:action/:id')
      ->to(controller => 'example', action => 'welcome', id => 1);
}

1;
__controller__
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# This action will render a template
sub welcome {
    my ($self, $c) = @_;

    # Render template "example/welcome.phtml"
    $c->render;
}

1;
__static__
<!doctype html>
    <head><title>Welcome to the Mojolicious Web Framework!</title></head>
    <body>
        <h2>Welcome to the Mojolicious Web Framework!</h2>
        This is the static document "public/index.html",
        <a href="/">click here</a>
        to get back to the start.
    </body>
</html>
__test__
% my $class = shift;
#!perl

use strict;
use warnings;

use Mojo::Client;
use Mojo::Transaction;
use Test::More tests => 4;

use_ok('<%= $class %>');

# Prepare client and transaction
my $client = Mojo::Client->new;
my $tx     = Mojo::Transaction->new_get('/');

# Process request
$client->process_local('<%= $class %>', $tx);

# Test response
is($tx->res->code, 200);
is($tx->res->headers->content_type, 'text/html');
like($tx->res->content->file->slurp, qr/Mojolicious Web Framework/i);
__welcome__
% my $c = shift;
<!doctype html>
    <head><title>Welcome to the Mojolicious Web Framework!</title></head>
    <body>
        <h2>Welcome to the Mojolicious Web Framework!</h2>
        This page was generated from the template
        "templates/example/test.phtml",
        <a href="<%= $c->url_for %>">
            click here
        </a> 
        to reload the page or
        <a href="/index.html">
            here
        </a>
        to move forward to a static page.
    </body>
</html>