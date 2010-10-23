package Mojolicious::Lite;

use strict;
use warnings;

use base 'Mojolicious';

# Since when is the Internet all about robbing people of their privacy?
# August 6, 1991.
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
    $routes->namespace('');

    # Route generator
    my $route = sub {
        my ($methods, @args) = @_;

        my ($cb, $constraints, $defaults, $name, $pattern);
        my $conditions = [];

        # Route information
        while (defined(my $arg = shift @args)) {

            # First scalar is the pattern
            if (!ref $arg && !$pattern) { $pattern = $arg }

            # Scalar
            elsif (!ref $arg && @args) {
                push @$conditions, $arg, shift @args;
            }

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
        $constraints ||= [];

        # Defaults
        $defaults ||= {};
        $defaults->{cb} = $cb if $cb;

        # Name
        $name ||= '';

        # Create bridge
        return $routes =
          $app->routes->bridge($pattern, {@$constraints})->over($conditions)
          ->to($defaults)->name($name)
          if !ref $methods && $methods eq 'under';

        # WebSocket
        my $websocket = 1 if !ref $methods && $methods eq 'websocket';
        $methods = [] if $websocket;

        # Create route
        my $route =
          $routes->route($pattern, {@$constraints})->over($conditions)
          ->via($methods)->to($defaults)->name($name);

        # WebSocket
        $route->websocket if $websocket;

        return $route;
    };

    # Prepare exports
    my $caller = caller;
    no strict 'refs';
    no warnings 'redefine';

    # Default static and template class
    $app->static->default_static_class($caller);
    $app->renderer->default_template_class($caller);

    # Export
    *{"${caller}::new"} = *{"${caller}::app"} = sub {$app};
    *{"${caller}::any"} = sub { $route->(ref $_[0] ? shift : [], @_) };
    *{"${caller}::get"} = sub { $route->('get', @_) };
    *{"${caller}::under"} = *{"${caller}::ladder"} =
      sub { $route->('under', @_) };
    *{"${caller}::plugin"}    = sub { $app->plugin(@_) };
    *{"${caller}::post"}      = sub { $route->('post', @_) };
    *{"${caller}::websocket"} = sub { $route->('websocket', @_) };

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
        my $foo  = $self->param('foo');
        $self->render(text => "Hello from $foo!");
    };

    # Start the Mojolicious command system
    app->start;

=head1 DESCRIPTION

L<Mojolicous::Lite> is a micro web framework built around L<Mojolicious>.

A minimal Hello World application looks like this, L<strict> and L<warnings>
are automatically enabled and a few functions imported when you use
L<Mojolicious::Lite>, turning your script into a full featured web
application.

    #!/usr/bin/env perl

    use Mojolicious::Lite;

    get '/' => sub { shift->render(text => 'Hello World!') };

    app->start;

There is also a helper command to generate a small example application.

    % mojo generate lite_app

All the normal L<Mojolicious> command options are available from the command
line.
Note that CGI, FastCGI and PSGI environments can usually be auto detected and
will just work without commands.

    % ./myapp.pl daemon
    Server available at http://127.0.0.1:3000.

    % ./myapp.pl daemon --listen http://*:8080
    Server available at http://127.0.0.1:8080.

    % ./myapp.pl cgi
    ...CGI output...

    % ./myapp.pl fastcgi
    ...Blocking FastCGI main loop...

    % ./myapp.pl
    ...List of available commands (or automatically detected environment)...

The app->start call that starts the L<Mojolicious> command system can be
customized to override normal C<@ARGV> use.

    app->start('cgi');

Your application will automatically reload itself if you set the C<--reload>
option, so you don't have to restart the server after every change.

    % ./myapp.pl daemon --reload
    Server available at http://127.0.0.1:3000.

Routes are basically just fancy paths that can contain different kinds of
placeholders.

    # /foo
    get '/foo' => sub {
        my $self = shift;
        $self->render(text => 'Hello World!');
    };

