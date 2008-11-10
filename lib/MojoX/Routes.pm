# Copyright (C) 2008, Sebastian Riedel.

package MojoX::Routes;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::URL;
use MojoX::Routes::Match;
use MojoX::Routes::Pattern;

use constant DEBUG => $ENV{MOJOX_ROUTES_DEBUG} || 0;

__PACKAGE__->attr([qw/block inline name/], chained => 1);
__PACKAGE__->attr('children', chained => 1, default => sub { [] });
__PACKAGE__->attr('parent', chained => 1, weak => 1);
__PACKAGE__->attr('pattern',
    chained => 1,
    default => sub { MojoX::Routes::Pattern->new }
);

sub new {
    my $self = shift->SUPER::new();
    $self->parse(@_);
    return $self;
}

sub bridge { return shift->route(@_)->inline(1) }

sub is_endpoint {
    my $self = shift;
    return 0 if $self->inline;
    return 0 if @{$self->children};
    return 1;
}

# Life can be hilariously cruel.
sub match {
    my ($self, $match) = @_;

    # Shortcut
    return undef unless $match;

    # Match object
    $match = MojoX::Routes::Match->new($match)
      unless ref $match && $match->isa('MojoX::Routes::Match');

    # Path
    my $path = $match->path;
    my $substring = $self->_shape(\$path);

    # Debug
    warn qq/"$substring" ("$path")\n/ if DEBUG;

    # Match
    my $captures = $self->pattern->match($substring) || return undef;

    $match->path($path);

    # Merge captures
    $captures = {%{$match->captures}, %$captures};
    $match->captures($captures);

    # Update stack
    if ($self->inline || $self->is_endpoint) {
        push @{$match->stack}, $captures;
    }

    # Waypoint match
    if ($self->block && (!$path || $path eq '/')) {
        push @{$match->stack}, $captures;
        $match->endpoint($self);
        return $self;
    }

    # Match children
    for my $child (@{$self->children}) {

        # Match
        $child->match($match);

        # Endpoint found
        return $match if $match->endpoint;

        # Reset path
        $match->path($path);
    }

    $match->endpoint($self) if $self->is_endpoint;

    return $match;
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

    # We are the parent
    $route->parent($self);

    # Add to tree
    push @{$self->children}, $route;

    return $route;
}

sub segments { return shift->pattern->segments }

sub to {
    my $self = shift;

    # Shortcut
    return $self unless @_;

    # Defaults
    my $defaults = ref $_[0] eq 'HASH' ? $_[0] : {@_};
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
    my $path = $url->path->to_string;
    $path = $self->pattern->render($values) . $path;

    # Make sure there is always a root
    $path = '/' if !$path && !$self->parent;

    $url->path->parse($path);

    $self->parent->url_for($url, $values) if $self->parent;

    return $url;
}

sub waypoint { return shift->route(@_)->block(1) }

sub _shape {
    my ($self, $pathref) = @_;

    # Shortcut
    return '' unless $self->segments;

    my $substring = '';
    for (1 .. $self->segments) {
        $$pathref =~ s/^(\/?[^\/]*)//;
        $substring .= $1;
    }

    return $substring;
}

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

=head2 C<block>

    my $block = $routes->block;
    $routes   = $routes->block(1);

=head2 C<children>

    my $children = $routes->children;
    $routes      = $routes->children([MojoX::Routes->new]);

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

=head2 C<segments>

    my $segments = $routes->segments;

=head1 METHODS

L<MojoX::Routes> inherits all methods from L<Mojo::Base> and implements the
follwing the ones.

=head2 C<new>

    my $routes = MojoX::Routes->new;
    my $routes = MojoX::Routes->new('/:controller/:action');

=head2 C<bridge>

    my $bridge = $routes->bridge;
    my $bridge = $routes->bridge('/:controller/:action');

=head2 C<to>

    my $to  = $routes->to;
    $routes = $routes->to(action => 'foo');
    $routes = $routes->to({action => 'foo'});

=head2 C<is_endpoint>

    my $is_endpoint = $routes->is_endpoint;

=head2 C<match>

    my $match = $routes->match($tx);

=head2 C<parse>

    $routes = $routes->parse('/:controller/:action');

=head2 C<route>

    my $route = $routes->route('/:c/:a', a => qr/\w+/);

=head2 C<to_string>

    my $string = $routes->to_string;

=head2 C<url_for>

    my $url = $routes->url_for($url);
    my $url = $routes->url_for($url, {foo => 'bar'});

=head2 C<waypoint>

    my $route = $routes->waypoint('/:c/:a', a => qr/\w+/);

=cut