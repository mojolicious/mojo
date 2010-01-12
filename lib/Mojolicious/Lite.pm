# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Lite;

use strict;
use warnings;

use base 'Mojolicious';

use File::Spec;
use FindBin;

# Make reloading work
BEGIN { $INC{$0} = $0 }

# It's the future, my parents, my co-workers, my girlfriend,
# I'll never see any of them ever again... YAHOOO!
sub import {
    my $class = shift;

    # Lite apps are strict!
    strict->import;
    warnings->import;

    # Home
    $ENV{MOJO_HOME} ||= File::Spec->catdir(split '/', $FindBin::Bin);

    # Initialize app
    my $app = $class->new;

    # Initialize routes
    my $routes = $app->routes;

    # Route generator
    my $route = sub {
        my ($methods, @args) = @_;

        my ($cb, $constraints, $defaults, $name, $pattern);
        my $conditions = [];

        # Route information
        my $condition;
        while (my $arg = shift @args) {

            # Condition can be everything
            if ($condition) {
                push @$conditions, $condition => $arg;
                $condition = undef;
            }

            # First scalar is the pattern
            elsif (!ref $arg && !$pattern) { $pattern = $arg }

            # Scalar
            elsif (!ref $arg && @args) { $condition = $arg }

            # Last scalar is the route name
            elsif (!ref $arg) { $name = $arg }

            # Callback
            elsif (ref $arg eq 'CODE') { $cb = $arg }

            # Constraints
            elsif (ref $arg eq 'ARRAY') { $constraints = $arg }

            # Defaults
            elsif (ref $arg eq 'HASH') { $defaults = $arg }
        }

        # Defaults
        $cb ||= sub {1};
        $constraints ||= [];

        # Merge
        $defaults ||= {};
        $defaults = {%$defaults, callback => $cb};

        # Name
        $name ||= '';

        # Create bridge
        return $routes =
          $app->routes->bridge($pattern, {@$constraints})->over($conditions)
          ->to($defaults)->name($name)
          if !ref $methods && $methods eq 'ladder';

        # Create route
        $routes->route($pattern, {@$constraints})->over($conditions)
          ->via($methods)->to($defaults)->name($name);
    };

    # Prepare exports
    my $caller = caller;
    no strict 'refs';
    no warnings 'redefine';

    # Default template class
    $app->renderer->default_template_class($caller);

    # Export
    *{"${caller}::app"}    = sub {$app};
    *{"${caller}::any"}    = sub { $route->(ref $_[0] ? shift : [], @_) };
    *{"${caller}::get"}    = sub { $route->('get', @_) };
    *{"${caller}::ladder"} = sub { $route->('ladder', @_) };
    *{"${caller}::plugin"} = sub { $app->plugin(@_) };
    *{"${caller}::post"}   = sub { $route->('post', @_) };

    # We are most likely the app in a lite environment
    $ENV{MOJO_APP} = $app;

    # Shagadelic!
    *{"${caller}::shagadelic"} = sub { Mojolicious::Lite->start(@_) };
}

1;
__END__

=head1 NAME

Mojolicious::Lite - Micro Web Framework

=head1 SYNOPSIS

    # Using Mojolicious::Lite will enable "strict" and "warnings"
    use Mojolicious::Lite;

    # Route with placeholder
    get '/:foo' => sub {
        my $self = shift;
        $self->render_text('Yea baby!');
    };

    # Start the Mojolicious command system
    shagadelic;

=head1 DESCRIPTION

L<Mojolicous::Lite> is a micro web framework built around L<Mojolicious>.

A minimal application looks like this.

    #!/usr/bin/env perl

    use Mojolicious::Lite;

    get '/' => sub {
        my $self = shift;
        $self->render_text('Yea baby!');
    };

    shagadelic;

There is also a helper command to generate a small example application.

    % mojolicious generate lite_app

All the normal L<Mojolicious> command options are available from the command
line.

    % ./myapp.pl daemon
    Server available at http://127.0.0.1:3000.

    % ./myapp.pl daemon 8080
    Server available at http://127.0.0.1:8080.

    % ./myapp.pl daemon_prefork
    Server available at http://127.0.0.1:3000.

    % ./myapp.pl cgi
    ...CGI output...

    % ./myapp.pl fastcgi
    ...Blocking FastCGI main loop...

The shagadelic call that starts the L<Mojolicious> command system can be
customized to override normal C<@ARGV> use.

    shagadelic('cgi');

