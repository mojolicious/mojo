package Mojolicious::Routes;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Cache;
use Mojo::Loader;
use Mojo::Util 'camelize';
use Mojolicious::Routes::Match;
use Mojolicious::Routes::Pattern;
use Scalar::Util qw/blessed weaken/;

has [qw/block inline parent partial namespace/];
has cache => sub { Mojo::Cache->new };
has [qw/children conditions/] => sub { [] };
has controller_base_class => 'Mojolicious::Controller';
has [qw/dictionary shortcuts/] => sub { {} };
has hidden  => sub { [qw/new attr has/] };
has pattern => sub { Mojolicious::Routes::Pattern->new };

# "Yet thanks to my trusty safety sphere,
#  I sublibed with only tribial brain dablage."
sub AUTOLOAD {
  my $self = shift;

  # Method
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;
  croak qq/Undefined subroutine &${package}::$method called/
    unless blessed $self && $self->isa(__PACKAGE__);

  # Call shortcut
  croak qq/Can't locate object method "$method" via package "$package"/
    unless my $shortcut = $self->shortcuts->{$method};
  return $self->$shortcut(@_);
}

sub DESTROY { }

sub new { shift->SUPER::new->parse(@_) }

sub add_child {
  my ($self, $route) = @_;
  weaken $route->parent($self)->{parent};
  $route->shortcuts($self->shortcuts);
  push @{$self->children}, $route;
  return $self;
}

sub add_condition {
  my ($self, $name, $cb) = @_;
  $self->dictionary->{$name} = $cb;
  return $self;
}

sub add_shortcut {
  my ($self, $name, $cb) = @_;
  $self->shortcuts->{$name} = $cb;
  return $self;
}

sub any { shift->_generate_route(ref $_[0] eq 'ARRAY' ? shift : [], @_) }

# "Hey. What kind of party is this? There's no booze and only one hooker."
sub auto_render {
  my ($self, $c) = @_;
  my $stash = $c->stash;
  return if $stash->{'mojo.rendered'} || $c->tx->is_websocket;
  $c->render or ($stash->{'mojo.routed'} or $c->render_not_found);
}

sub bridge { shift->route(@_)->inline(1) }

sub delete { shift->_generate_route(delete => @_) }

sub detour { shift->partial(1)->to(@_) }

