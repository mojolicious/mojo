# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Command::Generate::App;

use strict;
use warnings;

use base 'Mojo::Command';

__PACKAGE__->attr(description => <<'EOF');
Generate application directory structure.
EOF
__PACKAGE__->attr(usage => <<"EOF");
usage: $0 generate app [NAME]
EOF

# Why can't she just drink herself happy like a normal person?
sub run {
    my ($self, $class) = @_;
    $class ||= 'MyMojoliciousApp';

    my $name = $self->class_to_file($class);

    # Script
    $self->render_to_rel_file('mojo', "$name/script/$name", $class);
    $self->chmod_file("$name/script/$name", 0744);

    # Appclass
    my $app = $self->class_to_path($class);
    $self->render_to_rel_file('appclass', "$name/lib/$app", $class);

    # Controller
    my $controller = "${class}::Example";
    my $path       = $self->class_to_path($controller);
    $self->render_to_rel_file('controller', "$name/lib/$path", $controller);

    # Test
    $self->render_to_rel_file('test', "$name/t/basic.t", $class);

    # Log
    $self->create_rel_dir("$name/log");

    # Static
    $self->render_to_rel_file('static', "$name/public/index.html");

    # Layout and Templates
    $self->renderer->line_start('%%');
    $self->renderer->tag_start('<%%');
    $self->renderer->tag_end('%%>');
    $self->render_to_rel_file('not_found',
        "$name/templates/not_found.html.ep");
    $self->render_to_rel_file('exception',
        "$name/templates/exception.html.ep");
    $self->render_to_rel_file('layout',
        "$name/templates/layouts/default.html.ep");
    $self->render_to_rel_file('welcome',
        "$name/templates/example/welcome.html.ep");
}

1;
__DATA__
@@ mojo
% my $class = shift;
#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;

use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../lib";

# Check if Mojo is installed
eval 'use Mojolicious::Commands';
die <<EOF if $@;
It looks like you don't have the Mojo Framework installed.
Please visit http://mojolicious.org for detailed installation instructions.

EOF

# Application
$ENV{MOJO_APP} ||= '<%= $class %>';

# Start commands
Mojolicious::Commands->start;
@@ appclass
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojolicious';

# This method will run once at server start
sub startup {
    my $self = shift;

    # Routes
    my $r = $self->routes;

    # Default route
    $r->route('/:controller/:action/:id')->to('example#welcome', id => 1);
}

1;
@@ controller
% my $class = shift;
package <%= $class %>;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# This action will render a template
sub welcome {
    my $self = shift;

    # Render template "example/welcome.html.ep" with message
    $self->render(message => 'Welcome to the Mojolicious Web Framework!');
}

1;
@@ static
<!doctype html><html>
    <head><title>Welcome to the Mojolicious Web Framework!</title></head>
    <body>
        <h2>Welcome to the Mojolicious Web Framework!</h2>
        This is the static document "public/index.html",
        <a href="/">click here</a> to get back to the start.
    </body>
</html>
@@ test
% my $class = shift;
#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;
use Test::Mojo;

use_ok('<%= $class %>');

# Test
my $t = Test::Mojo->new(app => '<%= $class %>');
$t->get_ok('/')->status_is(200)->content_type_is('text/html')
  ->content_like(qr/Mojolicious Web Framework/i);
@@ not_found
<!doctype html><html>
    <head><title>Not Found</title></head>
    <body>
        The page you were requesting
        "<%= $self->req->url->path || '/' %>"
        could not be found.
    </body>
</html>
@@ exception
<!doctype html><html>
% my $s = $self->stash;
% my $e = $self->stash('exception');
% delete $s->{inner_template};
% delete $s->{exception};
% my $dump = dumper $s;
% $s->{exception} = $e;
    <head>
	    <title>Exception</title>
	    <style type="text/css">
	        body {
		        font: 0.9em Verdana, "Bitstream Vera Sans", sans-serif;
	        }
	        .snippet {
                font: 115% Monaco, "Courier New", monospace;
	        }
	    </style>
    </head>
    <body>
        <% if ($self->app->mode eq 'development') { %>
	        <div>
                This page was generated from the template
                "templates/exception.html.ep".
            </div>
            <div class="snippet"><pre><%= $e->message %></pre></div>
            <div>
                <% for my $line (@{$e->lines_before}) { %>
                    <div class="snippet">
                        <%= $line->[0] %>: <%= $line->[1] %>
                    </div>
                <% } %>
                <% if ($e->line->[0]) { %>
                    <div class="snippet">
	                    <b><%= $e->line->[0] %>: <%= $e->line->[1] %></b>
	                </div>
                <% } %>
                <% for my $line (@{$e->lines_after}) { %>
                    <div class="snippet">
                        <%= $line->[0] %>: <%= $line->[1] %>
                    </div>
                <% } %>
            </div>
            <div class="snippet"><pre><%= $dump %></pre></div>
        <% } else { %>
            <div>Page temporarily unavailable, please come back later.</div>
        <% } %>
    </body>
</html>
@@ layout
<!doctype html><html>
    <head><title>Welcome</title></head>
    <body><%== content %></body>
</html>
@@ welcome
% layout 'default';
<h2><%= $message %></h2>
This page was generated from the template
"templates/example/welcome.html.ep" and the layout
"templates/layouts/default.html.ep",
<a href="<%== url_for %>">click here</a>
to reload the page or
<a href="/index.html">here</a>
to move forward to a static page.
__END__
=head1 NAME

Mojolicious::Command::Generate::App - App Generator Command

=head1 SYNOPSIS

    use Mojolicious::Command::Generate::App;

    my $app = Mojolicious::Command::Generate::App->new;
    $app->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Generate::App> is a application generator.

=head1 ATTRIBUTES

L<Mojolicious::Command::Generate::App> inherits all attributes from
L<Mojo::Command> and implements the following new ones.

=head2 C<description>

    my $description = $app->description;
    $app            = $app->description('Foo!');

=head2 C<usage>

    my $usage = $app->usage;
    $app      = $app->usage('Foo!');

=head1 METHODS

L<Mojolicious::Command::Generate::App> inherits all methods from
L<Mojo::Command> and implements the following new ones.

=head2 C<run>

    $app->run(@ARGV);

=cut
