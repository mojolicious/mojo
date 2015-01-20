package Mojolicious::Routes::Route;
use Mojo::Base -base;

use Carp ();
use Mojo::Util;
use Mojolicious::Routes::Pattern;
use Scalar::Util ();

has [qw(inline parent partial)];
has 'children' => sub { [] };
has pattern    => sub { Mojolicious::Routes::Pattern->new };

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless Scalar::Util::blessed $self && $self->isa(__PACKAGE__);

  # Call shortcut with current route
  Carp::croak qq{Can't locate object method "$method" via package "$package"}
    unless my $shortcut = $self->root->shortcuts->{$method};
  return $self->$shortcut(@_);
}

sub add_child {
  my ($self, $route) = @_;
  Scalar::Util::weaken $route->remove->parent($self)->{parent};
  push @{$self->children}, $route;
  return $self;
}

sub any { shift->_generate_route(ref $_[0] eq 'ARRAY' ? shift : [], @_) }

# DEPRECATED in Tiger Face!
sub bridge {
  Mojo::Util::deprecated 'Mojolicious::Routes::Route::bridge is DEPRECATED in'
    . ' favor of Mojolicious::Routes::Route::under';
  shift->route(@_)->inline(1);
}

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

sub has_custom_name { !!shift->{custom} }

sub has_websocket {
  my $self = shift;
  return $self->{has_websocket} if exists $self->{has_websocket};
  return $self->{has_websocket} = grep { $_->is_websocket } @{$self->_chain};
}

sub is_endpoint { $_[0]->inline ? undef : !@{$_[0]->children} }

sub is_websocket { !!shift->{websocket} }

sub name {
  my $self = shift;
  return $self->{name} unless @_;
  @$self{qw(name custom)} = (shift, 1);
  return $self;
}

sub new { shift->SUPER::new->parse(@_) }

sub options { shift->_generate_route(OPTIONS => @_) }

sub over {
  my $self = shift;

  # Routes with conditions can't be cached
  return $self->{over} unless @_;
  my $conditions = ref $_[0] eq 'ARRAY' ? $_[0] : [@_];
  return $self unless @$conditions;
  $self->{over} = $conditions;
  $self->root->cache->max_keys(0);

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
  my ($self, $values) = @_;
  my $path = join '',
    map { $_->pattern->render($values, !@{$_->children} && !$_->partial) }
    @{$self->_chain};
  return $path || '/';
}

sub root { shift->_chain->[0] }

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
  my ($shortcut, %defaults) = Mojo::Util::_options(@_);

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

  @{$pattern->defaults}{keys %defaults} = values %defaults;

  return $self;
}

