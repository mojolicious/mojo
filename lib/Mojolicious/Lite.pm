package Mojolicious::Lite;
use Mojo::Base 'Mojolicious';

# Lite apps are modern!
require feature if $] >= 5.010;

# "Since when is the Internet all about robbing people of their privacy?
#  August 6, 1991."
use File::Basename 'dirname';
use File::Spec;

# "It's the future, my parents, my co-workers, my girlfriend,
#  I'll never see any of them ever again... YAHOOO!"
sub import {
  my $class = shift;

  # Lite apps are strict!
  strict->import;
  warnings->import;

  # Lite apps are modern!
  feature->import(':5.10') if $] >= 5.010;

  # Executable
  $ENV{MOJO_EXE} ||= (caller)[1];

  # Home
  local $ENV{MOJO_HOME} =
    File::Spec->catdir(split '/', dirname($ENV{MOJO_EXE}))
    unless $ENV{MOJO_HOME};

  # Initialize app
  my $app = $class->new;

  # Initialize routes
  my $routes = $app->routes;
  $routes->namespace('');

  # Prepare exports
  my $caller = caller;
  no strict 'refs';
  no warnings 'redefine';

  # Default static and template class
  $app->static->default_static_class($caller);
  $app->renderer->default_template_class($caller);

  # Root
  my $root = $routes;

  # Export
  *{"${caller}::new"} = *{"${caller}::app"} = sub {$app};
  *{"${caller}::any"}    = sub { $routes->any(@_) };
  *{"${caller}::del"}    = sub { $routes->del(@_) };
  *{"${caller}::get"}    = sub { $routes->get(@_) };
  *{"${caller}::helper"} = sub { $app->helper(@_) };
  *{"${caller}::hook"}   = sub { $app->hook(@_) };
  *{"${caller}::under"}  = *{"${caller}::ladder"} =
    sub { $routes = $root->under(@_) };
  *{"${caller}::plugin"}    = sub { $app->plugin(@_) };
  *{"${caller}::post"}      = sub { $routes->post(@_) };
  *{"${caller}::put"}       = sub { $routes->put(@_) };
  *{"${caller}::websocket"} = sub { $routes->websocket(@_) };

  # We are most likely the app in a lite environment
  $ENV{MOJO_APP} ||= $app;

  # Shagadelic!
  *{"${caller}::shagadelic"} = sub { $app->start(@_) };
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

L<Mojolicious::Lite> is a micro web framework built around L<Mojolicious>.

=head1 TUTORIAL

A quick example driven introduction to the wonders of L<Mojolicious::Lite>.
Most of what you'll learn here also applies to normal L<Mojolicious>
applications.

=head2 Hello World!

A minimal Hello World application looks like this, L<strict> and L<warnings>
are automatically enabled and a few functions imported when you use
L<Mojolicious::Lite>, turning your script into a full featured web
application.

  #!/usr/bin/env perl

  use Mojolicious::Lite;

  get '/' => sub { shift->render(text => 'Hello World!') };

  app->start;

=head2 Generator

There is also a helper command to generate a small example application.

  % mojo generate lite_app

=head2 Commands

All the normal L<Mojolicious command options|Mojolicious::Commands> are
available from the command line.
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

=head2 Start

The app->start call that starts the L<Mojolicious> command system can be
customized to override normal C<@ARGV> use.

  app->start('cgi');

=head2 Reloading

Your application will automatically reload itself if you set the C<--reload>
option, so you don't have to restart the server after every change.

  % ./myapp.pl daemon --reload
  Server available at http://127.0.0.1:3000.

=head2 Routes

Routes are basically just fancy paths that can contain different kinds of
placeholders.
C<$self> is an instance of L<Mojolicious::Controller> containing both the
HTTP request and response.

  # /foo
  get '/foo' => sub {
    my $self = shift;
    $self->render(text => 'Hello World!');
  };

=head2 GET/POST Parameters

