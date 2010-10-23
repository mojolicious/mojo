package MojoX::Routes;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::URL;
use MojoX::Routes::Pattern;
use Scalar::Util 'weaken';

__PACKAGE__->attr([qw/block inline parent partial/]);
__PACKAGE__->attr([qw/children conditions/] => sub { [] });
__PACKAGE__->attr(dictionary                => sub { {} });
__PACKAGE__->attr(pattern => sub { MojoX::Routes::Pattern->new });

# Yet thanks to my trusty safety sphere,
# I sublibed with only tribial brain dablage.
sub new {
    my $self = shift->SUPER::new();

    # Parse
    $self->parse(@_);

    # Method condition
    $self->add_condition(
        method => sub {
            my ($r, $c, $captures, $methods) = @_;

            # Methods
            return unless $methods && ref $methods eq 'ARRAY';

            # Match
            my $m = lc $c->req->method;
            $m = 'get' if $m eq 'head';
            for my $method (@$methods) {
                return 1 if $method eq $m;
            }

            # Nothing
            return;
        }
    );

    # WebSocket condition
    $self->add_condition(
        websocket => sub {
            my ($r, $c, $captures) = @_;

            # WebSocket
            return 1 if $c->tx->is_websocket;

            # Not a WebSocket
            return;
        }
    );

    return $self;
}

sub add_child {
    my ($self, $route) = @_;

    # We are the parent
    $route->parent($self);
    weaken $route->{parent};

    # Add to tree
    push @{$self->children}, $route;

    return $self;
}

sub add_condition {
    my ($self, $name, $condition) = @_;

    # Add
    $self->dictionary->{$name} = $condition;

    return $self;
}

sub bridge { shift->route(@_)->inline(1) }

sub is_endpoint {
    my $self = shift;
    return   if $self->inline;
    return 1 if $self->block;
    return   if @{$self->children};
    return 1;
}

sub is_websocket {
    my $self = shift;
    return 1 if $self->{_websocket};
    if (my $parent = $self->parent) { return $parent->is_websocket }
    return;
}

# Dr. Zoidberg, can you note the time and declare the patient legally dead?
# Can I! That’s my specialty!
sub name {
    my ($self, $name) = @_;

    # New name
    if (defined $name) {

        # Generate
        if ($name eq '*') {
            $name = $self->pattern->pattern;
            $name =~ s/\W+//g;
        }
        $self->{_name} = $name;

        return $self;
    }

    return $self->{_name};
}

sub over {
    my $self = shift;

    # Shortcut
    return $self unless @_;

    # Conditions
    my $conditions = ref $_[0] eq 'ARRAY' ? $_[0] : [@_];
    push @{$self->conditions}, @$conditions;

    return $self;
}

sub parse {
    my $self = shift;

    # Pattern does the real work
    $self->pattern->parse(@_);

    return $self;
}

sub render {
    my ($self, $path, $values) = @_;

    # Path prefix
    my $prefix = $self->pattern->render($values);
    $path = $prefix . $path unless $prefix eq '/';

    # Make sure there is always a root
    $path = '/' if !$path && !$self->parent;

    # Format
    if ((my $format = $values->{format}) && !$self->parent) {
        $path .= ".$format" unless $path =~ /\.[^\/]+$/;
    }

    # Parent
    $path = $self->parent->render($path, $values) if $self->parent;

    return $path;
}

# Morbo forget how you spell that letter that looks like a man wearing a hat.
# Hello, tiny man. I will destroy you!
sub route {
    my $self = shift;

    # New route
    my $route = $self->new(@_);
    $self->add_child($route);

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

    # Shortcut
    if ($shortcut) {

        # App
        if (ref $shortcut || $shortcut =~ /^[\w\:]+$/) {
            $defaults->{app} = $shortcut;
        }

        # Controller and action
        elsif ($shortcut =~ /^([\w\-]+)?\#(\w+)?$/) {
            $defaults->{controller} = $1 if defined $1;
            $defaults->{action}     = $2 if defined $2;
        }
    }

    # Pattern
    my $pattern = $self->pattern;

    # Defaults
    my $old = $pattern->defaults;
    $pattern->defaults({%$old, %$defaults}) if $defaults;

    return $self;
}

sub to_string {
    my $self = shift;
    my $pattern = $self->parent ? $self->parent->to_string : '';
    $pattern .= $self->pattern->pattern if $self->pattern->pattern;
    return $pattern;
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
    $self->{_websocket} = 1;

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

    # Nested route for two actions sharing the same "controller" parameter
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

=head1 ATTRIBUTES

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

=head2 C<parent>

    my $parent = $r->parent;
    $r         = $r->parent(MojoX::Routes->new);

The parent of this route, used for nesting routes.

=head2 C<partial>

    my $partial = $r->partial;
    $r          = $r->partial('path');

Route has no specific end, remaining characters will be captured with the
partial name.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<pattern>

    my $pattern = $r->pattern;
    $r          = $r->pattern(MojoX::Routes::Pattern->new);

Pattern for this route, by default a L<MojoX::Routes::Pattern> object and
used for matching.

=head1 METHODS

L<MojoX::Routes> inherits all methods from L<Mojo::Base> and implements the
following ones.

=head2 C<new>

    my $r = MojoX::Routes->new;
    my $r = MojoX::Routes->new('/:controller/:action');

Construct a new route object.

=head2 C<add_child>

    $r = $r->add_child(MojoX::Route->new);

Add a new child to this route.

=head2 C<add_condition>

    $r = $r->add_condition(foo => sub { ... });

Add a new condition for this route.

=head2 C<bridge>

    my $bridge = $r->bridge;
    my $bridge = $r->bridge('/:controller/:action');

Add a new bridge to this route as a nested child.

=head2 C<is_endpoint>

    my $is_endpoint = $r->is_endpoint;

Returns true if this route qualifies as an endpoint.

=head2 C<is_websocket>

    my $is_websocket = $r->is_websocket;

Returns true if this route leads to a WebSocket.

=head2 C<name>

    my $name = $r->name;
    $r       = $r->name('foo');
    $r       = $r->name('*');

The name of this route, the special value C<*> will generate a name based on
the route pattern.
Note that the name C<current> is reserved for refering to the current route.

=head2 C<over>

    $r = $r->over(foo => qr/\w+/);

Apply condition parameters to this route.

=head2 C<parse>

    $r = $r->parse('/:controller/:action');

Parse a pattern.

=head2 C<render>

    my $path = $r->render($path);
    my $path = $r->render($path, {foo => 'bar'});

Render route with parameters into a path.

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
    $r = $r->to($app);
    $r = $r->to($app, foo => 'bar');
    $r = $r->to($app, {foo => 'bar'});
    $r = $r->to('MyApp');
    $r = $r->to('MyApp', foo => 'bar');
    $r = $r->to('MyApp', {foo => 'bar'});

Set default parameters for this route.

=head2 C<to_string>

    my $string = $r->to_string;

Stringifies the whole route.

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