sub to_string {
  join '', map { $_->pattern->pattern // '' } @{shift->_chain};
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

sub _chain {
  my @chain = (my $parent = shift);
  unshift @chain, $parent while $parent = $parent->parent;
  return \@chain;
}

sub _generate_route {
  my ($self, $methods, @args) = @_;

  my (@conditions, @constraints, %defaults, $name, $pattern);
  while (defined(my $arg = shift @args)) {

    # First scalar is the pattern
    if (!ref $arg && !$pattern) { $pattern = $arg }

    # Scalar
    elsif (!ref $arg && @args) { push @conditions, $arg, shift @args }

    # Last scalar is the route name
    elsif (!ref $arg) { $name = $arg }

    # Callback
    elsif (ref $arg eq 'CODE') { $defaults{cb} = $arg }

    # Constraints
    elsif (ref $arg eq 'ARRAY') { push @constraints, @$arg }

    # Defaults
    elsif (ref $arg eq 'HASH') { %defaults = (%defaults, %$arg) }
  }

  my $route
    = $self->route($pattern, @constraints)->over(\@conditions)->to(\%defaults);
  $methods eq 'under' ? $route->inline(1) : $route->via($methods);

  return defined $name ? $route->name($name) : $route;
}

1;

=encoding utf8

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

  my $bool = $r->inline;
  $r       = $r->inline($bool);

Allow L</"under"> semantics for this route.

=head2 parent

  my $parent = $r->parent;
  $r         = $r->parent(Mojolicious::Routes::Route->new);

The parent of this route, usually a L<Mojolicious::Routes::Route> object.

=head2 partial

  my $bool = $r->partial;
  $r       = $r->partial($bool);

Route has no specific end, remaining characters will be captured in C<path>.

=head2 pattern

  my $pattern = $r->pattern;
  $r          = $r->pattern(Mojolicious::Routes::Pattern->new);

Pattern for this route, defaults to a L<Mojolicious::Routes::Pattern> object.

=head1 METHODS

L<Mojolicious::Routes::Route> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add_child

  $r = $r->add_child(Mojolicious::Routes::Route->new);

Add a new child to this route, it will be automatically removed from its
current parent if necessary.

  # Reattach route
  $r->add_child($r->find('foo'));

=head2 any

  my $route = $r->any('/:foo');
  my $route = $r->any('/:foo' => sub {...});
  my $route = $r->any('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->any('/:foo' => [foo => qr/\w+/] => sub {...});
  my $route = $r->any([qw(GET POST)] => '/:foo' => sub {...});
  my $route = $r->any([qw(GET POST)] => '/:foo' => [foo => qr/\w+/]);

Generate L<Mojolicious::Routes::Route> object matching any of the listed HTTP
request methods or all. See also L<Mojolicious::Guides::Tutorial> for many
more argument variations.

  $r->any('/user')->to('user#whatever');

=head2 delete

  my $route = $r->delete('/:foo');
  my $route = $r->delete('/:foo' => sub {...});
  my $route = $r->delete('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->delete('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only C<DELETE>
requests. See also L<Mojolicious::Guides::Tutorial> for many more argument
variations.

  $r->delete('/user')->to('user#remove');

=head2 detour

  $r = $r->detour(action => 'foo');
  $r = $r->detour('controller#action');
  $r = $r->detour(Mojolicious->new, foo => 'bar');
  $r = $r->detour('MyApp', {foo => 'bar'});

Set default parameters for this route and allow partial matching to simplify
application embedding, takes the same arguments as L</"to">.

=head2 find

  my $route = $r->find('foo');

Find child route by name, custom names have precedence over automatically
generated ones.

  $r->find('show_user')->to(foo => 'bar');

=head2 get

  my $route = $r->get('/:foo');
  my $route = $r->get('/:foo' => sub {...});
  my $route = $r->get('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->get('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only C<GET> requests.
See also L<Mojolicious::Guides::Tutorial> for many more argument variations.

  $r->get('/user')->to('user#show');

=head2 has_custom_name

  my $bool = $r->has_custom_name;

Check if this route has a custom name.

=head2 has_websocket

  my $bool = $r->has_websocket;

Check if this route has a WebSocket ancestor and cache the result for future
checks.

=head2 is_endpoint

  my $bool = $r->is_endpoint;

Check if this route qualifies as an endpoint.

=head2 is_websocket

  my $bool = $r->is_websocket;

Check if this route is a WebSocket.

=head2 name

  my $name = $r->name;
  $r       = $r->name('foo');

The name of this route, defaults to an automatically generated name based on
the route pattern. Note that the name C<current> is reserved for referring to
the current route.

  $r->get('/user')->to('user#show')->name('show_user');

=head2 new

  my $r = Mojolicious::Routes::Route->new;
  my $r = Mojolicious::Routes::Route->new('/:action');
  my $r = Mojolicious::Routes::Route->new('/:action', action => qr/\w+/);
  my $r = Mojolicious::Routes::Route->new(format => 0);

Construct a new L<Mojolicious::Routes::Route> object and L</"parse"> pattern
if necessary.

=head2 options

  my $route = $r->options('/:foo');
  my $route = $r->options('/:foo' => sub {...});
  my $route = $r->options('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->options('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only C<OPTIONS>
requests. See also L<Mojolicious::Guides::Tutorial> for many more argument
variations.

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

  my $route = $r->patch('/:foo');
  my $route = $r->patch('/:foo' => sub {...});
  my $route = $r->patch('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->patch('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only C<PATCH> requests.
See also L<Mojolicious::Guides::Tutorial> for many more argument variations.

  $r->patch('/user')->to('user#update');

=head2 post

  my $route = $r->post('/:foo');
  my $route = $r->post('/:foo' => sub {...});
  my $route = $r->post('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->post('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only C<POST> requests.
See also L<Mojolicious::Guides::Tutorial> for many more argument variations.

  $r->post('/user')->to('user#create');

=head2 put

  my $route = $r->put('/:foo');
  my $route = $r->put('/:foo' => sub {...});
  my $route = $r->put('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->put('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only C<PUT> requests.
See also L<Mojolicious::Guides::Tutorial> for many more argument variations.

  $r->put('/user')->to('user#replace');

=head2 remove

  $r = $r->remove;

Remove route from parent.

  # Remove route completely
  $r->find('foo')->remove;

  # Reattach route to new parent
  $r->route('/foo')->add_child($r->find('bar')->remove);

=head2 render

  my $path = $r->render({foo => 'bar'});

Render route with parameters into a path.

=head2 root

  my $root = $r->root;

The L<Mojolicious::Routes> object this route is a descendant of.

=head2 route

  my $route = $r->route;
  my $route = $r->route('/:action');
  my $route = $r->route('/:action', action => qr/\w+/);
  my $route = $r->route(format => 0);

Low-level generator for routes matching all HTTP request methods, returns a
L<Mojolicious::Routes::Route> object.

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
  my $route = $r->under('/:foo' => sub {...});
  my $route = $r->under('/:foo' => {foo => 'bar'});
  my $route = $r->under('/:foo' => [foo => qr/\w+/]);
  my $route = $r->under([format => 0]);

Generate L<Mojolicious::Routes::Route> object for a nested route with its own
intermediate destination. See also L<Mojolicious::Guides::Tutorial> for many
more argument variations.

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

  my $route = $r->websocket('/:foo');
  my $route = $r->websocket('/:foo' => sub {...});
  my $route = $r->websocket('/:foo' => {foo => 'bar'} => sub {...});
  my $route = $r->websocket('/:foo' => [foo => qr/\w+/] => sub {...});

Generate L<Mojolicious::Routes::Route> object matching only WebSocket
handshakes. See also L<Mojolicious::Guides::Tutorial> for many more argument
variations.

  $r->websocket('/echo')->to('example#echo');

=head1 AUTOLOAD

In addition to the L</"ATTRIBUTES"> and L</"METHODS"> above you can also call
shortcuts provided by L</"root"> on L<Mojolicious::Routes::Route> objects.

  # Add a "firefox" shortcut
  $r->root->add_shortcut(firefox => sub {
    my ($r, $path) = @_;
    $r->get($path, agent => qr/Firefox/);
  });

  # Use "firefox" shortcut to generate routes
  $r->firefox('/welcome')->to('firefox#welcome');
  $r->firefox('/bye')->to('firefox#bye');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