All C<GET> and C<POST> parameters are accessible via C<param>.

  # /foo?user=sri
  get '/foo' => sub {
    my $self = shift;
    my $user = $self->param('user');
    $self->render(text => "Hello $user!");
  };

=head2 Stash

The C<stash> is used to pass data to templates, which can be inlined in the
C<DATA> section.

  # /bar
  get '/bar' => sub {
    my $self = shift;
    $self->stash(one => 23);
    $self->render('baz', two => 24);
  };

  __DATA__

  @@ baz.html.ep
  The magic numbers are <%= $one %> and <%= $two %>.

=head2 HTTP

L<Mojo::Message::Request> and L<Mojo::Message::Response> give you full access
to all HTTP features and information.

  # /agent
  get '/agent' => sub {
    my $self = shift;
    $self->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
    $self->render(text => $self->req->headers->user_agent);
  };

=head2 Route Names

All routes can have a name associated with them, this allows automatic
template detection and back referencing with C<url_for>, C<link_to> and
C<form_for>.
Nameless routes get an automatically generated one assigned that is simply
equal to the route itself without non-word characters.

  # /
  get '/' => 'index';

  # /hello
  get '/hello';

  __DATA__

  @@ index.html.ep
  <%= link_to Hello => 'hello' %>.
  <%= link_to Reload => 'index' %>.

  @@ hello.html.ep
  Hello World!

=head2 Layouts

Templates can have layouts.

  # GET /with_layout
  get '/with_layout' => sub {
    my $self = shift;
    $self->render('with_layout');
  };

  __DATA__

  @@ with_layout.html.ep
  % title 'Green!';
  % layout 'green';
  We've got content!

  @@ layouts/green.html.ep
  <!doctype html><html>
    <head><title><%= title %></title></head>
    <body><%= content %></body>
  </html>

=head2 Blocks

Template blocks can be used like normal Perl functions and are always
delimited by the C<begin> and C<end> keywords.

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
      <%== $link->('http://mojolicio.us', 'Mojolicious') %>
      <%== $link->('http://catalystframework.org', 'Catalyst') %>
    </body>
  </html>

=head2 Captured Content

The C<content_for> helper can be used to pass around blocks of captured
content.

  # GET /captured
  get '/captured' => sub {
    my $self = shift;
    $self->render('captured');
  };

  __DATA__

  @@ captured.html.ep
  % layout 'blue', title => 'Green!';
  <% content_for header => begin %>
    <meta http-equiv="Pragma" content="no-cache">
  <% end %>
  We've got content!
  <% content_for header => begin %>
    <meta http-equiv="Expires" content="-1">
  <% end %>

  @@ layouts/blue.html.ep
  <!doctype html><html>
    <head>
      <title><%= title %></title>
      <%= content_for 'header' %>
    </head>
    <body><%= content %></body>
  </html>

=head2 Helpers

You can also extend L<Mojolicious> with your own helpers, a list of all built
in ones can be found in L<Mojolicious::Plugin::DefaultHelpers> and
L<Mojolicious::Plugin::TagHelpers>.

  # "whois" helper
  helper whois => sub {
    my $self  = shift;
    my $agent = $self->req->headers->user_agent || 'Anonymous';
    my $ip    = $self->tx->remote_address;
    return "$agent ($ip)";
  };

  # GET /secret
  get '/secret' => sub {
    my $self = shift;
    my $user = $self->whois;
    $self->app->log->debug("Request from $user.");
  };

  __DATA__

  @@ secret.html.ep
  We know who you are <%= whois %>.

=head2 Placeholders

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

=head2 Relaxed Placeholders

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

=head2 Wildcard Placeholders

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

=head2 HTTP Methods

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

=head2 Route Constraints

