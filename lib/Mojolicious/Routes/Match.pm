package Mojolicious::Routes::Match;
use Mojo::Base -base;

use Mojo::Util;

has current => 0;
has [qw(endpoint root)];
has stack => sub { [] };

sub match { $_[0]->_match($_[0]->root, $_[1], $_[2]) }

sub path_for {
  my ($self, $name, %values) = (shift, Mojo::Util::_options(@_));

  # Current route
  my $endpoint;
  if ($name && $name eq 'current' || !$name) {
    return {} unless $endpoint = $self->endpoint;
  }

  # Find endpoint
  else { return {path => $name} unless $endpoint = $self->root->lookup($name) }

  # Merge values (clear format)
  my $captures = $self->stack->[-1] || {};
  %values = (%$captures, format => undef, %values);
  my $pattern = $endpoint->pattern;
  $values{format}
    //= defined $captures->{format}
    ? $captures->{format}
    : $pattern->defaults->{format}
    if $pattern->constraints->{format};

  my $path = $endpoint->render('', \%values);
  return {path => $path, websocket => $endpoint->has_websocket};
}

sub _match {
  my ($self, $r, $c, $options) = @_;

  # Pattern
  my $path    = $options->{path};
  my $partial = $r->partial;
  my $detect  = (my $endpoint = $r->is_endpoint) && !$partial;
  return unless my $captures = $r->pattern->match_partial(\$path, $detect);
  local $options->{path} = $path;

  # Method
  my $methods = $r->via;
  return if $methods && !grep { $_ eq $options->{method} } @$methods;

  # Conditions
  if (my $over = $r->over) {
    my $conditions = $self->{conditions} ||= $self->root->conditions;
    for (my $i = 0; $i < @$over; $i += 2) {
      return unless my $condition = $conditions->{$over->[$i]};
      return if !$condition->($r, $c, $captures, $over->[$i + 1]);
    }
  }

  # WebSocket
  return if $r->is_websocket && !$options->{websocket};

  # Merge after everything matched
  @{$self->{captures} ||= {}}{keys %$captures} = values %$captures;
  $captures = $self->{captures};

  # Partial
  my $empty = !length $path || $path eq '/';
  if ($partial) {
    $captures->{path} = $path;
    $self->endpoint($r);
    $empty = 1;
  }

  # Endpoint (or bridge)
  if (($endpoint && $empty) || $r->inline) {
    push @{$self->stack}, {%$captures};
    if ($endpoint && $empty) {
      my $format = $captures->{format};
      if ($format) { $_->{format} = $format for @{$self->stack} }
      return $self->endpoint($r);
    }
    delete @$captures{qw(app cb)};
  }

  # Match children
  my $snapshot = [@{$self->stack}];
  for my $child (@{$r->children}) {
    $self->_match($child, $c, $options);

    # Endpoint found
    return if $self->endpoint;

    # Reset
    if   ($r->parent) { $self->stack([@$snapshot])->{captures} = $captures }
    else              { $self->stack([])->{captures}           = {} }
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
  $match->match($c => {method => 'PUT', path => '/foo/bar'});
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

=head2 current

  my $current = $match->current;
  $match      = $match->current(2);

Current position on the L</"stack">, defaults to C<0>.

=head2 endpoint

  my $endpoint = $match->endpoint;
  $match       = $match->endpoint(Mojolicious::Routes::Route->new);

The route endpoint that matched, usually a L<Mojolicious::Routes::Route>
objects.

=head2 root

  my $root = $match->root;
  $match   = $match->root(Mojolicious::Routes->new);

The root of the route structure, usually a L<Mojolicious::Routes> object.

=head2 stack

  my $stack = $match->stack;
  $match    = $match->stack([{foo => 'bar'}]);

Captured parameters with nesting history.

=head1 METHODS

L<Mojolicious::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 match

  $match->match(Mojolicious::Controller->new, {method => 'GET', path => '/'});

Match controller and options against L</"root"> to find appropriate
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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
