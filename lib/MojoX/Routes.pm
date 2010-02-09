# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Routes;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::URL;
use MojoX::Routes::Match;
use MojoX::Routes::Pattern;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJOX_ROUTES_DEBUG} || 0;

__PACKAGE__->attr([qw/block inline name parent/]);
__PACKAGE__->attr([qw/children conditions/] => sub { [] });
__PACKAGE__->attr(dictionary                => sub { {} });
__PACKAGE__->attr(pattern => sub { MojoX::Routes::Pattern->new });

sub new {
    my $self = shift->SUPER::new();

    # Parse
    $self->parse(@_);

    # Method condition
    $self->add_condition(
        method => sub {
            my ($r, $tx, $captures, $methods) = @_;

            # Methods
            return unless $methods && ref $methods eq 'ARRAY';

            # Match
            for my $method (@$methods) {
                return $captures if $method eq lc $tx->req->method;
            }

            # Nothing
            return;
        }
    );

    # WebSocket condition
    $self->add_condition(
        websocket => sub {
            my ($r, $tx, $captures) = @_;

            # WebSocket
            return $captures if $tx->is_websocket;

            # Not a WebSocket
            return;
        }
    );

    return $self;
}

sub add_condition {
    my $self = shift;

    # Merge
    my $dictionary = ref $_[0] ? $_[0] : {@_};
    $dictionary = {%{$self->dictionary}, %$dictionary};
    $self->dictionary($dictionary);

    return $self;
}

sub bridge { shift->route(@_)->inline(1) }

sub find_route {
    my ($self, $name) = @_;

    # Find endpoint
    my @children = ($self);
    while (my $child = shift @children) {

        # Match
        return $child if ($child->name || '') eq $name;

        # Append
        push @children, @{$child->children};
    }

    # Not found
    return;
}

sub is_endpoint {
    my $self = shift;
    return   if $self->inline;
    return 1 if $self->block;
    return   if @{$self->children};
    return 1;
}

# Life can be hilariously cruel.
sub match {
    my $self  = shift;
    my $match = shift;

    # Shortcut
    return unless $match;

    # Match object
    $match = MojoX::Routes::Match->new($match)->dictionary($self->dictionary)
      unless ref $match && $match->isa('MojoX::Routes::Match');

    # Root
    $match->root($self) unless $match->root;

    # Conditions
    for (my $i = 0; $i < @{$self->conditions}; $i += 2) {
        my $name      = $self->conditions->[$i];
        my $value     = $self->conditions->[$i + 1];
        my $condition = $self->dictionary->{$name};

        # No condition
        return unless $condition;

        # Match
        my $captures =
          $condition->($self, $match->tx, $match->captures, $value);

        # Matched
        return unless $captures && ref $captures eq 'HASH';

        # Merge captures
        $match->captures($captures);
    }

    # Path
    my $path = $match->path;

    # Match
    my $captures = $self->pattern->shape_match(\$path);

    $match->path($path);

    return unless $captures;

    # Merge captures
    $captures = {%{$match->captures}, %$captures};
    $match->captures($captures);

    # Format
    if ($self->is_endpoint && !$self->pattern->format) {
        if ($path =~ /^\.([^\/]+)$/) {
            $match->captures->{format} = $1;
            $match->path('');
        }
    }
    $match->captures->{format} = $self->pattern->format
      if $self->pattern->format;

    # Update stack
    push @{$match->stack}, $captures
      if $self->inline || ($self->is_endpoint && $match->is_path_empty);

    # Waypoint match
    if ($self->block && $match->is_path_empty) {
        $match->endpoint($self);
        return $match;
    }

    # Match children
    my $snapshot = [@{$match->stack}];
    for my $child (@{$self->children}) {

        # Match
        $child->match($match);

        # Endpoint found
        return $match if $match->endpoint;

        # Reset path
        $match->path($path);

        # Reset stack
        if ($self->parent) { $match->stack($snapshot) }
        else {
            $match->captures({});
            $match->stack([]);
        }
    }

    $match->endpoint($self) if $self->is_endpoint && $match->is_path_empty;

    return $match;
}

sub over {
    my $self = shift;

    # Shortcut
    return $self unless @_;

    # Conditions
    my $conditions = ref $_[0] eq 'ARRAY' ? $_[0] : [@_];
    $self->conditions($conditions);

    return $self;
}

sub parse {
    my $self = shift;

    # Pattern does the real work
    $self->pattern->parse(@_);

    return $self;
}

sub route {
    my $self = shift;

    # New route
    my $route = $self->new(@_);

    # Inherit conditions
    $route->add_condition($self->dictionary);

    # We are the parent
    $route->parent($self);
    weaken $route->{parent};

    # Add to tree
    push @{$self->children}, $route;

    return $route;
}

sub to {
    my $self = shift;

    # Shortcut
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
            if (ref $_[1] eq 'HASH') {
                $shortcut = shift;
                $defaults = shift;
            }

            # Just defaults
            else { $defaults = {@_} }
        }
    }

    # Controller and action
    if ($shortcut && $shortcut =~ /^([\w\-]+)?\#(\w+)?$/) {
        $defaults->{controller} = $1 if defined $1;
        $defaults->{action}     = $2 if defined $2;
    }

    # Defaults
    $self->pattern->defaults($defaults) if $defaults;

    return $self;
}

sub to_string {
    my $self = shift;
    my $pattern = $self->parent ? $self->parent->to_string : '';
    $pattern .= $self->pattern->pattern if $self->pattern->pattern;
    return $pattern;
}

