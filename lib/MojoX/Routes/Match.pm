# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Routes::Match;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::ByteStream 'b';
use Mojo::URL;

__PACKAGE__->attr(captures => sub { {} });
__PACKAGE__->attr([qw/endpoint root tx/]);
__PACKAGE__->attr(stack => sub { [] });

# I'm Bender, baby, please insert liquor!
sub new {
    my $self = shift->SUPER::new();
    my $tx   = shift;
    $self->tx($tx);
    $self->{_path} = shift
      || b($tx->req->url->path->to_string)->url_unescape->decode('UTF-8')
      ->to_string;
    return $self;
}

# Life can be hilariously cruel.
sub match {
    my ($self, $r) = @_;

    # Shortcut
    return unless $r;

    # Dictionary
    my $dictionary = $self->{_dictionary} ||= $r->dictionary;

    # Root
    $self->root($r) unless $self->root;

    # Conditions
    for (my $i = 0; $i < @{$r->conditions}; $i += 2) {
        my $name      = $r->conditions->[$i];
        my $value     = $r->conditions->[$i + 1];
        my $condition = $dictionary->{$name};

        # No condition
        return unless $condition;

        # Match
        my $captures = $condition->($r, $self->tx, $self->captures, $value);

        # Matched
        return unless $captures && ref $captures eq 'HASH';

        # Merge captures
        $self->captures($captures);
    }

    # Path
    my $path = $self->{_path};

    # Match
    my $captures = $r->pattern->shape_match(\$path);

    # No match
    return unless $captures;

    # Partial
    if (my $partial = $r->partial) {
        $captures->{$partial} = $path;
        $path = '';
    }
    $self->{_path} = $path;


    # Merge captures
    $captures = {%{$self->captures}, %$captures};
    $self->captures($captures);

    # Format
    if ($r->is_endpoint && !$r->pattern->format) {
        if ($path =~ /^\.([^\/]+)$/) {
            $self->captures->{format} = $1;
            $self->{_path} = '';
        }
    }
    $self->captures->{format} ||= $r->pattern->format if $r->pattern->format;

    # Update stack
    push @{$self->stack}, $captures
      if $r->inline || ($r->is_endpoint && $self->_is_path_empty);

    # Waypoint match
    if ($r->block && $self->_is_path_empty) {
        $self->endpoint($r);
        return $self;
    }

    # Match children
    my $snapshot = [@{$self->stack}];
    for my $child (@{$r->children}) {

        # Match
        $self->match($child);

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

sub url_for {
    my $self     = shift;
    my $endpoint = $self->endpoint;
    my $values   = {};
    my $name     = undef;

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

    # Named
    if ($name) {
        croak qq/Route "$name" used in url_for does not exist/
          unless $endpoint = $self->_find_route($name);
    }

    # Merge values
    $values = {%{$self->captures}, %$values};

    my $url = Mojo::URL->new;

    # No endpoint
    return $url unless $endpoint;

    # Render
    my $path = $endpoint->render($url->path->to_string, $values);
    $url->path->parse($path);

    return $url;
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

MojoX::Routes::Match - Routes Visitor

=head1 SYNOPSIS

    use MojoX::Routes::Match;

    # New match object
    my $m = MojoX::Routes::Match->new($tx);

    # Match
    $m->match($routes);

=head1 DESCRIPTION

L<MojoX::Routes::Match> is a visitor for L<MojoX::Routes> structures.

=head1 ATTRIBUTES

L<MojoX::Routes::Match> implements the following attributes.

=head2 C<captures>

    my $captures = $m->captures;
    $m           = $m->captures({foo => 'bar'});

Captured parameters.

=head2 C<endpoint>

    my $endpoint = $m->endpoint;
    $m           = $m->endpoint(MojoX::Routes->new);

The routes endpoint that actually matched.

=head2 C<root>

    my $root = $m->root;
    $m       = $m->root($routes);

The root of the routes tree.

=head2 C<stack>

    my $stack = $m->stack;
    $m        = $m->stack([{foo => 'bar'}]);

Captured parameters with nesting history.

=head2 C<tx>

    my $tx = $m->tx;
    $m     = $m->tx(Mojo::Transaction::HTTP->new);

Transaction object used for matching.

=head1 METHODS

L<MojoX::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<new>

    my $m = MojoX::Routes::Match->new;
    my $m = MojoX::Routes::Match->new(Mojo::Transaction::HTTP->new);

Construct a new match object.

=head2 C<match>

    $m->match(MojoX::Routes->new);

Match against a routes tree.

=head2 C<url_for>

    my $url = $m->url_for;
    my $url = $m->url_for(foo => 'bar');
    my $url = $m->url_for({foo => 'bar'});
    my $url = $m->url_for('named');
    my $url = $m->url_for('named', foo => 'bar');
    my $url = $m->url_for('named', {foo => 'bar'});

Render matching route with parameters into a L<Mojo::URL> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