Your application will automatically reload itself if you set the C<--reload>
option, so you don't have to restart the server after every change.

    % ./myapp.pl daemon --reload
    Server available at http://127.0.0.1:3000.

Routes are basically just fancy paths that can contain different kinds of
placeholders.

    # /foo
    get '/foo' => sub {
        my $self = shift;
        $self->render_text('Yea baby!');
    };

All routes can have a name associated with them, this allows automatic
template detection and back referencing with C<url_for>.
Names are always the last argument.

    # /
    get '/' => 'index';

    # /foo
    get '/foo' => 'foo';

    # /bar
    get '/bar' => sub {
        my $self = shift;
        $self->render_text('Hi!')
    } => 'bar';

    __DATA__

    @@ index.html.ep
    <a href="<%= url_for 'foo' %>">Foo</a>.
    <a href="<%= url_for 'bar' %>">Bar</a>.

    @@ foo.html.ep
    <a href="<%= url_for 'index' %>">Home</a>.

Templates can have layouts.

    # GET /with_layout
    get '/with_layout' => sub {
        my $self = shift;
        $self->render('with_layout', layout => 'green');
    };

    __DATA__

    @@ with_layout.html.ep
    We've got content!

    @@ layouts/green.html.ep
    <!doctype html><html>
        <head><title>Green!</title></head>
        <body><%= content %></body>
    </html>

Templates can also extend each other.

    # GET /
    get '/' => 'first';

    # GET /second
    get '/second' => 'second';

    __DATA__

    @@ first.html.ep
    % extends 'second';
    %{ content header =>
        <title>Howdy!</title>
    %}
    First!

    @@ second.html.ep
    % layout 'third';
    %{ content header =>
        <title>Welcome!</title>
    %}
    Second!

    @@ layouts/third.html.ep
    <!doctype html><html>
        <head>
            <%{= content header => %>
                <title>Lame default title...</title>
            <%}%>
        </head>
        <body><%= content %></body>
    </html>

Route placeholders allow capturing parts of a request path until a C</> or
C<.> separator occurs, results will be stored by name in the C<stash> and
C<param>.

    # /foo/*
    get '/foo/:bar' => sub {
        my $self = shift;
        my $bar  = $self->stash('bar');
        $self->render_text("Our :bar placeholder matched $bar");
    };

    # /*something/foo
    get '/(:bar)something/foo' => sub {
        my $self = shift;
        my $bar  = $self->param('bar');
        $self->render_text("Our :bar placeholder matched $bar");
    };

Relaxed placeholders allow matching of everything until a C</> occurs.

    # GET /hello/*
    get '/hello/(.you)' => sub {
        shift->render('groovy');
    };

    __DATA__

    @@ groovy.html.ep
    Your name is <%= $you %>.

Wildcard placeholders allow matching absolutely everything, including
C</> and C<.>.

    # /hello/*
    get '/hello/(*you)' => sub {
        shift->render('groovy');
    };

    __DATA__

    @@ groovy.html.ep
    Your name is <%= $you %>.

Routes can be restricted to specific request methods.

    # GET /bye
    get '/bye' => sub { shift->render_text('Bye!') };

    # POST /bye
    post '/bye' => sub { shift->render_text('Bye!') };

    # GET|POST|DELETE /bye
    any [qw/get post delete/] => '/bye' => sub {
        shift->render_text('Bye!');
    };

    # /baz
    any '/baz' => sub {
        my $self   = shift;
        my $method = $self->req->method;
        $self->render_text("You called /baz with $method");
    };

All placeholders get compiled to a regex internally, with regex constraints
this process can be easily customized.

    # /*
    any '/:bar' => [bar => qr/\d+/] => sub {
        my $self = shift;
        my $bar  = $self->param('bar');
        $self->render_text("Our :bar placeholder matched $bar");
    };

Routes allow default values to make placeholders optional.

    # /hello/*
    get '/hello/:name' => {name => 'Sebastian'} => sub {
        my $self = shift;
        $self->render('groovy', format => 'txt');
    };

    __DATA__

    @@ groovy.txt.ep
    My name is <%= $name %>.

All those features can be easily used together.

    # /everything/*?name=*
    get '/everything/:stuff' => [stuff => qr/\d+/] => {stuff => 23} => sub {
        shift->render('welcome');
    };

    __DATA__

    @@ welcome.html.ep
    Stuff is <%= $stuff %>.
    Query param name is <%= param 'name' %>.