sub url_for {
    my ($self, $url, $values) = @_;

    # Path prefix
    my $path   = $url->path->to_string;
    my $prefix = $self->pattern->render($values);
    $path = $prefix . $path unless $prefix eq '/';

    # Make sure there is always a root
    $path = '/' if !$path && !$self->parent;

    # Format
    if ((my $format = $values->{format}) && !$self->parent) {
        $path .= ".$format" unless $path =~ /\.[^\/]+$/;
    }

    $url->path->parse($path);

    $self->parent->url_for($url, $values) if $self->parent;

    return $url;
}

sub via {
    my $self = shift;

    # Methods
    my $methods = ref $_[0] ? $_[0] : [@_];

    # Shortcut
    return $self unless @$methods;

    # Condition
    push @{$self->conditions}, method => [map { lc $_ } @$methods];

    return $self;
}

sub waypoint { shift->route(@_)->block(1) }

sub websocket {
    my $self = shift;

    # Condition
    push @{$self->conditions}, websocket => 1;

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Routes - Always Find Your Destination With Routes

=head1 SYNOPSIS

    use MojoX::Routes;

    # New routes tree
    my $r = MojoX::Routes->new;

    # Normal route matching "/articles" with parameters "controller" and
    # "action"
    $r->route('/articles')->to(controller => 'article', action => 'list');

    # Route with a placeholder matching everything but "/" and "."
    $r->route('/:controller')->to(action => 'list');

    # Route with a placeholder and regex constraint
    $r->route('/articles/:id', id => qr/\d+/)
      ->to(controller => 'article', action => 'view');

    # Route with an optional parameter "year"
    $r->route('/archive/:year')
      ->to(controller => 'archive', action => 'list', year => undef);

    # Nested route for two actions sharing the same "controller" paramater
    my $books = $r->route('/books/:id')->to(controller => 'book');
    $books->route('/edit')->to(action => 'edit');
    $books->route('/delete')->to(action => 'delete');

    # Bridges can be used to chain multiple routes
    $r->bridge->to(controller => 'foo', action =>'auth')
      ->route('/blog')->to(action => 'list');

    # Waypoints are similar to bridges and nested routes but can also match
    # if they are not the actual endpoint of the whole route
    my $b = $r->waypoint('/books')->to(controller => 'books', action => 'list');
    $b->route('/:id', id => qr/\d+/)->to(action => 'view');

=head1 DESCRIPTION

L<MojoX::Routes> is a very powerful implementation of the famous routes
pattern and the core of the L<Mojolicious> web framework.

=head2 ATTRIBUTES

L<MojoX::Routes> implements the following attributes.

=head2 C<block>

    my $block = $r->block;
    $r        = $r->block(1);

Allow this route to match even if it's not an endpoint, used for waypoints.

=head2 C<children>

    my $children = $r->children;
    $r           = $r->children([MojoX::Routes->new]);

The children of this routes object, used for nesting routes.

=head2 C<conditions>

    my $conditions  = $r->conditions;
    $r              = $r->conditions([foo => qr/\w+/]);

Contains condition parameters for this route, used for C<over>.

=head2 C<dictionary>

    my $dictionary = $r->dictionary;
    $r             = $r->dictionary({foo => sub { ... }});

Contains all available conditions for this route.
There are currently two conditions built in, C<method> and C<websocket>.

=head2 C<inline>

    my $inline = $r->inline;
    $r         = $r->inline(1);

Allow C<bridge> semantics for this route.

=head2 C<name>

    my $name = $r->name;
    $r       = $r->name('foo');

The name of this route.

=head2 C<parent>

    my $parent = $r->parent;
    $r         = $r->parent(MojoX::Routes->new);

The parent of this route, used for nesting routes.

=head2 C<pattern>

    my $pattern = $r->pattern;
    $r          = $r->pattern(MojoX::Routes::Pattern->new);

Pattern for this route, by default a L<MojoX::Routes::Pattern> object and
used for matching.

=head1 METHODS

L<MojoX::Routes> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<new>

    my $r = MojoX::Routes->new;
    my $r = MojoX::Routes->new('/:controller/:action');

Construct a new route object.

=head2 C<add_condition>

    $r = $r->add_condition(foo => sub { ... });

Add a new condition for this route.

=head2 C<bridge>

    my $bridge = $r->bridge;
    my $bridge = $r->bridge('/:controller/:action');

Add a new bridge to this route as a nested child.

=head2 C<find_route>

    my $route = $r->find_route('some_route');

Find a route by name in the whole routes tree.

=head2 C<is_endpoint>

    my $is_endpoint = $r->is_endpoint;

Returns true if this route qualifies as an endpoint.

=head2 C<match>

    $match = $r->match($match);
    my $match = $r->match(Mojo::Transaction::HTTP->new);

Match the whole routes tree against a L<MojoX::Routes::Match> or
L<Mojo::Transaction::HTTP> object.

=head2 C<over>

    $r = $r->over(foo => qr/\w+/);
    $r = $r->over({foo => qr/\w+/});

Apply condition parameters to this route.

=head2 C<parse>

    $r = $r->parse('/:controller/:action');

Parse a pattern.

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

Set default parameters for this route.

=head2 C<to_string>

    my $string = $r->to_string;

Stringifies the whole route.

=head2 C<url_for>

    my $url = $r->url_for($url);
    my $url = $r->url_for($url, {foo => 'bar'});

Render route with parameters into a L<Mojo::URL> object.

=head2 C<via>

    $r = $r->via('get');
    $r = $r->via(qw/get post/);
    $r = $r->via([qw/get post/]);

Apply C<method> constraint to this route.

=head2 C<waypoint>

    my $route = $r->waypoint('/:c/:a', a => qr/\w+/);

Add a waypoint to this route as nested child.

=head2 C<websocket>

    $route->websocket;

Apply C<websocket> constraint to this route.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
