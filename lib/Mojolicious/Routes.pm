package Mojolicious::Routes;
use Mojo::Base 'Mojolicious::Routes::Route';

use List::Util 'first';
use Mojo::Cache;
use Mojo::Loader;
use Mojo::Util 'camelize';
use Mojolicious::Routes::Match;
use Scalar::Util 'weaken';

has base_classes => sub { [qw(Mojolicious::Controller Mojo)] };
has cache        => sub { Mojo::Cache->new };
has [qw(conditions shortcuts)] => sub { {} };
has hidden => sub { [qw(attr has new)] };
has 'namespace';

sub add_condition {
  my ($self, $name, $cb) = @_;
  $self->conditions->{$name} = $cb;
  return $self;
}

sub add_shortcut {
  my ($self, $name, $cb) = @_;
  $self->shortcuts->{$name} = $cb;
  return $self;
}

# "Hey. What kind of party is this? There's no booze and only one hooker."
sub auto_render {
  my ($self, $c) = @_;
  my $stash = $c->stash;
  return if $stash->{'mojo.rendered'} || $c->tx->is_websocket;
  $c->render or ($stash->{'mojo.routed'} or $c->render_not_found);
}

sub dispatch {
  my ($self, $c) = @_;

  # Prepare path
  my $req  = $c->req;
  my $path = $c->stash->{path};
  if (defined $path) { $path = "/$path" if $path !~ m!^/! }
  else               { $path = $req->url->path->to_abs_string }

  # Prepare match
  my $method = $req->method;
  my $websocket = $c->tx->is_websocket ? 1 : 0;
  my $m = Mojolicious::Routes::Match->new($method => $path, $websocket);
  $c->match($m);

  # Check cache
  my $cache = $self->cache;
  if ($cache && (my $cached = $cache->get("$method:$path:$websocket"))) {
    $m->root($self)->endpoint($cached->{endpoint});
    $m->stack($cached->{stack})->captures($cached->{captures});
  }

  # Check routes
  else {
    $m->match($self, $c);

    # Cache routes without conditions
    if ($cache && (my $endpoint = $m->endpoint)) {
      $cache->set(
        "$method:$path:$websocket" => {
          endpoint => $endpoint,
          stack    => $m->stack,
          captures => $m->captures
        }
      ) unless $endpoint->has_conditions;
    }
  }

  # No match
  return unless $m && @{$m->stack};

  # Dispatch
  return if $self->_walk($c);
  $self->auto_render($c);
  return 1;
}

sub hide { push @{shift->hidden}, @_ }

sub route {
  shift->add_child(Mojolicious::Routes::Route->new(@_))->children->[-1];
}

sub _callback {
  my ($self, $c, $field, $staging) = @_;
  $c->stash->{'mojo.routed'}++;
  $c->app->log->debug('Routing to a callback.');
  my $continue = $field->{cb}->($c);
  return !$staging || $continue ? 1 : undef;
}