sub dispatch {
  my ($self, $c) = @_;

  # Prepare path
  my $req  = $c->req;
  my $path = $c->stash->{path};
  if (defined $path) { $path = "/$path" if $path !~ m#^/# }
  else               { $path = $req->url->path->to_abs_string }

  # Prepare match
  my $method = $req->method;
  my $websocket = $c->tx->is_websocket ? 1 : 0;
  my $m = Mojolicious::Routes::Match->new($method => $path, $websocket);
  $c->match($m);

  # Check cache
  my $cache = $self->cache;
  if ($cache && (my $cached = $cache->get("$method:$path:$websocket"))) {
    $m->root($self);
    $m->stack($cached->{stack});
    $m->captures($cached->{captures});
    $m->endpoint($cached->{endpoint});
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
  return if $self->_walk_stack($c);
  $self->auto_render($c);
  return 1;
}

sub get { shift->_generate_route(get => @_) }

sub has_conditions {
  my $self = shift;
  return 1 if @{$self->conditions};
  return unless my $parent = $self->parent;
  return $parent->has_conditions;
}

sub has_custom_name { shift->{custom} }

sub has_websocket {
  my $self = shift;
  return 1 if $self->is_websocket;
  return unless my $parent = $self->parent;
  return $parent->is_websocket;
}

sub hide { push @{shift->hidden}, @_ }

sub is_endpoint {
  my $self = shift;
  return   if $self->inline;
  return 1 if $self->block;
  return !@{$self->children};
}

sub is_websocket { shift->{websocket} }

sub name {
  my $self = shift;

  # Custom names have precedence
  if (@_) {
    if (defined(my $name = shift)) {
      $self->{name}   = $name;
      $self->{custom} = 1;
    }
    return $self;
  }

  return $self->{name};
}

sub over {
  my $self = shift;
  my $conditions = ref $_[0] eq 'ARRAY' ? $_[0] : [@_];
  return $self unless @$conditions;

  # Routes with conditions can't be cached
  push @{$self->conditions}, @$conditions;
  my $root = my $parent = $self;
  while ($parent = $parent->parent) { $root = $parent }
  $root->cache(0);

  return $self;
}

sub parse {
  my $self = shift;
  my $name = $self->pattern->parse(@_)->pattern // '';
  $name =~ s/\W+//g;
  $self->{name} = $name;
  return $self;
}

sub patch { shift->_generate_route(patch => @_) }
sub post  { shift->_generate_route(post  => @_) }
sub put   { shift->_generate_route(put   => @_) }

sub render {
  my ($self, $path, $values) = @_;

  # Path prefix
  my $prefix = $self->pattern->render($values);
  $path = $prefix . $path unless $prefix eq '/';

  # Make sure there is always a root
  $path = '/' if !$path && !$self->parent;

  # Format
  if ((my $format = $values->{format}) && !$self->parent) {
    $path .= ".$format" unless $path =~ m#\.[^/]+$#;
  }

  # Parent
  $path = $self->parent->render($path, $values) if $self->parent;

  return $path;
}

sub route {
  my $self  = shift;
  my $route = $self->new(@_);
  $self->add_child($route);
  return $route;
}

sub to {
  my $self = shift;
  return $self unless @_;

  # Single argument
  my ($shortcut, $defaults);
  if (@_ == 1) {

    # Hash
    $defaults = shift if ref $_[0] eq 'HASH';
    $shortcut = shift if $_[0];
  }

  # Multiple arguments
  else {

    # Odd
    if (@_ % 2) {
      $shortcut = shift;
      $defaults = {@_};
    }

    # Even
    else {

      # Shortcut and defaults
      if (ref $_[1] eq 'HASH') { ($shortcut, $defaults) = (shift, shift) }

      # Just defaults
      else { $defaults = {@_} }
    }
  }

  # Shortcut
  if ($shortcut) {

    # App
    if (ref $shortcut || $shortcut =~ /^[\w\:]+$/) {
      $defaults->{app} = $shortcut;
    }

    # Controller and action
    elsif ($shortcut =~ /^([\w\-]+)?\#(\w+)?$/) {
      $defaults->{controller} = $1 if defined $1;
      $defaults->{action}     = $2 if defined $2;
    }
  }

  # Defaults
  my $pattern = $self->pattern;
  my $old     = $pattern->defaults;
  $pattern->defaults({%$old, %$defaults}) if $defaults;

  return $self;
}

sub to_string {
  my $self = shift;
  my $pattern = $self->parent ? $self->parent->to_string : '';
  $pattern .= $self->pattern->pattern if $self->pattern->pattern;
  return $pattern;
}

sub under { shift->_generate_route(under => @_) }

sub via {
  my $self = shift;

  # Restrict methods
  if (@_) {
    my $methods = [map { lc $_ } @{ref $_[0] ? $_[0] : [@_]}];
    $self->{via} = $methods if @$methods;
    return $self;
  }

  return $self->{via};
}

sub waypoint { shift->route(@_)->block(1) }

sub websocket {
  my $self  = shift;
  my $route = $self->get(@_);
  $route->{websocket} = 1;
  return $route;
}

sub _dispatch_callback {
  my ($self, $c, $field, $staging) = @_;
  $c->stash->{'mojo.routed'}++;
  $c->app->log->debug(qq/Routing to a callback./);
  my $continue = $field->{cb}->($c);
  return !$staging || $continue ? 1 : undef;
}

sub _dispatch_controller {
  my ($self, $c, $field, $staging) = @_;

  # Class and method
  return 1
    unless my $app = $field->{app} || $self->_generate_class($field, $c);
  my $method = $self->_generate_method($field, $c);
  my $target = (ref $app || $app) . ($method ? "->$method" : '');
  $c->app->log->debug(qq/Routing to "$target"./);

  # Controller or application
  return unless $self->_load_class($c, $app);
  $app = $app->new($c) unless ref $app;

  # Action
  my $continue;
  if ($method) {

    # Call action
    my $stash = $c->stash;
    if (my $code = $app->can($method)) {
      $stash->{'mojo.routed'}++ unless $staging;
      $continue = $app->$code;
    }

    # Render
    else {
      $c->app->log->debug(
        qq/Action "$target" not found, assuming template without action./);
    }
  }

  # Application
  else {
    if (my $code = $app->can('routes')) {
      my $r = $app->$code;
      weaken $r->parent($c->match->endpoint)->{parent} unless $r->parent;
    }
    $app->handler($c);
  }

  return !$staging || $continue ? 1 : undef;
}

sub _generate_class {
  my ($self, $field, $c) = @_;

  # DEPRECATED in Leaf Fluttering In Wind!
  warn "The class stash value is DEPRECATED in favor of controller!\n"
    if $field->{class};
  my $class = camelize $field->{class} || $field->{controller} || '';

  # Namespace
  my $namespace = $field->{namespace};
  return unless $class || $namespace;
  $namespace //= $self->namespace;
  $class = length $class ? "${namespace}::$class" : $namespace
    if length $namespace;

  # Invalid
  return unless $class =~ /^[a-zA-Z0-9_:]+$/;

  return $class;
}

sub _generate_method {
  my ($self, $field, $c) = @_;

  # Prepare hidden
  unless ($self->{hiding}) { $self->{hiding}->{$_}++ for @{$self->hidden} }

  # DEPRECATED in Leaf Fluttering In Wind!
  warn "The method stash value is DEPRECATED in favor of action!\n"
    if $field->{method};
  return unless my $method = $field->{method} || $field->{action};

  # Hidden
  $c->app->log->debug(qq/Action "$method" is not allowed./) and return
    if $self->{hiding}->{$method} || index($method, '_') == 0;

  # Invalid
  $c->app->log->debug(qq/Action "$method" is invalid./) and return
    unless $method =~ /^[a-zA-Z0-9_:]+$/;

  return $method;
}

sub _generate_route {
  my ($self, $methods, @args) = @_;

  # Route information
  my ($cb, $constraints, $defaults, $name, $pattern);
  my $conditions = [];
  while (defined(my $arg = shift @args)) {

    # First scalar is the pattern
    if (!ref $arg && !$pattern) { $pattern = $arg }

    # Scalar
    elsif (!ref $arg && @args) { push @$conditions, $arg, shift @args }

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
  $defaults    ||= {};
  $defaults->{cb} = $cb if $cb;

  # Create bridge
  return $self->bridge($pattern, {@$constraints})->over($conditions)
    ->to($defaults)->name($name)
    if !ref $methods && $methods eq 'under';

  # Create route
  return $self->route($pattern, {@$constraints})->over($conditions)
    ->via($methods)->to($defaults)->name($name);
}

sub _load_class {
  my ($self, $c, $app) = @_;

  # Load unless already loaded or application
  return 1 if $self->{loaded}->{$app} || ref $app;
  if (my $e = Mojo::Loader->load($app)) {

    # Doesn't exist
    $c->app->log->debug("$app does not exist, maybe a typo?") and return
      unless ref $e;

    # Error
    die $e;
  }

  # Check for controller and application
  return unless $app->isa($self->controller_base_class) || $app->isa('Mojo');
  return ++$self->{loaded}->{$app};
}

sub _walk_stack {
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
    my $continue =
        $field->{cb}
      ? $self->_dispatch_callback($c, $field, $staging)
      : $self->_dispatch_controller($c, $field, $staging);

    # Break the chain
    return 1 if $staging && !$continue;
  }

  return;
}

1;
__END__

=head1 NAME

Mojolicious::Routes - Always find your destination with routes

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

  # Waypoints are similar to bridges and nested routes but can also match
  # if they are not the actual endpoint of the whole route
  my $b = $r->waypoint('/books')->to(controller => 'books', action => 'list');
  $b->route('/:id', id => qr/\d+/)->to(action => 'view');

  # Simplified Mojolicious::Lite style route generation is also possible
  $r->get('/')->to(controller => 'blog', action => 'welcome');
  my $blog = $r->under('/blog');
  $blog->post('/list')->to('blog#list');
  $blog->get(sub { shift->render(text => 'Go away!') });

=head1 DESCRIPTION

L<Mojolicious::Routes> is the core of the L<Mojolicious> web framework. See
L<Mojolicious::Guides::Routing> for more.

=head1 ATTRIBUTES

L<Mojolicious::Routes> implements the following attributes.

=head2 C<block>

  my $block = $r->block;
  $r        = $r->block(1);

Allow this route to match even if it's not an endpoint, used for waypoints.

=head2 C<children>

  my $children = $r->children;
  $r           = $r->children([Mojolicious::Routes->new]);

The children of this routes object, used for nesting routes.

=head2 C<cache>

  my $cache = $r->cache;
  $r        = $r->cache(Mojo::Cache->new);

Routing cache, defaults to a L<Mojo::Cache> object.

=head2 C<conditions>

  my $conditions  = $r->conditions;
  $r              = $r->conditions([foo => qr/\w+/]);

Contains condition parameters for this route, used for C<over>.

=head2 C<controller_base_class>

  my $base = $r->controller_base_class;
  $r       = $r->controller_base_class('Mojolicious::Controller');

Base class used to identify controllers, defaults to
L<Mojolicious::Controller>.

=head2 C<dictionary>

  my $dictionary = $r->dictionary;
  $r             = $r->dictionary({foo => sub {...}});

Contains all available conditions for this route.

=head2 C<hidden>

  my $hidden = $r->hidden;
  $r         = $r->hidden([qw/new attr tx render req res stash/]);

Controller methods and attributes that are hidden from routes.

=head2 C<inline>

  my $inline = $r->inline;
  $r         = $r->inline(1);

Allow C<bridge> semantics for this route.

=head2 C<namespace>

  my $namespace = $r->namespace;
  $r            = $r->namespace('Foo::Bar::Controller');

Namespace used by C<dispatch> to search for controllers.

=head2 C<parent>

  my $parent = $r->parent;
  $r         = $r->parent(Mojolicious::Routes->new);

The parent of this route, used for nesting routes.

=head2 C<partial>

  my $partial = $r->partial;
  $r          = $r->partial(1);

Route has no specific end, remaining characters will be captured in C<path>.

=head2 C<pattern>

  my $pattern = $r->pattern;
  $r          = $r->pattern(Mojolicious::Routes::Pattern->new);

Pattern for this route, defaults to a L<Mojolicious::Routes::Pattern> object.

=head2 C<shortcuts>

  my $shortcuts = $r->shortcuts;
  $r            = $r->shortcuts({foo => sub {...}});

Contains all additional route shortcuts available for this route.

=head1 METHODS

L<Mojolicious::Routes> inherits all methods from L<Mojo::Base> and implements
the following ones.

=head2 C<new>

  my $r = Mojolicious::Routes->new;
  my $r = Mojolicious::Routes->new('/:controller/:action');

Construct a new route object.

=head2 C<add_child>

  $r = $r->add_child(Mojolicious::Route->new);

Add a new child to this route.

=head2 C<add_condition>

  $r = $r->add_condition(foo => sub {...});

Add a new condition for this route.

=head2 C<add_shortcut>

  $r = $r->add_shortcut(foo => sub {...});

Add a new shortcut for this route.

=head2 C<any>

  my $route = $route->any('/:foo' => sub {...});
  my $route = $route->any([qw/get post/] => '/:foo' => sub {...});

Generate route matching any of the listed HTTP request methods or all. See
also the L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<auto_render>

  $r->auto_render(Mojolicious::Controller->new);

Automatic rendering.

=head2 C<bridge>

  my $bridge = $r->bridge;
  my $bridge = $r->bridge('/:controller/:action');

Add a new bridge to this route as a nested child.

=head2 C<delete>

  my $route = $route->delete('/:foo' => sub {...});

Generate route matching only C<DELETE> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<detour>

  $r = $r->detour(action => 'foo');
  $r = $r->detour({action => 'foo'});
  $r = $r->detour('controller#action');
  $r = $r->detour('controller#action', foo => 'bar');
  $r = $r->detour('controller#action', {foo => 'bar'});
  $r = $r->detour($app);
  $r = $r->detour($app, foo => 'bar');
  $r = $r->detour($app, {foo => 'bar'});
  $r = $r->detour('MyApp');
  $r = $r->detour('MyApp', foo => 'bar');
  $r = $r->detour('MyApp', {foo => 'bar'});

Set default parameters for this route and allow partial matching to simplify
application embedding.

=head2 C<dispatch>

  my $success = $r->dispatch(Mojolicious::Controller->new);

Match routes and dispatch.

=head2 C<get>

  my $route = $route->get('/:foo' => sub {...});

Generate route matching only C<GET> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<has_conditions>

  my $success = $r->has_conditions;

Check if this route contains conditions.

=head2 C<has_custom_name>

  my $success = $r->has_custom_name;

Check if this route has a custom user defined name.

=head2 C<has_websocket>

  my $success = $r->has_websocket;

Check if this route has a WebSocket ancestor.

=head2 C<hide>

  $r = $r->hide('new');

Hide controller method or attribute from routes.

=head2 C<is_endpoint>

  my $success = $r->is_endpoint;

Check if this route qualifies as an endpoint.

=head2 C<is_websocket>

  my $success = $r->is_websocket;

Check if this route is a WebSocket.

=head2 C<name>

  my $name = $r->name;
  $r       = $r->name('foo');

The name of this route, defaults to an automatically generated name based on
the route pattern. Note that the name C<current> is reserved for refering to
the current route.

=head2 C<over>

  $r = $r->over(foo => qr/\w+/);

Apply condition parameters to this route and disable routing cache.

=head2 C<parse>

  $r = $r->parse('/:controller/:action');

Parse a pattern.

=head2 C<patch>

  my $route = $route->patch('/:foo' => sub {...});

Generate route matching only C<PATCH> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<post>

  my $route = $route->post('/:foo' => sub {...});

Generate route matching only C<POST> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<put>

  my $route = $route->put('/:foo' => sub {...});

Generate route matching only C<PUT> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<render>

  my $path = $r->render($path);
  my $path = $r->render($path, {foo => 'bar'});

Render route with parameters into a path.

=head2 C<route>

  my $route = $r->route('/:c/:a', a => qr/\w+/);

Add a new nested child to this route.

=head2 C<to>

  my $to  = $r->to;
  $r = $r->to(action => 'foo');
  $r = $r->to({action => 'foo'});
  $r = $r->to('controller#action');
  $r = $r->to('controller#action', foo => 'bar');
  $r = $r->to('controller#action', {foo => 'bar'});
  $r = $r->to($app);
  $r = $r->to($app, foo => 'bar');
  $r = $r->to($app, {foo => 'bar'});
  $r = $r->to('MyApp');
  $r = $r->to('MyApp', foo => 'bar');
  $r = $r->to('MyApp', {foo => 'bar'});

Set default parameters for this route.

=head2 C<to_string>

  my $string = $r->to_string;

Stringifies the whole route.

=head2 C<under>

  my $route = $r->under(sub {...});
  my $route = $r->under('/:foo');

Generate bridges. See also the L<Mojolicious::Lite> tutorial for more
argument variations.

=head2 C<via>

  my $methods = $r->via;
  $r          = $r->via('GET');
  $r          = $r->via(qw/GET POST/);
  $r          = $r->via([qw/GET POST/]);

Restrict HTTP methods this route is allowed to handle, defaults to no
restrictions.

=head2 C<waypoint>

  my $r = $r->waypoint('/:c/:a', a => qr/\w+/);

Add a waypoint to this route as nested child.

=head2 C<websocket>

  my $websocket = $r->websocket('/:foo' => sub {...});

Generate route matching only C<WebSocket> handshakes. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head1 SHORTCUTS

In addition to the attributes and methods above you can also call shortcuts
on L<Mojolicious::Routes> objects.

  $r->add_shortcut(firefox => sub {
    my ($r, $path) = @_;
    $r->get($path, agent => qr/Firefox/);
  });

  $r->firefox('/welcome')->to('firefox#welcome');
  $r->firefox('/bye')->to('firefox#bye);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
