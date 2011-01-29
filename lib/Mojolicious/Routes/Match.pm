package Mojolicious::Routes::Match;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Util qw/decode url_unescape/;
use Mojo::URL;
use Scalar::Util 'weaken';

has captures => sub { {} };
has stack    => sub { [] };
has [qw/endpoint is_websocket root/];

# "I'm Bender, baby, please insert liquor!"
sub new {
    my $self = shift->SUPER::new();

    # Path
    my $path = shift || Carp::croak(qq/Missing path/);
    url_unescape $path;
    decode 'UTF8', $path;
    $self->{_path} = $path;

    # Method
    $self->{_method} = shift || Carp::croak(qq/Missing method/);

    return $self;
}

# "Life can be hilariously cruel."
sub match {
    my ($self, $r, $c) = @_;

    # Shortcut
    return unless $r;

    # Dictionary
    my $dictionary = $self->{_dictionary} ||= $r->dictionary;

    # Root
    $self->root($r) unless $self->root;

    # Path
    my $path = $self->{_path};

    # Pattern
    my $pattern = $r->pattern;

    # Match
    my $captures = $pattern->shape_match(\$path);

    # No match
    return unless $captures;

    # Merge captures
    $captures = {%{$self->captures}, %$captures};
    $self->captures($captures);

    # Request method
    if ($r->{_via}) {
      return unless $self->_method($self->{_method}, $r->{_via});
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

    # Partial
    if (my $partial = $r->partial) {
        $captures->{$partial} = $path;
        $path = '';
    }
    $self->{_path} = $path;

    # Format
    if ($r->is_endpoint && !$pattern->format) {
        if ($path =~ /^\.([^\/]+)$/) {
            $captures->{format} = $1;
            $self->{_path}      = '';
        }
    }
    $captures->{format} ||= $pattern->format if $pattern->format;

    # Update stack
    if ($r->inline || ($r->is_endpoint && $self->_is_path_empty)) {
        push @{$self->stack}, {%$captures};
        delete $captures->{cb};
        delete $captures->{app};
    }

    # Waypoint match
    if ($r->block && $self->_is_path_empty) {
        $self->endpoint($r);
        return $self;
    }

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

    $self->endpoint($r) if $r->is_endpoint && $self->_is_path_empty;

    return $self;
}

# Method condition
sub _method {
    my $self   = shift;
    my $method = shift;
    my $valid  = shift;

    # Lowercase
    $method = lc($method);

    # Default
    $valid = ['get'] unless $valid;

    # Methods
    return unless $valid && ref $valid eq 'ARRAY';

    # Match
    $method = 'get' if $method eq 'head';
    for my $v (@$valid) {
        return 1 if $method eq $v;
    }

    # Nothing
    return;
}


sub url_for {
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

    # Captures
    my $captures = $self->captures;

    # Endpoint
    my $endpoint;

    # Current route
    if ($name && $name eq 'current' || !$name) {
        return undef unless $endpoint = $self->endpoint;
    }
    # Find
    else {
        $captures = {};
        return $name unless $endpoint = $self->_find_route($name);
    }

    # Merge values
    $values = {%$captures, format => undef, %$values};

    # Endpoint is websocket
    $self->is_websocket($endpoint->is_websocket);

    # Render
    return $endpoint->render('', $values);

}

sub _find_route {
    my ($self, $name) = @_;

    # Find endpoint
    my @children = ($self->root);
    while (my $child = shift @children) {

        # Match
        return $child if ($child->name || '') eq $name;

        # Append
        push @children, @{$child->children};
    }

    # Not found
    return;
}

sub _is_path_empty {
    my $self = shift;
    return 1 if !length $self->{_path} || $self->{_path} eq '/';
    return;
}

1;
__END__

=head1 NAME

Mojolicious::Routes::Match - Routes Visitor

=head1 SYNOPSIS

    use Mojolicious::Routes::Match;

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

=head2 C<is_websocket>

    my $is_websocket = $m->is_websocket;

Returns true if endpoint leads to a WebSocket.

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

    my $m = Mojolicious::Routes::Match->new('/foo/bar.html', 'post');

Construct a new match object. Expects the path and request method.

=head2 C<match>

    $m->match(Mojolicious::Routes->new, Mojolicious::Controller->new);

Match against a routes tree. A controller object can be passed as a second
argument which will then be passed to conditions (defined via C<over> command
in L<Mojolicious::Routes>).

=head2 C<url_for>

    my $url = $m->url_for;
    my $url = $m->url_for(foo => 'bar');
    my $url = $m->url_for({foo => 'bar'});
    my $url = $m->url_for('named');
    my $url = $m->url_for('named', foo => 'bar');
    my $url = $m->url_for('named', {foo => 'bar'});

Render matching route with parameters into a L<Mojo::URL> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
