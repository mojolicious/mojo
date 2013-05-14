package Mojolicious::Routes::Route;
use Mojo::Base -base;

use Carp 'croak';
use Mojolicious::Routes::Pattern;
use Scalar::Util qw(blessed weaken);

has [qw(inline parent partial)];
has 'children' => sub { [] };
has pattern    => sub { Mojolicious::Routes::Pattern->new };

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^([\w:]+)::(\w+)$/;
  croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  # Call shortcut with current route
  croak qq{Can't locate object method "$method" via package "$package"}
    unless my $shortcut = $self->root->shortcuts->{$method};
  return $self->$shortcut(@_);
}

sub DESTROY { }

sub new { shift->SUPER::new->parse(@_) }

sub add_child {
  my ($self, $route) = @_;
  weaken $route->remove->parent($self)->{parent};
  push @{$self->children}, $route;
  return $self;
}

sub any { shift->_generate_route(ref $_[0] eq 'ARRAY' ? shift : [], @_) }

sub bridge { shift->route(@_)->inline(1) }

sub delete { shift->_generate_route(DELETE => @_) }

sub detour { shift->partial(1)->to(@_) }

sub find {
  my ($self, $name) = @_;

  my @children = (@{$self->children});
  my $candidate;
  while (my $child = shift @children) {

    # Match
    $candidate = $child->has_custom_name ? return $child : $child
      if $child->name eq $name;

    # Search children too
    push @children, @{$child->children};
  }

  return $candidate;
}

sub get { shift->_generate_route(GET => @_) }

sub has_conditions {
  my $self = shift;
  return 1 if @{$self->over || []};
  return undef unless my $parent = $self->parent;
  return $parent->has_conditions;
}

sub has_custom_name { !!shift->{custom} }

sub has_websocket {
  my $self = shift;
  return 1 if $self->is_websocket;
  return undef unless my $parent = $self->parent;
  return $parent->is_websocket;
}

sub is_endpoint { $_[0]->inline ? undef : !@{$_[0]->children} }

sub is_websocket { !!shift->{websocket} }

sub name {
  my $self = shift;
  return $self->{name} unless @_;
  $self->{name}   = shift;
  $self->{custom} = 1;
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
  $self->{name} = $self->pattern->parse(@_)->pattern // '';
  $self->{name} =~ s/\W+//g;
  return $self;
}

sub patch { shift->_generate_route(PATCH => @_) }
sub post  { shift->_generate_route(POST  => @_) }
sub put   { shift->_generate_route(PUT   => @_) }

sub remove {
  my $self = shift;
  return $self unless my $parent = $self->parent;
  @{$parent->children} = grep { $_ ne $self } @{$parent->children};
  return $self->parent(undef);
}

sub render {
  my ($self, $path, $values) = @_;

  # Render pattern
  my $prefix = $self->pattern->render($values, !$path);
  $path = "$prefix$path" unless $prefix eq '/';
  $path ||= '/' unless my $parent = $self->parent;

  # Let parent render
  return $parent ? $parent->render($path, $values) : $path;
}

sub root {
  my $root = my $parent = shift;
  while ($parent = $parent->parent) { $root = $parent }
  return $root;
}

sub route {
  my $self   = shift;
  my $route  = $self->add_child($self->new(@_))->children->[-1];
  my $format = $self->pattern->constraints->{format};
  $route->pattern->constraints->{format} //= 0 if defined $format && !$format;
  return $route;
}

sub to {
  my $self = shift;

  my $pattern = $self->pattern;
  return $pattern->defaults unless @_;
  my ($shortcut, %defaults) = _defaults(@_);

  if ($shortcut) {

    # Application
    if (ref $shortcut || $shortcut =~ /^[\w:]+$/) {
      $defaults{app} = $shortcut;
    }

    # Controller and action
    elsif ($shortcut =~ /^([\w\-:]+)?\#(\w+)?$/) {
      $defaults{controller} = $1 if defined $1;
      $defaults{action}     = $2 if defined $2;
    }
  }

  $pattern->defaults({%{$pattern->defaults}, %defaults});

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
  my $methods = [map uc($_), @{ref $_[0] ? $_[0] : [@_]}];
  $self->{via} = $methods if @$methods;
  return $self;
}

sub websocket {
  my $route = shift->get(@_);
  $route->{websocket} = 1;
  return $route;
}

sub _defaults {

  # Hash or shortcut (one)
  return ref $_[0] eq 'HASH' ? (undef, %{shift()}) : @_ if @_ == 1;

  # Shortcut and values (odd)
  return shift, @_ if @_ % 2;

  # Shortcut and hash or just values (even)
  return ref $_[1] eq 'HASH' ? (shift, %{shift()}) : (undef, @_);
}

