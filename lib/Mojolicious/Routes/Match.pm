package Mojolicious::Routes::Match;
use Mojo::Base -base;

use Mojo::Util qw/decode url_unescape/;

has captures => sub { {} };
has stack    => sub { [] };
has [qw/endpoint root/];

# "I'm Bender, baby, please insert liquor!"
sub new {
  my $self = shift->SUPER::new();

  # Method
  $self->{_method} = lc shift;

  # Path
  my $path = shift;
  url_unescape $path;
  my $backup = $path;
  decode 'UTF-8', $path;
  $path = $backup unless defined $path;
  $self->{_path} = $path;

  # WebSocket
  $self->{_websocket} = shift;

  return $self;
}

# "Life can be hilariously cruel."
sub match {
  my ($self, $r, $c) = @_;
  return unless $r;

  my $dictionary = $self->{_dictionary} ||= $r->dictionary;

  # Root
  $self->root($r) unless $self->root;

  my $path    = $self->{_path};
  my $pattern = $r->pattern;

  # Match
  my $captures = $pattern->shape_match(\$path);
  return unless $captures;
  $self->{_path} = $path;

  # Merge captures
  $captures = {%{$self->captures}, %$captures};
  $self->captures($captures);

  # Method
  if (my $methods = $r->via) {
    my $method = lc $self->{_method};
    $method = 'get' if $method eq 'head';
    my $found = 0;
    for my $m (@$methods) { ++$found and last if $method eq $m }
    return unless $found;
  }

  # Conditions
  my $conditions = $r->conditions;
  for (my $i = 0; $i < @$conditions; $i += 2) {
    my $name      = $conditions->[$i];
    my $value     = $conditions->[$i + 1];
    my $condition = $dictionary->{$name};

    # No condition
    return unless $condition;

    # Match
    return if !$condition->($r, $c, $captures, $value);
  }

  # WebSocket
  return if $r->is_websocket && !$self->{_websocket};

  # Empty path
  my $empty = !length $path || $path eq '/' ? 1 : 0;

  # Partial
  if (my $partial = $r->partial) {
    $captures->{$partial} = $path;
    $self->endpoint($r);
    $empty = 1;
  }

  # Format
  my $endpoint = $r->is_endpoint;
  if ($endpoint && !$pattern->format && $path =~ /^\/?\.([^\/]+)$/) {
    $captures->{format} = $1;
    $empty = 1;
  }
  $captures->{format} ||= $pattern->format if $pattern->format;

  # Update stack
  if ($r->inline || ($endpoint && $empty)) {
    push @{$self->stack}, {%$captures};
    delete $captures->{cb};
    delete $captures->{app};
  }

  # Waypoint match
  if ($r->block && $empty) {
    $self->endpoint($r);
    return $self;
  }

  # Endpoint
  return $self->endpoint($r) if $endpoint && $empty;

  # Match children
  my $snapshot = [@{$self->stack}];
  for my $child (@{$r->children}) {

    # Match
    $self->match($child, $c);

    # Endpoint found
    return $self if $self->endpoint;

    # Reset path
    $self->{_path} = $path;

    # Reset stack
    if ($r->parent) { $self->stack([@$snapshot]) }
    else {
      $self->captures({});
      $self->stack([]);
    }
  }

  return $self;
}

sub path_for {
  my $self   = shift;
  my $values = {};
  my $name   = undef;

  # Single argument
  if (@_ == 1) {

    # Hash
    $values = shift if ref $_[0] eq 'HASH';

    # Name
    $name = $_[0] if $_[0];
  }

  # Multiple arguments
  elsif (@_ > 1) {

    # Odd
    if (@_ % 2) {
      $name   = shift;
      $values = {@_};
    }

    # Even
    else {

      # Name and hashref
      if (ref $_[1] eq 'HASH') {
        $name   = shift;
        $values = shift;
      }

      # Just values
      else { $values = {@_} }

    }
  }

  # Current route
  my $captures = $self->captures;
  my $endpoint;
  if ($name && $name eq 'current' || !$name) {
    return undef unless $endpoint = $self->endpoint;
  }

  # Find endpoint
  else {
    $captures = {};

    # Find
    my @children = ($self->root);
    my $candidate;
    while (my $child = shift @children) {

      # Match
      if ($child->name eq $name) {
        $candidate = $child;
        last if $child->has_custom_name;
      }

      # Search too
      push @children, @{$child->children};
    }
    $endpoint = $candidate;

    # Nothing
    return $name unless $endpoint;
  }

  # Merge values
  $values = {%$captures, format => undef, %$values};

  # Render
  my $path = $endpoint->render('', $values);
  utf8::downgrade $path, 1;
  return wantarray ? ($path, $endpoint->has_websocket) : $path;
}

1;
__END__

=head1 NAME

Mojolicious::Routes::Match - Routes Visitor

=head1 SYNOPSIS

  use Mojolicious::Routes;
  use Mojolicious::Routes::Match;

  # Routes
  my $r = Mojolicious::Routes->new;
  $r->route('/foo')->to(action => 'foo');
  $r->route('/bar')->to(action => 'bar');

  # Match
  my $m = Mojolicious::Routes::Match->new(GET => '/bar');
  $m->match($r);
  print $m->captures->{action};

=head1 DESCRIPTION

L<Mojolicious::Routes::Match> is a visitor for L<Mojolicious::Routes>
structures.

=head1 ATTRIBUTES

L<Mojolicious::Routes::Match> implements the following attributes.

=head2 C<captures>

  my $captures = $m->captures;
  $m           = $m->captures({foo => 'bar'});

Captured parameters.

=head2 C<endpoint>

  my $endpoint = $m->endpoint;
  $m           = $m->endpoint(Mojolicious::Routes->new);

The routes endpoint that actually matched.

=head2 C<root>

  my $root = $m->root;
  $m       = $m->root($routes);

The root of the routes tree.

=head2 C<stack>

  my $stack = $m->stack;
  $m        = $m->stack([{foo => 'bar'}]);

Captured parameters with nesting history.

=head1 METHODS

L<Mojolicious::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<new>

  my $m = Mojolicious::Routes::Match->new(get => '/foo');
  my $m = Mojolicious::Routes::Match->new(get => '/foo', $ws);

Construct a new match object.

=head2 C<match>

  $m->match(Mojolicious::Routes->new, Mojolicious::Controller->new);

Match against a routes tree.

=head2 C<path_for>

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
