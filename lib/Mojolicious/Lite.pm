package Mojolicious::Lite;
use Mojo::Base 'Mojolicious';

# "Bender: Bite my shiny metal ass!"
use Mojo::File qw(path);
use Mojo::UserAgent::Server;
use Mojo::Util qw(monkey_patch);

sub import {

  # Remember executable for later
  $ENV{MOJO_EXE} ||= (caller)[1];

  # Reuse home directory if possible
  local $ENV{MOJO_HOME} = path($ENV{MOJO_EXE})->dirname->to_string unless $ENV{MOJO_HOME};

  # Initialize application class
  my $caller = caller;
  no strict 'refs';
  push @{"${caller}::ISA"}, 'Mojolicious';

  # Generate moniker based on filename
  my $moniker = path($ENV{MOJO_EXE})->basename('.pl', '.pm', '.t');
  my $app     = shift->new(moniker => $moniker);

  # Initialize routes without namespaces
  my $routes = $app->routes->namespaces([]);
  $app->static->classes->[0] = $app->renderer->classes->[0] = $caller;

  # The Mojolicious::Lite DSL
  my $root = $routes;
  for my $name (qw(any get options patch post put websocket)) {
    monkey_patch $caller, $name, sub { $routes->$name(@_) }
  }
  monkey_patch($caller, $_, sub {$app}) for qw(new app);
  monkey_patch $caller, del   => sub { $routes->delete(@_) };
  monkey_patch $caller, group => sub (&) {
    (my $old, $root) = ($root, $routes);
    shift->();
    ($routes, $root) = ($root, $old);
  };
  monkey_patch $caller,
    helper => sub { $app->helper(@_) },
    hook   => sub { $app->hook(@_) },
    plugin => sub { $app->plugin(@_) },
    under  => sub { $routes = $root->under(@_) };

  # Make sure there's a default application for testing
  Mojo::UserAgent::Server->app($app) unless Mojo::UserAgent::Server->app;

  # Lite apps are strict!
  unshift @_, 'Mojo::Base', '-strict';
  goto &Mojo::Base::import;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Lite - Micro real-time web framework

=head1 SYNOPSIS

  # Automatically enables "strict", "warnings", "utf8" and Perl 5.16 features
  use Mojolicious::Lite -signatures;

  # Route with placeholder
  get '/:foo' => sub ($c) {
    my $foo = $c->param('foo');
    $c->render(text => "Hello from $foo.");
  };

  # Start the Mojolicious command system
  app->start;

=head1 DESCRIPTION

L<Mojolicious::Lite> is a tiny domain specific language built around L<Mojolicious>, made up of only about a dozen Perl
functions.

On Perl 5.20+ you can also use a C<-signatures> flag to enable support for L<subroutine
signatures|perlsub/"Signatures">.

  use Mojolicious::Lite -signatures;

  get '/:foo' => sub ($c) {
    my $foo = $c->param('foo');
    $c->render(text => "Hello from $foo.");
  };

  app->start;

See L<Mojolicious::Guides::Tutorial> for more!

=head1 GROWING

While L<Mojolicious::Guides::Growing> will give you a detailed introduction to growing a L<Mojolicious::Lite> prototype
into a well-structured L<Mojolicious> application, here we have collected a few snippets that illustrate very well just
how similar both of them are.

=head2 Routes

The functions L</"get">, L</"post"> and friends all have equivalent methods.

  # Mojolicious::Lite
  get '/foo' => sub ($c) {
    $c->render(text => 'Hello World!');
  };

  # Mojolicious
  sub startup ($self) {
  
    my $routes = $self->routes;
    $routes->get('/foo' => sub ($c) {
      $c->render(text => 'Hello World!');
    });
  }

=head2 Application

The application object you can access with the function L</"app"> is the first argument passed to the C<startup>
method.

  # Mojolicious::Lite
  app->max_request_size(16777216);

  # Mojolicious
  sub startup ($self) {
    $self->max_request_size(16777216);
  }

=head2 Plugins

Instead of the L</"plugin"> function you just use the method L<Mojolicious/"plugin">.

  # Mojolicious::Lite
  plugin 'Config';

  # Mojolicious
  sub startup ($self) {
    $self->plugin('Config');
  }

=head2 Helpers

Similar to plugins, instead of the L</"helper"> function you just use the method L<Mojolicious/"helper">.

  # Mojolicious::Lite
  helper two => sub ($c) {
    return 1 + 1;
  };

  # Mojolicious
  sub startup ($self) {
    $self->helper(two => sub ($c) {
      return 1 + 1;
    });
  }

=head2 Under

Instead of sequential function calls, we can use methods to build a tree with nested routes, that much better
illustrates how routes work internally.

  # Mojolicious::Lite
  under '/foo';
  get '/bar' => sub ($c) {...};

  # Mojolicious
  sub startup ($self) {

    my $routes = $self->routes;
    my $foo = $routes->under('/foo');
    $foo->get('/bar' => sub ($c) {...});
  }

=head1 FUNCTIONS

L<Mojolicious::Lite> implements the following functions, which are automatically exported.

=head2 any

  my $route = any '/:foo' => sub ($c) {...};
  my $route = any '/:foo' => sub ($c) {...} => 'name';
  my $route = any '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = any '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = any ['GET', 'POST'] => '/:foo' => sub ($c) {...};
  my $route = any ['GET', 'POST'] => '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = any ['GET', 'POST'] => '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"any">, matching any of the listed HTTP request methods or all. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 app

  my $app = app;

Returns the L<Mojolicious::Lite> application object, which is a subclass of L<Mojolicious>.

  # Use all the available attributes and methods
  app->log->level('error');
  app->defaults(foo => 'bar');

=head2 del

  my $route = del '/:foo' => sub ($c) {...};
  my $route = del '/:foo' => sub ($c) {...} => 'name';
  my $route = del '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = del '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = del '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"delete">, matching only C<DELETE> requests. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 get

  my $route = get '/:foo' => sub ($c) {...};
  my $route = get '/:foo' => sub ($c) {...} => 'name';
  my $route = get '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = get '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = get '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"get">, matching only C<GET> requests. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 group

  group {...};

Start a new route group.

=head2 helper

  helper foo => sub ($c, @args) {...};

Add a new helper with L<Mojolicious/"helper">.

=head2 hook

  hook after_dispatch => sub ($c) {...};

Share code with L<Mojolicious/"hook">.

=head2 options

  my $route = options '/:foo' => sub ($c) {...};
  my $route = options '/:foo' => sub ($c) {...} => 'name';
  my $route = options '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = options '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = options '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"options">, matching only C<OPTIONS> requests. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 patch

  my $route = patch '/:foo' => sub ($c) {...};
  my $route = patch '/:foo' => sub ($c) {...} => 'name';
  my $route = patch '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = patch '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = patch '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"patch">, matching only C<PATCH> requests. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 plugin

  plugin SomePlugin => {foo => 23};

Load a plugin with L<Mojolicious/"plugin">.

=head2 post

  my $route = post '/:foo' => sub ($c) {...};
  my $route = post '/:foo' => sub ($c) {...} => 'name';
  my $route = post '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = post '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = post '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"post">, matching only C<POST> requests. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 put

  my $route = put '/:foo' => sub ($c) {...};
  my $route = put '/:foo' => sub ($c) {...} => 'name';
  my $route = put '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = put '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = put '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"put">, matching only C<PUT> requests. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 under

  my $route = under sub ($c) {...};
  my $route = under '/:foo' => sub ($c) {...};
  my $route = under '/:foo' => {foo => 'bar'};
  my $route = under '/:foo' => [foo => qr/\w+/];
  my $route = under '/:foo' => (agent => qr/Firefox/);
  my $route = under [format => 0];

Generate nested route with L<Mojolicious::Routes::Route/"under">, to which all following routes are automatically
appended. See L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head2 websocket

  my $route = websocket '/:foo' => sub ($c) {...};
  my $route = websocket '/:foo' => sub ($c) {...} => 'name';
  my $route = websocket '/:foo' => {foo => 'bar'} => sub ($c) {...};
  my $route = websocket '/:foo' => [foo => qr/\w+/] => sub ($c) {...};
  my $route = websocket '/:foo' => (agent => qr/Firefox/) => sub ($c) {...};

Generate route with L<Mojolicious::Routes::Route/"websocket">, matching only WebSocket handshakes. See
L<Mojolicious::Guides::Tutorial> and L<Mojolicious::Guides::Routing> for more information.

=head1 ATTRIBUTES

L<Mojolicious::Lite> inherits all attributes from L<Mojolicious>.

=head1 METHODS

L<Mojolicious::Lite> inherits all methods from L<Mojolicious>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