sub _generate_route {
  my ($self, $methods, @args) = @_;

  my ($cb, @conditions, @constraints, %defaults, $name, $pattern);
  while (defined(my $arg = shift @args)) {

    # First scalar is the pattern
    if (!ref $arg && !$pattern) { $pattern = $arg }

    # Scalar
    elsif (!ref $arg && @args) { push @conditions, $arg, shift @args }

    # Last scalar is the route name
    elsif (!ref $arg) { $name = $arg }

    # Callback
    elsif (ref $arg eq 'CODE') { $cb = $arg }

    # Constraints
    elsif (ref $arg eq 'ARRAY') { @constraints = @$arg }

    # Defaults
    elsif (ref $arg eq 'HASH') { %defaults = %$arg }
  }

  # Callback
  $defaults{cb} = $cb if $cb;

  # Create bridge or route
  my $route
    = $methods eq 'under'
    ? $self->bridge($pattern, @constraints)
    : $self->route($pattern, @constraints)->via($methods);
  $route->over(\@conditions)->to(\%defaults);

  return defined $name ? $route->name($name) : $route;
}

1;

=head1 NAME

Mojolicious::Routes::Route - Route

=head1 SYNOPSIS

  use Mojolicious::Routes::Route;

  my $r = Mojolicious::Routes::Route->new;

=head1 DESCRIPTION

L<Mojolicious::Routes::Route> is the route container used by
L<Mojolicious::Routes>.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Route> implements the following attributes.

=head2 children

  my $children = $r->children;
  $r           = $r->children([Mojolicious::Routes::Route->new]);

The children of this route, used for nesting routes.

=head2 inline

  my $inline = $r->inline;
  $r         = $r->inline(1);

Allow C<bridge> semantics for this route.

=head2 parent

  my $parent = $r->parent;
  $r         = $r->parent(Mojolicious::Routes::Route->new);

The parent of this route, used for nesting routes.

=head2 partial

  my $partial = $r->partial;
  $r          = $r->partial(1);

Route has no specific end, remaining characters will be captured in C<path>.

=head2 pattern

  my $pattern = $r->pattern;
  $r          = $r->pattern(Mojolicious::Routes::Pattern->new);

Pattern for this route, defaults to a L<Mojolicious::Routes::Pattern> object.

=head1 METHODS

L<Mojolicious::Routes::Route> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 new

  my $r = Mojolicious::Routes::Route->new;
  my $r = Mojolicious::Routes::Route->new('/:controller/:action');

Construct a new L<Mojolicious::Routes::Route> object and <parse> pattern if
necessary.

=head2 add_child

  $r = $r->add_child(Mojolicious::Routes::Route->new);

Add a new child to this route, it will be automatically removed from its
current parent if necessary.

  # Reattach route
  $r->add_child($r->find('foo'));

=head2 any

  my $route = $r->any('/:foo' => sub {...});
  my $route = $r->any([qw(GET POST)] => '/:foo' => sub {...});

Generate route matching any of the listed HTTP request methods or all. See
also the L<Mojolicious::Lite> tutorial for more argument variations.

  $r->any('/user')->to('user#whatever');

=head2 bridge

  my $bridge = $r->bridge;
  my $bridge = $r->bridge('/:action');
  my $bridge = $r->bridge('/:action', action => qr/\w+/);
  my $bridge = $r->bridge(format => 0);

Generate bridge route.

  my $auth = $r->bridge('/user')->to('user#auth');
  $auth->get('/show')->to('#show');
  $auth->post('/create')->to('#create');

=head2 delete

  my $route = $r->delete('/:foo' => sub {...});

Generate route matching only C<DELETE> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->delete('/user')->to('user#remove');

=head2 detour

  $r = $r->detour(action => 'foo');
  $r = $r->detour('controller#action');
  $r = $r->detour(Mojolicious->new, foo => 'bar');
  $r = $r->detour('MyApp', {foo => 'bar'});

Set default parameters for this route and allow partial matching to simplify
application embedding, takes the same arguments as C<to>.

=head2 find

  my $route = $r->find('foo');

Find child route by name, custom names have precedence over automatically
generated ones.

  $r->find('show_user')->to(foo => 'bar');

=head2 get

  my $route = $r->get('/:foo' => sub {...});

Generate route matching only C<GET> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->get('/user')->to('user#show');

=head2 has_conditions

  my $success = $r->has_conditions;

Check if this route has active conditions.

=head2 has_custom_name

  my $success = $r->has_custom_name;

Check if this route has a custom name.