sub _class {
  my ($self, $field, $c) = @_;

  # Namespace and class
  my $namespace = $field->{namespace};
  my $class = camelize $field->{controller} || '';
  return unless $class || $namespace;
  $class = length $class ? "${namespace}::$class" : $namespace
    if length($namespace //= $self->namespace);

  # Check if it looks like a class
  return $class =~ /^[a-zA-Z0-9_:]+$/ ? $class : undef;
}

sub _controller {
  my ($self, $c, $field, $staging) = @_;

  # Load and instantiate controller/application
  return 1 unless my $app = $field->{app} || $self->_class($field, $c);
  return unless $self->_load($c, $app);
  $app = $app->new($c) unless ref $app;

  # Application
  my $continue;
  my $class = ref $app;
  if (my $sub = $app->can('handler')) {
    $c->app->log->debug(qq{Routing to application "$class".});

    # Try to connect routes
    if (my $sub = $app->can('routes')) {
      my $r = $app->$sub;
      weaken $r->parent($c->match->endpoint)->{parent} unless $r->parent;
    }
    $app->$sub($c);
  }

  # Action
  elsif (my $method = $self->_method($field, $c)) {
    my $log = $c->app->log;
    $log->debug(qq{Routing to controller "$class" and action "$method".});

    # Try to call action
    my $stash = $c->stash;
    if (my $sub = $app->can($method)) {
      $stash->{'mojo.routed'}++ unless $staging;
      $continue = $app->$sub;
    }

    # Action not found
    else { $log->debug('Action not found in controller.') }
  }

  return !$staging || $continue ? 1 : undef;
}

sub _load {
  my ($self, $c, $app) = @_;

  # Load unless already loaded or application
  return 1 if $self->{loaded}{$app} || ref $app;
  if (my $e = Mojo::Loader->new->load($app)) {

    # Doesn't exist
    $c->app->log->debug(qq{Controller "$app" does not exist.}) and return
      unless ref $e;

    # Error
    die $e;
  }

  # Check base classes
  $c->app->log->debug(qq{Class "$app" is not a controller.}) and return
    unless first { $app->isa($_) } @{$self->base_classes};
  return ++$self->{loaded}{$app};
}

sub _method {
  my ($self, $field, $c) = @_;

  # Hidden
  $self->{hiding} = {map { $_ => 1 } @{$self->hidden}} unless $self->{hiding};
  return unless my $method = $field->{action};
  $c->app->log->debug(qq{Action "$method" is not allowed.}) and return
    if $self->{hiding}{$method} || index($method, '_') == 0;

  # Invalid
  $c->app->log->debug(qq{Action "$method" is invalid.}) and return
    unless $method =~ /^[a-zA-Z0-9_:]+$/;

  return $method;
}

sub _walk {
  my ($self, $c) = @_;

  # Walk the stack
  my $stack   = $c->match->stack;
  my $stash   = $c->stash;
  my $staging = @$stack;
  $stash->{'mojo.captures'} ||= {};
  for my $field (@$stack) {
    $staging--;

    # Merge in captures
    my @keys = keys %$field;
    @{$stash}{@keys} = @{$stash->{'mojo.captures'}}{@keys} = values %$field;

    # Dispatch
    my $continue
      = $field->{cb}
      ? $self->_callback($c, $field, $staging)
      : $self->_controller($c, $field, $staging);

    # Break the chain
    return 1 if $staging && !$continue;
  }

  return;
}

1;

=head1 NAME

Mojolicious::Routes - Always find your destination with routes!

=head1 SYNOPSIS

  use Mojolicious::Routes;

  # New routes tree
  my $r = Mojolicious::Routes->new;

  # Normal route matching "/articles" with parameters "controller" and
  # "action"
  $r->route('/articles')->to(controller => 'article', action => 'list');

  # Route with a placeholder matching everything but "/" and "."
  $r->route('/:controller')->to(action => 'list');

  # Route with a placeholder and regex constraint
  $r->route('/articles/:id', id => qr/\d+/)
    ->to(controller => 'article', action => 'view');

  # Route with an optional parameter "year"
  $r->route('/archive/:year')
    ->to(controller => 'archive', action => 'list', year => undef);

  # Nested route for two actions sharing the same "controller" parameter
  my $books = $r->route('/books/:id')->to(controller => 'book');
  $books->route('/edit')->to(action => 'edit');
  $books->route('/delete')->to(action => 'delete');

  # Bridges can be used to chain multiple routes
  $r->bridge->to(controller => 'foo', action =>'auth')
    ->route('/blog')->to(action => 'list');

  # Simplified Mojolicious::Lite style route generation is also possible
  $r->get('/')->to(controller => 'blog', action => 'welcome');
  my $blog = $r->under('/blog');
  $blog->post('/list')->to('blog#list');
  $blog->get(sub { shift->render(text => 'Go away!') });

=head1 DESCRIPTION

L<Mojolicious::Routes> is the core of the L<Mojolicious> web framework.

See L<Mojolicious::Guides::Routing> for more.

=head1 ATTRIBUTES

L<Mojolicious::Routes> inherits all attributes from
L<Mojolicious::Routes::Route> and implements the following new ones.

=head2 C<base_classes>

  my $classes = $r->base_classes;
  $r          = $r->base_classes(['MyApp::Controller']);

Base classes used to identify controllers, defaults to
L<Mojolicious::Controller> and L<Mojo>.

=head2 C<cache>

  my $cache = $r->cache;
  $r        = $r->cache(Mojo::Cache->new);

Routing cache, defaults to a L<Mojo::Cache> object.

  # Disable caching
  $r->cache(0);

=head2 C<conditions>

  my $conditions = $r->conditions;
  $r             = $r->conditions({foo => sub {...}});

Contains all available conditions.

=head2 C<hidden>

  my $hidden = $r->hidden;
  $r         = $r->hidden([qw(attr has new)]);

Controller methods and attributes that are hidden from routes, defaults to
C<attr>, C<has> and C<new>.

=head2 C<namespace>

  my $namespace = $r->namespace;
  $r            = $r->namespace('Foo::Bar::Controller');

Namespace used by C<dispatch> to search for controllers.

=head2 C<shortcuts>

  my $shortcuts = $r->shortcuts;
  $r            = $r->shortcuts({foo => sub {...}});

Contains all available shortcuts.

=head1 METHODS

L<Mojolicious::Routes> inherits all methods from
L<Mojolicious::Routes::Route> and implements the following ones.

=head2 C<add_condition>

  $r = $r->add_condition(foo => sub {...});

Add a new condition.

=head2 C<add_shortcut>

  $r = $r->add_shortcut(foo => sub {...});

Add a new shortcut.

=head2 C<auto_render>

  $r->auto_render(Mojolicious::Controller->new);

Automatic rendering.

=head2 C<dispatch>

  my $success = $r->dispatch(Mojolicious::Controller->new);

Match routes with L<Mojolicious::Routes::Match> and dispatch.

=head2 C<hide>

  $r = $r->hide(qw(foo bar));

Hide controller methods and attributes from routes.

=head2 C<route>

  my $route = $r->route;
  my $route = $r->route('/:action');
  my $route = $r->route('/:action', action => qr/\w+/);
  my $route = $r->route(format => 0);

Generate route matching all HTTP request methods.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
