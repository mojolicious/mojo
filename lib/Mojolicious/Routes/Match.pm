package Mojolicious::Routes::Match;
use Mojo::Base -base;

has captures => sub { {} };
has [qw(endpoint root)];
has stack => sub { [] };

sub new {
  my $self = shift->SUPER::new;
  $self->{method}    = uc shift;
  $self->{path}      = shift;
  $self->{websocket} = shift;
  return $self;
}

sub match {
  my ($self, $r, $c) = @_;

  # Pattern
  $self->root($r) unless $self->root;
  my $path    = $self->{path};
  my $pattern = $r->pattern;
  return unless my $captures = $pattern->shape_match(\$path, $r->is_endpoint);
  $self->{path} = $path;
  $captures = {%{$self->captures}, %$captures};

  # Method
  if (my $methods = $r->via) {
    my $method = $self->{method} eq 'HEAD' ? 'GET' : $self->{method};
    return unless grep { $_ eq $method } @$methods;
  }

  # Conditions
  if (my $over = $r->over) {
    my $conditions = $self->{conditions} ||= $self->root->conditions;
    for (my $i = 0; $i < @$over; $i += 2) {
      return unless my $condition = $conditions->{$over->[$i]};
      return if !$condition->($r, $c, $captures, $over->[$i + 1]);
    }
  }

  # WebSocket
  return if $r->is_websocket && !$self->{websocket};

  # Partial
  my $empty = !length $path || $path eq '/';
  if ($r->partial) {
    $captures->{path} = $path;
    $self->endpoint($r);
    $empty = 1;
  }

  # Update stack
  $self->captures($captures);
  my $endpoint = $r->is_endpoint;
  if ($r->inline || ($endpoint && $empty)) {
    push @{$self->stack}, {%$captures};
    delete $captures->{$_} for qw(app cb);
  }

  # Endpoint
  return $self->endpoint($r) if $endpoint && $empty;

  # Match children
  my $snapshot = [@{$self->stack}];
  for my $child (@{$r->children}) {
    $self->match($child, $c);

    # Endpoint found
    return if $self->endpoint;

    # Reset
    $self->{path} = $path;
    if   ($r->parent) { $self->captures($captures)->stack([@$snapshot]) }
    else              { $self->captures({})->stack([]) }
  }
}

sub path_for {
  my $self = shift;

  # Single argument
  my (%values, $name);
  if (@_ == 1) {

    # Hash
    %values = %{shift()} if ref $_[0] eq 'HASH';

    # Name
    $name = $_[0] if $_[0];
  }

  # Multiple arguments
  elsif (@_ > 1) {

    # Odd
    if (@_ % 2) { ($name, %values) = (shift, @_) }

    # Even
    else {

      # Name and hash
      if (ref $_[1] eq 'HASH') { ($name, %values) = (shift, %{shift()}) }

      # Just values
      else { %values = @_ }

    }
  }

  # Current route
  my $endpoint;
  if ($name && $name eq 'current' || !$name) {
    return unless $endpoint = $self->endpoint;
  }

  # Find endpoint
  else { return $name unless $endpoint = $self->root->lookup($name) }

  # Merge values
  my $captures = $self->captures;
  %values = (%$captures, format => undef, %values);
  my $pattern = $endpoint->pattern;
  $values{format}
    = defined $captures->{format}
    ? $captures->{format}
    : $pattern->defaults->{format}
    if $pattern->constraints->{format};

  # Render
  my $path = $endpoint->render('', \%values);
  return wantarray ? ($path, $endpoint->has_websocket) : $path;
}

1;

=head1 NAME

Mojolicious::Routes::Match - Routes visitor

=head1 SYNOPSIS

  use Mojolicious::Controller;
  use Mojolicious::Routes;
  use Mojolicious::Routes::Match;

  # Routes
  my $r = Mojolicious::Routes->new;
  $r->get('/foo')->to(action => 'foo');
  $r->put('/bar')->to(action => 'bar');

  # Match
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(PUT => '/bar');
  $m->match($r, $c);
  say $m->captures->{action};

=head1 DESCRIPTION

L<Mojolicious::Routes::Match> is a visitor for L<Mojolicious::Routes>
structures.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Match> implements the following attributes.

=head2 captures

  my $captures = $m->captures;
  $m           = $m->captures({foo => 'bar'});

Captured parameters.

=head2 endpoint

  my $endpoint = $m->endpoint;
  $m           = $m->endpoint(Mojolicious::Routes->new);

The route endpoint that actually matched.

=head2 root

  my $root = $m->root;
  $m       = $m->root($routes);

The root of the route tree.

=head2 stack

  my $stack = $m->stack;
  $m        = $m->stack([{foo => 'bar'}]);

Captured parameters with nesting history.

=head1 METHODS

L<Mojolicious::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 new

  my $m = Mojolicious::Routes::Match->new(GET => '/foo');
  my $m = Mojolicious::Routes::Match->new(GET => '/foo', $ws);

Construct a new L<Mojolicious::Routes::Match> object.

=head2 match

  $m->match(Mojolicious::Routes->new, Mojolicious::Controller->new);

Match against a route tree.

=head2 path_for

  my $path        = $m->path_for;
  my $path        = $m->path_for(foo => 'bar');
  my $path        = $m->path_for({foo => 'bar'});
  my $path        = $m->path_for('named');
  my $path        = $m->path_for('named', foo => 'bar');
  my $path        = $m->path_for('named', {foo => 'bar'});
  my ($path, $ws) = $m->path_for;
  my ($path, $ws) = $m->path_for(foo => 'bar');
  my ($path, $ws) = $m->path_for({foo => 'bar'});
  my ($path, $ws) = $m->path_for('named');
  my ($path, $ws) = $m->path_for('named', foo => 'bar');
  my ($path, $ws) = $m->path_for('named', {foo => 'bar'});

Render matching route with parameters into path.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
