package Mojolicious::Routes;
use Mojo::Base 'Mojolicious::Routes::Route';

use List::Util 'first';
use Mojo::Cache;
use Mojo::Loader 'load_class';
use Mojo::Util 'camelize';
use Mojolicious::Routes::Match;
use Scalar::Util 'weaken';

has base_classes => sub { [qw(Mojolicious::Controller Mojo)] };
has cache        => sub { Mojo::Cache->new };
has [qw(conditions shortcuts)] => sub { {} };
has hidden     => sub { [qw(attr has new tap)] };
has namespaces => sub { [] };

sub add_condition { $_[0]->conditions->{$_[1]} = $_[2] and return $_[0] }
sub add_shortcut  { $_[0]->shortcuts->{$_[1]}  = $_[2] and return $_[0] }

sub continue {
  my ($self, $c) = @_;

  my $match    = $c->match;
  my $stack    = $match->stack;
  my $position = $match->position;
  return _render($c) unless my $field = $stack->[$position];

  # Merge captures into stash
  my $stash = $c->stash;
  @{$stash->{'mojo.captures'} //= {}}{keys %$field} = values %$field;
  @$stash{keys %$field} = values %$field;

  my $continue;
  my $last = !$stack->[++$position];
  if (my $cb = $field->{cb}) { $continue = $self->_callback($c, $cb, $last) }
  else { $continue = $self->_controller($c, $field, $last) }
  $match->position($position);
  $self->continue($c) if $last || $continue;
}

sub dispatch {
  my ($self, $c) = @_;
  $self->match($c);
  @{$c->match->stack} ? $self->continue($c) : return undef;
  return 1;
}

sub hide { push @{shift->hidden}, @_ }

sub is_hidden {
  my ($self, $method) = @_;
  my $h = $self->{hiding} ||= {map { $_ => 1 } @{$self->hidden}};
  return !!($h->{$method} || $method =~ /^_/ || $method =~ /^[A-Z_]+$/);
}

sub lookup { ($_[0]{reverse} //= $_[0]->_index)->{$_[1]} }

sub match {
  my ($self, $c) = @_;

  # Path (partial path gets priority)
  my $req  = $c->req;
  my $path = $c->stash->{path};
  if (defined $path) { $path = "/$path" if $path !~ m!^/! }
  else               { $path = $req->url->path->to_route }

  # Method (HEAD will be treated as GET)
  my $method = uc($req->url->query->clone->param('_method') || $req->method);
  $method = 'GET' if $method eq 'HEAD';

  # Check cache
  my $ws = $c->tx->is_websocket ? 1 : 0;
  my $match = Mojolicious::Routes::Match->new(root => $self);
  $c->match($match);
  my $cache = $self->cache;
  if (my $result = $cache->get("$method:$path:$ws")) {
    return $match->endpoint($result->{endpoint})->stack($result->{stack});
  }

  # Check routes
  $match->find($c => {method => $method, path => $path, websocket => $ws});
  return unless my $route = $match->endpoint;
  $cache->set(
    "$method:$path:$ws" => {endpoint => $route, stack => $match->stack});
}

sub _action { shift->plugins->emit_chain(around_action => @_) }

sub _callback {
  my ($self, $c, $cb, $last) = @_;
  $c->stash->{'mojo.routed'} = 1 if $last;
  my $app = $c->app;
  $app->log->debug('Routing to a callback');
  return _action($app, $c, $cb, $last);
}

sub _class {
  my ($self, $c, $field) = @_;

  # Application instance
  return $field->{app} if ref $field->{app};

  # Application class
  my @classes;
  my $class = $field->{controller} ? camelize $field->{controller} : '';
  if ($field->{app}) { push @classes, $field->{app} }

  # Specific namespace
  elsif (defined(my $ns = $field->{namespace})) {
    if ($class) { push @classes, $ns ? "${ns}::$class" : $class }
    elsif ($ns) { push @classes, $ns }
  }

  # All namespaces
  elsif ($class) { push @classes, "${_}::$class" for @{$self->namespaces} }

  # Try to load all classes
  my $log = $c->app->log;
  for my $class (@classes) {

    # Failed
    next unless defined(my $found = $self->_load($class));
    return !$log->debug(qq{Class "$class" is not a controller}) unless $found;

    # Success
    my $new = $class->new(%$c);
    weaken $new->{$_} for qw(app tx);
    return $new;
  }

  # Nothing found
  $log->debug(qq{Controller "$classes[-1]" does not exist}) if @classes;
  return @classes ? undef : 0;
}

sub _controller {
  my ($self, $old, $field, $last) = @_;

  # Load and instantiate controller/application
  my $new;
  unless ($new = $self->_class($old, $field)) { return defined $new }

  # Application
  my $class = ref $new;
  my $app   = $old->app;
  my $log   = $app->log;
  if ($new->isa('Mojo')) {
    $log->debug(qq{Routing to application "$class"});

    # Try to connect routes
    if (my $sub = $new->can('routes')) {
      my $r = $new->$sub;
      weaken $r->parent($old->match->endpoint)->{parent} unless $r->parent;
    }
    $new->handler($old);
    $old->stash->{'mojo.routed'} = 1;
  }

  # Action
  elsif (my $method = $field->{action}) {
    if (!$self->is_hidden($method)) {
      $log->debug(qq{Routing to controller "$class" and action "$method"});

      if (my $sub = $new->can($method)) {
        $old->stash->{'mojo.routed'} = 1 if $last;
        return 1 if _action($app, $new, $sub, $last);
      }

      else { $log->debug('Action not found in controller') }
    }
    else { $log->debug(qq{Action "$method" is not allowed}) }
  }

  return undef;
}

sub _load {
  my ($self, $app) = @_;

  # Load unless already loaded
  return 1 if $self->{loaded}{$app};
  if (my $e = load_class $app) { ref $e ? die $e : return undef }

  # Check base classes
  return 0 unless first { $app->isa($_) } @{$self->base_classes};
  return $self->{loaded}{$app} = 1;
}

sub _render {
  my $c     = shift;
  my $stash = $c->stash;
  return if $stash->{'mojo.rendered'};
  $c->render_maybe or $stash->{'mojo.routed'} or $c->helpers->reply->not_found;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Routes - Always find your destination with routes

=head1 SYNOPSIS

  use Mojolicious::Routes;

  # Simple route
  my $r = Mojolicious::Routes->new;
  $r->route('/')->to(controller => 'blog', action => 'welcome');

  # More advanced routes
  my $blog = $r->under('/blog');
  $blog->get('/list')->to('blog#list');
  $blog->get('/:id' => [id => qr/\d+/])->to('blog#show', id => 23);
  $blog->patch(sub { shift->render(text => 'Go away!', status => 405) });

=head1 DESCRIPTION

L<Mojolicious::Routes> is the core of the L<Mojolicious> web framework.

See L<Mojolicious::Guides::Routing> for more.

=head1 ATTRIBUTES

L<Mojolicious::Routes> inherits all attributes from
L<Mojolicious::Routes::Route> and implements the following new ones.

=head2 base_classes

  my $classes = $r->base_classes;
  $r          = $r->base_classes(['MyApp::Controller']);

Base classes used to identify controllers, defaults to
L<Mojolicious::Controller> and L<Mojo>.

=head2 cache

  my $cache = $r->cache;
  $r        = $r->cache(Mojo::Cache->new);

Routing cache, defaults to a L<Mojo::Cache> object.

=head2 conditions

  my $conditions = $r->conditions;
  $r             = $r->conditions({foo => sub {...}});

Contains all available conditions.

=head2 hidden

  my $hidden = $r->hidden;
  $r         = $r->hidden(['attr', 'has', 'new']);

Controller attributes and methods that are hidden from router, defaults to
C<attr>, C<has>, C<new> and C<tap>.

=head2 namespaces

  my $namespaces = $r->namespaces;
  $r             = $r->namespaces(['MyApp::Controller', 'MyApp']);

Namespaces to load controllers from.

  # Add another namespace to load controllers from
  push @{$r->namespaces}, 'MyApp::MyController';

=head2 shortcuts

  my $shortcuts = $r->shortcuts;
  $r            = $r->shortcuts({foo => sub {...}});

Contains all available shortcuts.

=head1 METHODS

L<Mojolicious::Routes> inherits all methods from L<Mojolicious::Routes::Route>
and implements the following new ones.

=head2 add_condition

  $r = $r->add_condition(foo => sub {...});

Register a condition.

  $r->add_condition(foo => sub {
    my ($route, $c, $captures, $arg) = @_;
    ...
    return 1;
  });

=head2 add_shortcut

  $r = $r->add_shortcut(foo => sub {...});

Register a shortcut.

  $r->add_shortcut(foo => sub {
    my ($route, @args) = @_;
    ...
  });

=head2 continue

  $r->continue(Mojolicious::Controller->new);

Continue dispatch chain and emit the hook L<Mojolicious/"around_action"> for
every action.

=head2 dispatch

  my $bool = $r->dispatch(Mojolicious::Controller->new);

Match routes with L</"match"> and dispatch with L</"continue">.

=head2 hide

  $r = $r->hide('foo', 'bar');

Hide controller attributes and methods from router.

=head2 is_hidden

  my $bool = $r->is_hidden('foo');

Check if controller attribute or method is hidden from router.

=head2 lookup

  my $route = $r->lookup('foo');

Find route by name with L<Mojolicious::Routes::Route/"find"> and cache all
results for future lookups.

=head2 match

  $r->match(Mojolicious::Controller->new);

Match routes with L<Mojolicious::Routes::Match>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
