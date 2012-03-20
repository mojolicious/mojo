package Mojolicious::Routes::Route;
use Mojo::Base -base;

use Carp 'croak';
use Mojolicious::Routes::Pattern;
use Scalar::Util qw/blessed weaken/;

has [qw/block inline parent partial/];
has 'children' => sub { [] };
has [qw/conditions shortcuts/] => sub { {} };
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
  $route->conditions($self->conditions)->shortcuts($self->shortcuts);
  push @{$self->children}, $route;
  return $self;
}

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

sub any { shift->_generate_route(ref $_[0] eq 'ARRAY' ? shift : [], @_) }

sub bridge { shift->route(@_)->inline(1) }

sub delete { shift->_generate_route(DELETE => @_) }

sub detour { shift->partial(1)->to(@_) }

# DEPRECATED in Leaf Fluttering In Wind!
sub dictionary {
  warn <<EOF;
Mojolicious::Routes::Route->dictionary is DEPRECATED in favor of
Mojolicious::Routes::Route->conditions!
EOF
  return shift->conditions(@_);
}

sub find {
  my ($self, $name) = @_;

  # Check all children
  my @children = (@{$self->children});
  my $candidate;
  while (my $child = shift @children) {

    # Match
    if ($child->name eq $name) {
      $candidate = $child;
      return $candidate if $child->has_custom_name;
    }

    # Search children too
    push @children, @{$child->children};
  }

  return $candidate;
}

sub get { shift->_generate_route(GET => @_) }

sub has_conditions {
  my $self = shift;
  return 1 if @{$self->over || []};
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
  return $self->{name} unless @_;
  if (defined(my $name = shift)) {
    $self->{name}   = $name;
    $self->{custom} = 1;
  }

  return $self;
}

sub options { shift->_generate_route(OPTIONS => @_) }

sub over {
  my $self = shift;

  # Routes with conditions can't be cached
  return $self->{over} unless @_;
  my $conditions = ref $_[0] eq 'ARRAY' ? $_[0] : [@_];
  return $self unless @$conditions;
  $self->{over} = $conditions;
  $self->root->cache(0);

  return $self;
}

sub parse {
  my $self = shift;
  my $name = $self->pattern->parse(@_)->pattern // '';
  $name =~ s/\W+//g;
  $self->{name} = $name;
  return $self;
}

sub patch { shift->_generate_route(PATCH => @_) }
sub post  { shift->_generate_route(POST  => @_) }
sub put   { shift->_generate_route(PUT   => @_) }

sub render {
  my ($self, $path, $values) = @_;

  # Path prefix
  my $prefix = $self->pattern->render($values);
  $path = $prefix . $path unless $prefix eq '/';

  # Make sure there is always a root
  my $parent = $self->parent;
  $path = '/' if !$path && !$parent;

  # Format
  if ((my $format = $values->{format}) && !$parent) {
    $path .= ".$format" unless $path =~ m#\.[^/]+$#;
  }

  return $parent ? $parent->render($path, $values) : $path;
}

sub root {
  my $root = my $parent = shift;
  while ($parent = $parent->parent) { $root = $parent }
  return $root;
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
  return $self->{via} unless @_;
  my $methods = [map { uc $_ } @{ref $_[0] ? $_[0] : [@_]}];
  $self->{via} = $methods if @$methods;
  return $self;
}

sub waypoint { shift->route(@_)->block(1) }

sub websocket {
  my $self  = shift;
  my $route = $self->get(@_);
  $route->{websocket} = 1;
  return $route;
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

1;
__END__

=head1 NAME

Mojolicious::Routes::Route - Route container

=head1 SYNOPSIS

  use Mojolicious::Routes::Route;

  my $r = Mojolicious::Routes::Route->new;

=head1 DESCRIPTION

L<Mojolicious::Routes::Route> is the route container used by
L<Mojolicious::Routes>.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Route> implements the following attributes.

=head2 C<block>

  my $block = $r->block;
  $r        = $r->block(1);

Allow this route to match even if it's not an endpoint, used for waypoints.

=head2 C<children>

  my $children = $r->children;
  $r           = $r->children([Mojolicious::Routes::Route->new]);

The children of this routes object, used for nesting routes.

=head2 C<conditions>

  my $conditions = $r->conditions;
  $r             = $r->conditions({foo => sub {...}});

Contains all available conditions for this route.

=head2 C<inline>

  my $inline = $r->inline;
  $r         = $r->inline(1);

Allow C<bridge> semantics for this route.

=head2 C<parent>

  my $parent = $r->parent;
  $r         = $r->parent(Mojolicious::Routes::Route->new);

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

L<Mojolicious::Routes::Route> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<new>

  my $r = Mojolicious::Routes::Route->new;
  my $r = Mojolicious::Routes::Route->new('/:controller/:action');

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

  my $route = $r->any('/:foo' => sub {...});
  my $route = $r->any(['GET', 'POST'] => '/:foo' => sub {...});

Generate route matching any of the listed HTTP request methods or all. See
also the L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<bridge>

  my $bridge = $r->bridge;
  my $bridge = $r->bridge('/:controller/:action');

Add a new bridge to this route as a nested child.

=head2 C<delete>

  my $route = $r->delete('/:foo' => sub {...});

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

=head2 C<find>

  my $route = $r->find('foo');

Find child route by name, custom names have precedence over automatically
generated ones.

=head2 C<get>

  my $route = $r->get('/:foo' => sub {...});

Generate route matching only C<GET> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<has_conditions>

  my $success = $r->has_conditions;

Check if this route contains conditions.

=head2 C<has_custom_name>

  my $success = $r->has_custom_name;

Check if this route has a custom name.

=head2 C<has_websocket>

  my $success = $r->has_websocket;

Check if this route has a WebSocket ancestor.

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

=head2 C<options>

  my $route = $r->options('/:foo' => sub {...});

Generate route matching only C<OPTIONS> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<over>

  my $conditions = $r->over;
  $r             = $r->over(foo => qr/\w+/);

Apply condition parameters to this route and disable routing cache.

=head2 C<parse>

  $r = $r->parse('/:controller/:action');

Parse a pattern.

=head2 C<patch>

  my $route = $r->patch('/:foo' => sub {...});

Generate route matching only C<PATCH> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<post>

  my $route = $r->post('/:foo' => sub {...});

Generate route matching only C<POST> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<put>

  my $route = $r->put('/:foo' => sub {...});

Generate route matching only C<PUT> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

=head2 C<render>

  my $path = $r->render($suffix);
  my $path = $r->render($suffix, {foo => 'bar'});

Render route with parameters into a path.

=head2 C<root>

  my $root = $r->root;

The root of the routes tree.

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
on L<Mojolicious::Routes::Route> objects.

  $r->add_shortcut(firefox => sub {
    my ($r, $path) = @_;
    $r->get($path, agent => qr/Firefox/);
  });

  $r->firefox('/welcome')->to('firefox#welcome');
  $r->firefox('/bye')->to('firefox#bye);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
