package Mojolicious::Routes::Match;
use Mojo::Base -base;

use Mojo::Util;

has [qw(endpoint root)];
has position => 0;
has stack => sub { [] };

sub find { $_[0]->_match($_[0]->root, $_[1], $_[2]) }

sub path_for {
  my ($self, $name, %values) = (shift, Mojo::Util::_options(@_));

  # Current route
  my $route;
  if (!$name || $name eq 'current') {
    return {} unless $route = $self->endpoint;
  }

  # Find endpoint
  else { return {path => $name} unless $route = $self->root->lookup($name) }

  # Merge values (clear format)
  my $captures = $self->stack->[-1] || {};
  %values = (%$captures, format => undef, %values);
  my $pattern = $route->pattern;
  $values{format}
    //= defined $captures->{format}
    ? $captures->{format}
    : $pattern->defaults->{format}
    if $pattern->constraints->{format};

  my $path = $route->render(\%values);
  return {path => $path, websocket => $route->has_websocket};
}

sub _match {
  my ($self, $r, $c, $options) = @_;

  # Pattern
  my $path    = $options->{path};
  my $partial = $r->partial;
  my $detect  = (my $endpoint = $r->is_endpoint) && !$partial;
  return undef
    unless my $captures = $r->pattern->match_partial(\$path, $detect);
  local $options->{path} = $path;
  local @{$self->{captures} ||= {}}{keys %$captures} = values %$captures;
  $captures = $self->{captures};

  # Method
  my $methods = $r->via;
  return undef if $methods && !grep { $_ eq $options->{method} } @$methods;

  # Conditions
  if (my $over = $r->over) {
    my $conditions = $self->{conditions} ||= $self->root->conditions;
    for (my $i = 0; $i < @$over; $i += 2) {
      return undef unless my $condition = $conditions->{$over->[$i]};
      return undef if !$condition->($r, $c, $captures, $over->[$i + 1]);
    }
  }

  # WebSocket
  return undef if $r->is_websocket && !$options->{websocket};

  # Partial
  my $empty = !length $path || $path eq '/';
  if ($partial) {
    $captures->{path} = $path;
    $self->endpoint($r);
    $empty = 1;
  }

  # Endpoint (or intermediate destination)
  if (($endpoint && $empty) || $r->inline) {
    push @{$self->stack}, {%$captures};
    if ($endpoint && $empty) {
      my $format = $captures->{format};
      if ($format) { $_->{format} = $format for @{$self->stack} }
      return !!$self->endpoint($r);
    }
    delete @$captures{qw(app cb)};
  }

  # Match children
  my @snapshot = $r->parent ? ([@{$self->stack}], $captures) : ([], {});
  for my $child (@{$r->children}) {
    return 1 if $self->_match($child, $c, $options);
    $self->stack([@{$snapshot[0]}])->{captures} = $snapshot[1];
  }
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Routes::Match - Find routes

=head1 SYNOPSIS

  use Mojolicious::Controller;
  use Mojolicious::Routes;
  use Mojolicious::Routes::Match;

  # Routes
  my $r = Mojolicious::Routes->new;
  $r->get('/:controller/:action');
  $r->put('/:controller/:action');

  # Match
  my $c = Mojolicious::Controller->new;
  my $match = Mojolicious::Routes::Match->new(root => $r);
  $match->find($c => {method => 'PUT', path => '/foo/bar'});
  say $match->stack->[0]{controller};
  say $match->stack->[0]{action};

  # Render
  say $match->path_for->{path};
  say $match->path_for(action => 'baz')->{path};

=head1 DESCRIPTION

L<Mojolicious::Routes::Match> finds routes in L<Mojolicious::Routes>
structures.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Match> implements the following attributes.

=head2 endpoint

  my $route = $match->endpoint;
  $match    = $match->endpoint(Mojolicious::Routes::Route->new);

The route endpoint that matched, usually a L<Mojolicious::Routes::Route>
object.

=head2 position

  my $position = $match->position;
  $match       = $match->position(2);

Current position on the L</"stack">, defaults to C<0>.

=head2 root

  my $root = $match->root;
  $match   = $match->root(Mojolicious::Routes->new);

The root of the route structure, usually a L<Mojolicious::Routes> object.

=head2 stack

  my $stack = $match->stack;
  $match    = $match->stack([{action => 'foo'}, {action => 'bar'}]);

Captured parameters with nesting history.

=head1 METHODS

L<Mojolicious::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 find

  $match->find(Mojolicious::Controller->new, {method => 'GET', path => '/'});

Match controller and options against L</"root"> to find an appropriate
L</"endpoint">.

=head2 path_for

  my $info = $match->path_for;
  my $info = $match->path_for(foo => 'bar');
  my $info = $match->path_for({foo => 'bar'});
  my $info = $match->path_for('named');
  my $info = $match->path_for('named', foo => 'bar');
  my $info = $match->path_for('named', {foo => 'bar'});

Render matching route with parameters into path.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