Here's a fully functional example for a html form handling application using
multiple features at once.

    #!/usr/bin/env perl

    use Mojolicious::Lite;

    get '/' => 'index';

    post '/form' => sub {
        my $self = shift;

        my $groovy = $self->param('groovy') || 'Austin Powers';
        $groovy =~ s/[^\w\s]+//g;

        $self->render(
            template => 'welcome',
            layout   => 'funky',
            groovy   => $groovy
        );
    } => 'form';

    shagadelic;
    __DATA__

    @@ index.html.ep
    % layout 'funky');
    Who is groovy?
    <form action="<%= url_for 'form' %>" method="POST">
        <input type="text" name="groovy" />
        <input type="submit" value="Woosh!">
    </form>

    @@ welcome.html.ep
    <%= $groovy %> is groovy!
    <%= include 'menu' %>

    @@ menu.html.ep
    <a href="<%= url_for 'index' %>">Try again</a>

    @@ layouts/funky.html.ep
    <!doctype html><html>
        <head><title>Funky!</title></head>
        <body><%= content %>
        </body>
    </html>

Ladders can be used for authentication and to share code between multiple
routes.
All routes following a ladder are only evaluated if the ladder returns a
true value.

    use Mojolicious::Lite;

    # Authenticate based on name parameter
    ladder sub {
        my $self = shift;

        # Authenticated
        my $name = $self->param('name') || '';
        return 1 if $name eq 'Bender';

        # Not authenticated
        $self->render('denied');
        return;
    };

    # GET / (with ladder authentication)
    get '/' => 'index';

    shagadelic;
    __DATA__;

    @@ denied.html.ep
    You are not Bender, permission denied!

    @@ index.html.ep
    Hi Bender!

Conditions such as C<agent> allow even more powerful route constructs.

    # /foo
    get '/foo' => (agent => qr/Firefox/) => sub {
        shift->render_text('Congratulations, you are using a cool browser!');
    }

    # /foo
    get '/foo' => (agent => qr/Internet Explorer/) => sub {
        shift->render_text('Dude, you really need to upgrade to Firefox!');
    }

Formats can be automatically detected by looking at file extensions.

    # /detection.html
    # /detection.txt
    get '/detection' => sub {
        my $self = shift;
        $self->render('detected');
    };

    __DATA__

    @@ detected.html.ep
    <!doctype html><html>
        <head><title>Detected!</title></head>
        <body>HTML was detected.</body>
    </html>

    @@ detected.txt.ep
    TXT was detected.

External templates will be searched by the renderer in a C<templates>
directory.

    # /external
    any '/external' => sub {
        my $self = shift;

        # templates/foo/bar.html.ep
        $self->render('foo/bar');
    };

Static files will be automatically served from the C<public> directory if it
exists.

    % mkdir public
    % mv something.js public/something.js

Testing your application is as easy as creating a C<t> directory and filling
it with normal Perl unit tests like C<t/funky.t>.

    use Test::More tests => 3;
    use Test::Mojo;

    use FindBin;
    require "$FindBin::Bin/../myapp.pl";

    my $t = Test::Mojo->new;
    $t->get_ok('/')->status_is(200)->content_like(qr/Funky!/);

Run all unit tests with the C<test> command.

    % ./myapp.pl test

To disable debug messages later in a production setup you can change the
L<Mojolicious> mode, default will be C<development>.

    % MOJO_MODE=production ./myapp.pl

Log messages will be automatically written to a C<log/$mode.log> file if a
C<log> directory exists.

    % mkdir log

For more control the L<Mojolicious> instance can be accessed directly.

    app->log->level('error');
    app->routes->route('/foo/:bar')->via('get')->to(callback => sub {
        my $self = shift;
        $self->render_text('Hello Mojo!');
    });

In case a lite app needs to grow, lite and real L<Mojolicous> applications
can be easily mixed to make the transition process very smooth.

    package MyApp::Foo;
    use base 'Mojolicious::Controller';

    sub index { shift->render_text('It works!') }

    package main;
    use Mojolicious::Lite;

    get '/bar' => sub { shift->render_text('This too!') };

    app->routes->namespace('MyApp');
    app->routes->route('/foo/:action')->via('get')->to('foo#index');

    shagadelic;

=head1 ATTRIBUTES

L<Mojolicious::Lite> inherits all attributes from L<Mojolicious>.

=head1 METHODS

L<Mojolicious::Lite> inherits all methods from L<Mojolicious>.

=cut
