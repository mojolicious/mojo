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

            # Methods?
            return unless $methods && ref $methods eq 'ARRAY';

            # Match
            for my $method (@$methods) {
                return $captures if $method eq lc $tx->req->method;
            }

            # Nothing
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

        # Matched?
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
    if ($self->inline || ($self->is_endpoint && $match->is_path_empty)) {
        push @{$match->stack}, $captures;
    }

    # Waypoint match
    if ($self->block && $match->is_path_empty) {
        push @{$match->stack}, $captures;
        $match->endpoint($self);
        return $self;
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
    my ($defaults, $shortcut);
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
    if ($shortcut && $shortcut =~ /^(\w+)\#(\w+)$/) {
        $defaults->{controller} = $1;
        $defaults->{action}     = $2;
    }

    # Defaults
    $self->pattern->defaults($defaults);

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

1;
__END__

=head1 NAME

MojoX::Routes - Routes

=head1 SYNOPSIS

    use MojoX::Routes;

    my $routes = MojoX::Routes->new;

=head1 DESCRIPTION

L<MojoX::Routes> is a routes implementation.

=head2 ATTRIBUTES

L<MojoX::Routes> implements the following attributes.

=head2 C<block>

    my $block = $routes->block;
    $routes   = $routes->block(1);

=head2 C<children>

    my $children = $routes->children;
    $routes      = $routes->children([MojoX::Routes->new]);

=head2 C<conditions>

    my $conditions  = $routes->conditions;
    $routes         = $routes->conditions([foo => qr/\w+/]);

=head2 C<dictionary>

    my $dictionary = $routes->dictionary;
    $routes        = $routes->dictionary({foo => sub { ... }});

=head2 C<inline>

    my $inline = $routes->inline;
    $routes    = $routes->inline(1);

=head2 C<name>

    my $name = $routes->name;
    $routes  = $routes->name('foo');

=head2 C<parent>

    my $parent = $routes->parent;
    $routes    = $routes->parent(MojoX::Routes->new);

=head2 C<pattern>

    my $pattern = $routes->pattern;
    $routes     = $routes->pattern(MojoX::Routes::Pattern->new);

=head1 METHODS

L<MojoX::Routes> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<new>

    my $routes = MojoX::Routes->new;
    my $routes = MojoX::Routes->new('/:controller/:action');

=head2 C<add_condition>

    $routes = $routes->add_condition(foo => sub { ... });

=head2 C<bridge>

    my $bridge = $routes->bridge;
    my $bridge = $routes->bridge('/:controller/:action');

=head2 C<to>

    my $to  = $routes->to;
    $routes = $routes->to(action => 'foo');
    $routes = $routes->to({action => 'foo'});
    $routes = $routes->to('controller#action');
    $routes = $routes->to('controller#action', foo => 'bar');
    $routes = $routes->to('controller#action', {foo => 'bar'});

=head2 C<is_endpoint>

    my $is_endpoint = $routes->is_endpoint;

=head2 C<match>

    $match = $routes->match($match);
    my $match = $routes->match('/foo/bar');
    my $match = $routes->match(get => '/foo/bar');

=head2 C<over>

    $routes = $routes->over(foo => qr/\w+/);
    $routes = $routes->over({foo => qr/\w+/});

=head2 C<parse>

    $routes = $routes->parse('/:controller/:action');

=head2 C<route>

    my $route = $routes->route('/:c/:a', a => qr/\w+/);

=head2 C<to_string>

    my $string = $routes->to_string;

=head2 C<url_for>

    my $url = $routes->url_for($url);
    my $url = $routes->url_for($url, {foo => 'bar'});

=head2 C<via>

    $routes = $routes->via('get');
    $routes = $routes->via(qw/get post/);
    $routes = $routes->via([qw/get post/]);

=head2 C<waypoint>

    my $route = $routes->waypoint('/:c/:a', a => qr/\w+/);

=cut