All routes can have a name associated with them, this allows automatic
template detection and back referencing with C<url_for>, C<link_to> and
C<form_for>.
Names are always the last argument, the value C<*> means that the name is
simply equal to the route without non-word characters.

    # /
    get '/' => 'index';

    # /foo
    get '/foo' => '*';

    # /bar
    get '/bar' => sub {
        my $self = shift;
        $self->render(text => 'Hi!')
    } => 'bar';

    __DATA__

    @@ index.html.ep
    <%= link_to Foo => 'foo' %>.
    <%= link_to Bar => 'bar' %>.

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

Template blocks can be reused like functions in Perl scripts.

    # GET /with_block
    get '/with_block' => 'block';

    __DATA__

    @@ block.html.ep
    <% my $link = begin %>
        <% my ($url, $name) = @_; %>
        Try <%= link_to $url => begin %><%= $name %><% end %>!
    <% end %>
    <!doctype html><html>
        <head><title>Sebastians Frameworks!</title></head>
        <body>
            <%== $link->('http://mojolicious.org', 'Mojolicious') %>
            <%== $link->('http://catalystframework.org', 'Catalyst') %>
        </body>
    </html>

Templates can also pass around blocks of captured content and extend each
other.

    # GET /
    get '/' => 'first';

    # GET /second
    get '/second' => 'second';

    __DATA__

    @@ first.html.ep
    <!doctype html><html>
        <head>
            <%= content header => begin %>
                <title>Hi!</title>
            <% end %>
        </head>
        <body>
            <%= content body => begin %>
                First page!
            <% end %>
        </body>
    </html>

    @@ second.html.ep
    % extends 'first';
    <% content header => begin %>
        <title>Howdy!</title>
    <% end %>
    <% content body => begin %>
        Second page!
    <% end %>

Route placeholders allow capturing parts of a request path until a C</> or
C<.> separator occurs, results will be stored by name in the C<stash> and
C<param>.

    # /foo/* (everything except "/" and ".")
    # /foo/test
    # /foo/test123
    get '/foo/:bar' => sub {
        my $self = shift;
        my $bar  = $self->stash('bar');
        $self->render(text => "Our :bar placeholder matched $bar");
    };

    # /*something/foo (everything except "/" and ".")
    # /test/foo
    # /test123/foo
    get '/(:bar)something/foo' => sub {
        my $self = shift;
        my $bar  = $self->param('bar');
        $self->render(text => "Our :bar placeholder matched $bar");
    };

Relaxed placeholders allow matching of everything until a C</> occurs.

    # /*/hello (everything except "/")
    # /test/hello
    # /test123/hello
    # /test.123/hello
    get '/(.you)/hello' => sub {
        shift->render('groovy');
    };

    __DATA__

    @@ groovy.html.ep
    Your name is <%= $you %>.

Wildcard placeholders allow matching absolutely everything, including
C</> and C<.>.

    # /hello/* (everything)
    # /hello/test
    # /hello/test123
    # /hello/test.123/test/123
    get '/hello/(*you)' => sub {
        shift->render('groovy');
    };

    __DATA__

    @@ groovy.html.ep
    Your name is <%= $you %>.

Routes can be restricted to specific request methods.

    # GET /bye
    get '/bye' => sub { shift->render(text => 'Bye!') };

    # POST /bye
    post '/bye' => sub { shift->render(text => 'Bye!') };

    # GET|POST|DELETE /bye
    any [qw/get post delete/] => '/bye' => sub {
        shift->render(text => 'Bye!');
    };

    # /baz
    any '/baz' => sub {
        my $self   = shift;
        my $method = $self->req->method;
        $self->render(text => "You called /baz with $method");
    };