=head2 has_websocket

  my $success = $r->has_websocket;

Check if this route has a WebSocket ancestor.

=head2 is_endpoint

  my $success = $r->is_endpoint;

Check if this route qualifies as an endpoint.

=head2 is_websocket

  my $success = $r->is_websocket;

Check if this route is a WebSocket.

=head2 name

  my $name = $r->name;
  $r       = $r->name('foo');

The name of this route, defaults to an automatically generated name based on
the route pattern. Note that the name C<current> is reserved for referring to
the current route.

  $r->get('/user')->to('user#show')->name('show_user');

=head2 options

  my $route = $r->options('/:foo' => sub {...});

Generate route matching only C<OPTIONS> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->options('/user')->to('user#overview');

=head2 over

  my $over = $r->over;
  $r       = $r->over(foo => 1);
  $r       = $r->over(foo => 1, bar => {baz => 'yada'});
  $r       = $r->over([foo => 1, bar => {baz => 'yada'}]);

Activate conditions for this route. Note that this automatically disables the
routing cache, since conditions are too complex for caching.

  $r->get('/foo')->over(host => qr/mojolicio\.us/)->to('foo#bar');

=head2 parse

  $r = $r->parse('/:action');
  $r = $r->parse('/:action', action => qr/\w+/);
  $r = $r->parse(format => 0);

Parse pattern.

=head2 patch

  my $route = $r->patch('/:foo' => sub {...});

Generate route matching only C<PATCH> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->patch('/user')->to('user#update');

=head2 post

  my $route = $r->post('/:foo' => sub {...});

Generate route matching only C<POST> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->post('/user')->to('user#create');

=head2 put

  my $route = $r->put('/:foo' => sub {...});

Generate route matching only C<PUT> requests. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->put('/user')->to('user#replace');

=head2 remove

  $r = $r->remove;

Remove route from parent.

  # Remove route completely
  $r->find('foo')->remove;

  # Reattach route to new parent
  $r->route('/foo')->add_child($r->find('bar')->remove);

=head2 render

  my $path = $r->render($suffix);
  my $path = $r->render($suffix, {foo => 'bar'});

Render route with parameters into a path.

=head2 root

  my $root = $r->root;

The L<Mojolicious::Routes> object this route is an descendent of.

  $r->root->cache(0);

=head2 route

  my $route = $r->route;
  my $route = $r->route('/:action');
  my $route = $r->route('/:action', action => qr/\w+/);
  my $route = $r->route(format => 0);

Generate route matching all HTTP request methods.

=head2 to

  my $defaults = $r->to;
  $r           = $r->to(action => 'foo');
  $r           = $r->to({action => 'foo'});
  $r           = $r->to('controller#action');
  $r           = $r->to('controller#action', foo => 'bar');
  $r           = $r->to('controller#action', {foo => 'bar'});
  $r           = $r->to(Mojolicious->new);
  $r           = $r->to(Mojolicious->new, foo => 'bar');
  $r           = $r->to(Mojolicious->new, {foo => 'bar'});
  $r           = $r->to('MyApp');
  $r           = $r->to('MyApp', foo => 'bar');
  $r           = $r->to('MyApp', {foo => 'bar'});

Set default parameters for this route.

=head2 to_string

  my $str = $r->to_string;

Stringify the whole route.

=head2 under

  my $route = $r->under(sub {...});
  my $route = $r->under('/:foo');

Generate bridge route. See also the L<Mojolicious::Lite> tutorial for more
argument variations.

  my $auth = $r->under('/user')->to('user#auth');
  $auth->get('/show')->to('#show');
  $auth->post('/create')->to('#create');

=head2 via

  my $methods = $r->via;
  $r          = $r->via('GET');
  $r          = $r->via(qw(GET POST));
  $r          = $r->via([qw(GET POST)]);

Restrict HTTP methods this route is allowed to handle, defaults to no
restrictions.

  $r->route('/foo')->via(qw(GET POST))->to('foo#bar');

=head2 websocket

  my $ws = $r->websocket('/:foo' => sub {...});

Generate route matching only WebSocket handshakes. See also the
L<Mojolicious::Lite> tutorial for more argument variations.

  $r->websocket('/echo')->to('example#echo');

=head1 SHORTCUTS

In addition to the attributes and methods above you can also call shortcuts
on L<Mojolicious::Routes::Route> objects.

  $r->root->add_shortcut(firefox => sub {
    my ($r, $path) = @_;
    $r->get($path, agent => qr/Firefox/);
  });

  $r->firefox('/welcome')->to('firefox#welcome');
  $r->firefox('/bye')->to('firefox#bye);

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
