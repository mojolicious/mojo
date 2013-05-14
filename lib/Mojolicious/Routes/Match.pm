package Mojolicious::Routes::Match;
use Mojo::Base -base;

has [qw(endpoint root)];
has stack => sub { [] };

sub match { $_[0]->_match($_[0]->root, $_[1], $_[2]) }

sub path_for {
  my ($self, $name, %values) = (shift, _values(@_));

  # Current route
  my $endpoint;
  if ($name && $name eq 'current' || !$name) {
    return unless $endpoint = $self->endpoint;
  }

  # Find endpoint
  else { return $name unless $endpoint = $self->root->lookup($name) }

  # Merge values (clear format)
  my $captures = $self->stack->[-1] || {};
  %values = (%$captures, format => undef, %values);
  my $pattern = $endpoint->pattern;
  $values{format}
    = defined $captures->{format}
    ? $captures->{format}
    : $pattern->defaults->{format}
    if $pattern->constraints->{format};

  my $path = $endpoint->render('', \%values);
  return wantarray ? ($path, $endpoint->has_websocket) : $path;
}

sub _match {
  my ($self, $r, $c, $options) = @_;

  # Pattern
  my $path = $options->{path};
  return
    unless my $captures = $r->pattern->match_partial(\$path, $r->is_endpoint);
  local $options->{path} = $path;
  $captures = $self->{captures} = {%{$self->{captures} || {}}, %$captures};

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

  # Partial
  my $empty = !length $path || $path eq '/';
  if ($r->partial) {
    $captures->{path} = $path;
    $self->endpoint($r);
    $empty = 1;
  }

  # Endpoint (or bridge)
  my $endpoint = $r->is_endpoint;
  if (($endpoint && $empty) || $r->inline) {
    push @{$self->stack}, {%$captures};
    return $self->endpoint($r) if $endpoint && $empty;
    delete $captures->{$_} for qw(app cb);
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

sub _values {

  # Hash or name (one)
  return ref $_[0] eq 'HASH' ? (undef, %{shift()}) : @_ if @_ == 1;

  # Name and values (odd)
  return shift, @_ if @_ % 2;

  # Name and hash or just values (even)
  return ref $_[1] eq 'HASH' ? (shift, %{shift()}) : (undef, @_);
}

1;

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
  say $match->path_for;
  say $match->path_for(action => 'baz');

=head1 DESCRIPTION

L<Mojolicious::Routes::Match> finds routes in L<Mojolicious::Routes>
structures.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Match> implements the following attributes.

=head2 endpoint

  my $endpoint = $match->endpoint;
  $match       = $match->endpoint(Mojolicious::Routes::Route->new);

The route endpoint that matched.

=head2 root

  my $root = $match->root;
  $match   = $match->root(Mojolicious::Routes->new);

The root of the route structure.

=head2 stack

  my $stack = $match->stack;
  $match    = $match->stack([{foo => 'bar'}]);

Captured parameters with nesting history.

=head1 METHODS

L<Mojolicious::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 match

  $match->match(Mojolicious::Controller->new, {method => 'GET', path => '/'});

Match controller and options against C<root> to find appropriate C<endpoint>.

=head2 path_for

  my $path        = $match->path_for;
  my $path        = $match->path_for(foo => 'bar');
  my $path        = $match->path_for({foo => 'bar'});
  my $path        = $match->path_for('named');
  my $path        = $match->path_for('named', foo => 'bar');
  my $path        = $match->path_for('named', {foo => 'bar'});
  my ($path, $ws) = $match->path_for;
  my ($path, $ws) = $match->path_for(foo => 'bar');
  my ($path, $ws) = $match->path_for({foo => 'bar'});
  my ($path, $ws) = $match->path_for('named');
  my ($path, $ws) = $match->path_for('named', foo => 'bar');
  my ($path, $ws) = $match->path_for('named', {foo => 'bar'});

Render matching route with parameters into path.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