All placeholders get compiled to a regex internally, with regex constraints
this process can be easily customized.

  # /* (digits)
  any '/:foo' => [foo => qr/\d+/] => sub {
    my $self = shift;
    my $foo  = $self->param('foo');
    $self->render(text => "Our :foo placeholder matched $foo");
  };

  # /* (everything else)
  any '/:bar' => [bar => qr/.*/] => sub {
    my $self = shift;
    my $bar  = $self->param('bar');
    $self->render(text => "Our :bar placeholder matched $bar");
  };

Just make sure not to use C<^> and C<$> or capturing groups C<(...)>, because
placeholders become part of a larger regular expression internally,
C<(?:...)> is fine though.

=head2 Optional Placeholders

Routes allow default values to make placeholders optional.

  # /hello/*
  get '/hello/:name' => {name => 'Sebastian'} => sub {
    my $self = shift;
    $self->render('groovy', format => 'txt');
  };

  __DATA__

  @@ groovy.txt.ep
  My name is <%= $name %>.

=head2 A Little Bit Of Everything

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
      title    => 'Welcome!',
      layout   => 'funky',
      groovy   => $groovy
    );
  } => 'test';

  app->start;
  __DATA__

  @@ index.html.ep
  % title 'Groovy!';
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
    <head><title><%= title %></title></head>
    <body><%= content %></body>
  </html>

=head2 Under

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

=head2 Conditions

Conditions such as C<agent> allow even more powerful route constructs.

  # /foo
  get '/foo' => (agent => qr/Firefox/) => sub {
    shift->render(text => 'Congratulations, you are using a cool browser!');
  };

  # /foo
  get '/foo' => (agent => qr/Internet Explorer/) => sub {
    shift->render(text => 'Dude, you really need to upgrade to Firefox!');
  };

=head2 Formats

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

=head2 Sessions

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
    <head><title><%= title %></title></head>
    <body><%= content %></body>
  </html>

  @@ login.html.ep
  % layout 'default';
  % title 'Login';
  <%= form_for login => begin %>
    <% if (param 'name') { %>
      <b>Wrong name or password, please try again.</b><br>
    <% } %>
    Name:<br>
    <%= text_field 'name' %><br>
    Password:<br>
    <%= password_field 'pass' %><br>
    <%= submit_button 'Login' %>
  <% end %>

  @@ index.html.ep
  % layout 'default';
  % title 'Welcome';
  <% if (my $message = flash 'message' ) { %>
    <b><%= $message %></b><br>
  <% } %>
  Welcome <%= session 'name' %>!<br>
  <%= link_to logout => begin %>
    Logout
  <% end %>

=head2 Secret

Note that you should use a custom C<secret> to make signed cookies really
secure.

  app->secret('My secret passphrase here!');

=head2 File Uploads

All files uploaded via C<multipart/form-data> request are automatically
available as L<Mojo::Upload> instances.
And you don't have to worry about memory usage, because all files above
C<250KB> will be automatically streamed into a temporary file.

  use Mojolicious::Lite;

  any '/upload' => sub {
    my $self = shift;
    if (my $example = $self->req->upload('example')) {
      my $size = $example->size;
      my $name = $example->filename;
      $self->render(text => "Thanks for uploading $size byte file $name.");
    }
  };

  app->start;
  __DATA__

  @@ upload.html.ep
  <!doctype html><html>
    <head><title>Upload</title></head>
    <body>
      <%= form_for upload =>
            (method => 'post', enctype => 'multipart/form-data') => begin %>
        <%= file_field 'example' %>
        <%= submit_button 'Upload' %>
      <% end %>
    </body>
  </html>

To protect you from excessively large files there is also a global limit of
C<5MB> by default, which you can tweak with the C<MOJO_MAX_MESSAGE_SIZE>
environment variable.

  # Increase limit to 1GB
  $ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;

=head2 User Agent

With L<Mojo::UserAgent> there's a full featured HTTP 1.1 and WebSocket user
agent built right in.
Especially in combination with L<Mojo::JSON> and L<Mojo::DOM> this can be a
very powerful tool.

  get '/test' => sub {
    my $self = shift;
    $self->render(data => $self->ua->get('http://mojolicio.us')->res->body);
  };