All placeholders get compiled to a regex internally, with regex constraints
this process can be easily customized.

    # /*
    any '/:bar' => [bar => qr/\d+/] => sub {
        my $self = shift;
        my $bar  = $self->param('bar');
        $self->render(text => "Our :bar placeholder matched $bar");
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

    post '/test' => sub {
        my $self = shift;

        my $groovy = $self->param('groovy') || 'Austin Powers';
        $groovy =~ s/[^\w\s]+//g;

        $self->render(
            template => 'welcome',
            layout   => 'funky',
            groovy   => $groovy
        );
    } => 'test';

    app->start;
    __DATA__

    @@ index.html.ep
    % layout 'funky';
    Who is groovy?
    <%= form_for test => (method => 'post') => begin %>
        <%= text_field 'groovy' %>
        <%= submit_button 'Woosh!' %>
    <% end %>

    @@ welcome.html.ep
    <%= $groovy %> is groovy!
    <%= include 'menu' %>

    @@ menu.html.ep
    <%= link_to index => begin %>
        Try again
    <% end %>

    @@ layouts/funky.html.ep
    <!doctype html><html>
        <head><title>Funky!</title></head>
        <body><%= content %>
        </body>
    </html>

Authentication and code shared between multiple routes can be realized easily
with the C<under> statement.
All following routes are only evaluated if the C<under> callback returned a
true value.

    use Mojolicious::Lite;

    # Authenticate based on name parameter
    under sub {
        my $self = shift;

        # Authenticated
        my $name = $self->param('name') || '';
        return 1 if $name eq 'Bender';

        # Not authenticated
        $self->render('denied');
        return;
    };

    # GET / (with authentication)
    get '/' => 'index';

    app->start;
    __DATA__;

    @@ denied.html.ep
    You are not Bender, permission denied!

    @@ index.html.ep
    Hi Bender!

Prefixing multiple routes is another good use for C<under>.

    use Mojolicious::Lite;

    # /foo
    under '/foo';

    # GET /foo/bar
    get '/bar' => sub { shift->render(text => 'bar!') };

    # GET /foo/baz
    get '/baz' => sub { shift->render(text => 'baz!') };

    app->start;

Conditions such as C<agent> allow even more powerful route constructs.

    # /foo
    get '/foo' => (agent => qr/Firefox/) => sub {
        shift->render(
            text => 'Congratulations, you are using a cool browser!');
    }

    # /foo
    get '/foo' => (agent => qr/Internet Explorer/) => sub {
        shift->render(
            text => 'Dude, you really need to upgrade to Firefox!');
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

Signed cookie based sessions just work out of the box as soon as you start
using them.
The C<flash> can be used to store values that will only be available for the
next request (unlike C<stash>, which is only available for the current
request), this is very useful in combination with C<redirect_to>.

    use Mojolicious::Lite;

    get '/login' => sub {
        my $self = shift;
        my $name = $self->param('name') || '';
        my $pass = $self->param('pass') || '';
        return $self->render unless $name eq 'sebastian' && $pass eq '1234';
        $self->session(name => $name);
        $self->flash(message => 'Thanks for logging in!');
        $self->redirect_to('index');
    } => 'login';

    get '/' => sub {
        my $self = shift;
        return $self->redirect_to('login') unless $self->session('name');
        $self->render;
    } => 'index';

    get '/logout' => sub {
        my $self = shift;
        $self->session(expires => 1);
        $self->redirect_to('index');
    } => 'logout';

    app->start;
    __DATA__

    @@ layouts/default.html.ep
    <!doctype html><html>
        <head><title>Mojolicious rocks!</title></head>
        <body><%= content %></body>
    </html>

    @@ login.html.ep
    % layout 'default';
    <%= form_for login => begin %>
        <% if (param 'name') { %>
            <b>Wrong name or password, please try again.</b><br />
        <% } %>
        Name:<br />
        <%= text_field 'name' %><br />
        Password:<br />
        <%= password_field 'pass' %><br />
        <%= submit_button 'Login' %>
    <% end %>

    @@ index.html.ep
    % layout 'default';
    <% if (my $message = flash 'message' ) { %>
        <b><%= $message %></b><br />
    <% } %>
    Welcome <%= session 'name' %>!<br />
    <%= link_to logout => begin %>
        Logout
    <% end %>

Note that you should use a custom C<secret> to make signed cookies really secure.

    app->secret('My secret passphrase here!');

A full featured HTTP 1.1 and WebSocket client is built right in.
Especially in combination with L<Mojo::JSON> and L<Mojo::DOM> this can be a
very powerful tool.

    get '/test' => sub {
        my $self = shift;
        $self->render(
            data => $self->client->get('http://mojolicious.org')->res->body);
    };

WebSocket applications have never been this easy before.

    websocket '/echo' => sub {
        my $self = shift;
        $self->on_message(sub {
            my ($self, $message) = @_;
            $self->send_message("echo: $message");
        });
    };

External templates will be searched by the renderer in a C<templates>
directory.

    # /external
    any '/external' => sub {
        my $self = shift;

        # templates/foo/bar.html.ep
        $self->render('foo/bar');
    };

Static files will be automatically served from the C<DATA> section
(even Base 64 encoded) or a C<public> directory if it exists.

    @@ something.js
    alert('hello!');

    @@ test.txt (base64)
    dGVzdCAxMjMKbGFsYWxh

    % mkdir public
    % mv something.js public/something.js

Testing your application is as easy as creating a C<t> directory and filling
it with normal Perl unit tests.
Some plugins depend on the actual script name, so a test file for the
application C<myapp.pl> should be named C<t/myapp.t>.

    use Test::More tests => 3;
    use Test::Mojo;

    use FindBin;
    $ENV{MOJO_HOME} = "$FindBin::Bin/../";
    require "$ENV{MOJO_HOME}/myapp.pl";

    my $t = Test::Mojo->new;
    $t->get_ok('/')->status_is(200)->content_like(qr/Funky!/);

Run all unit tests with the C<test> command.

    % ./myapp.pl test

To make your tests more noisy and show you all log messages you can also
change the application log level directly in your test files.

    $t->app->log->level('debug');

To disable debug messages later in a production setup you can change the
L<Mojolicious> mode, default will be C<development>.

    % ./myapp.pl --mode production

Log messages will be automatically written to a C<log/$mode.log> file if a
C<log> directory exists.

    % mkdir log

For more control the L<Mojolicious> instance can be accessed directly.

    app->log->level('error');
    app->routes->route('/foo/:bar')->via('get')->to(cb => sub {
        my $self = shift;
        $self->render(text => 'Hello Mojo!');
    });

In case a lite app needs to grow, lite and real L<Mojolicous> applications
can be easily mixed to make the transition process very smooth.

    package MyApp::Foo;
    use base 'Mojolicious::Controller';

    sub index { shift->render(text => 'It works!') }

    package main;
    use Mojolicious::Lite;

    get '/bar' => sub { shift->render(text => 'This too!') };

    app->routes->namespace('MyApp');
    app->routes->route('/foo/:action')->via('get')->to('foo#index');

    app->start;

There is also a helper command to generate a full L<Mojolicious> example that
will let you explore the astonishing similarities between
L<Mojolicious::Lite> and L<Mojolicious> applications.
Both share about 99% of the same code, so almost everything you learned in
this tutorial applies there too. :)

    % mojo generate app

Have fun!

=head1 FUNCTIONS

L<Mojolicious::Lite> implements the following functions.

=head2 C<any>

    my $route = any '/:foo' => sub {...};
    my $route = any [qw/get post/] => '/:foo' => sub {...};

Generate route matching any of the listed HTTP request methods or all.
See also the tutorial above for more argument variations.

=head2 C<app>

    my $app = app;

The L<Mojolicious::Lite> application.

=head2 C<get>

    my $route = get '/:foo' => sub {...};

Generate route matching only C<GET> requests.
See also the tutorial above for more argument variations.

=head2 C<plugin>

    plugin 'something';
    plugin 'something', foo => 23;
    plugin 'something', {foo => 23};
    plugin 'Foo::Bar';
    plugin 'Foo::Bar', foo => 23;
    plugin 'Foo::Bar', {foo => 23};

Load a plugin.

=head2 C<post>

    my $route = post '/:foo' => sub {...};

Generate route matching only C<POST> requests.
See also the tutorial above for more argument variations.

=head2 C<under>

    my $route = under sub {...};
    my $route = under '/:foo';

Generate bridge to which all following routes are automatically appended.
See also the tutorial above for more argument variations.

=head2 C<websocket>

    my $route = websocket '/:foo' => sub {...};

Generate route matching only C<WebSocket> handshakes.
See also the tutorial above for more argument variations.

=head1 ATTRIBUTES

L<Mojolicious::Lite> inherits all attributes from L<Mojolicious>.

=head1 METHODS

L<Mojolicious::Lite> inherits all methods from L<Mojolicious>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