=head2 WebSockets

WebSocket applications have never been this easy before.

  websocket '/echo' => sub {
    my $self = shift;
    $self->on_message(sub {
      my ($self, $message) = @_;
      $self->send_message("echo: $message");
    });
  };

=head2 External Templates

External templates will be searched by the renderer in a C<templates>
directory.

  # /external
  any '/external' => sub {
    my $self = shift;

    # templates/foo/bar.html.ep
    $self->render('foo/bar');
  };

=head2 Static Files

Static files will be automatically served from the C<DATA> section
(even Base 64 encoded) or a C<public> directory if it exists.

  @@ something.js
  alert('hello!');

  @@ test.txt (base64)
  dGVzdCAxMjMKbGFsYWxh

  % mkdir public
  % mv something.js public/something.js

=head2 Testing

Testing your application is as easy as creating a C<t> directory and filling
it with normal Perl unit tests.

  use Test::More tests => 3;
  use Test::Mojo;

  use FindBin;
  require "$FindBin::Bin/../myapp.pl";

  my $t = Test::Mojo->new;
  $t->get_ok('/')->status_is(200)->content_like(qr/Funky!/);

Run all unit tests with the C<test> command.

  % ./myapp.pl test

To make your tests more noisy and show you all log messages you can also
change the application log level directly in your test files.

  $t->app->log->level('debug');

=head2 Mode

To disable debug messages later in a production setup you can change the
L<Mojolicious> mode, default will be C<development>.

  % ./myapp.pl --mode production

=head2 Logging

L<Mojo::Log> messages will be automatically written to a C<log/$mode.log>
file if a C<log> directory exists.

  % mkdir log

For more control the L<Mojolicious> instance can be accessed directly.

  app->log->level('error');
  app->routes->route('/foo/:bar')->via('get')->to(cb => sub {
    my $self = shift;
    $self->app->log->debug('Got a request for "Hello Mojo!".');
    $self->render(text => 'Hello Mojo!');
  });

=head2 Growing

In case a lite app needs to grow, lite and real L<Mojolicious> applications
can be easily mixed to make the transition process very smooth.

  package MyApp::Foo;
  use Mojo::Base 'Mojolicious::Controller';

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

=head2 More

You can continue with L<Mojolicious::Guides> now, and don't forget to have
fun!

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

=head2 C<del>

  my $route = del '/:foo' => sub {...};

Generate route matching only C<DELETE> requests.
See also the tutorial above for more argument variations.

=head2 C<get>

  my $route = get '/:foo' => sub {...};

Generate route matching only C<GET> requests.
See also the tutorial above for more argument variations.

=head2 C<helper>

  helper foo => sub {...};

Add a new helper that will be available as a method of the controller object
and the application object, as well as a function in C<ep> templates.

  # Helper
  helper add => sub { $_[1] + $_[2] };

  # Controller/Application
  my $result = $self->add(2, 3);

  # Template
  <%= add 2, 3 %>

Note that this function is EXPERIMENTAL and might change without warning!

=head2 C<hook>

  hook after_dispatch => sub {...};

Add hooks to named events, see L<Mojolicious> for a list of all available
events.
Note that this function is EXPERIMENTAL and might change without warning!

=head2 C<plugin>

  plugin 'something';
  plugin 'something', foo => 23;
  plugin 'something', {foo => 23};
  plugin 'Foo::Bar';
  plugin 'Foo::Bar', foo => 23;
  plugin 'Foo::Bar', {foo => 23};

Load plugins, see L<Mojolicious> for a list of all included example plugins.

=head2 C<post>

  my $route = post '/:foo' => sub {...};

Generate route matching only C<POST> requests.
See also the tutorial above for more argument variations.

=head2 C<put>

  my $route = put '/:foo' => sub {...};

Generate route matching only C<PUT> requests.
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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
