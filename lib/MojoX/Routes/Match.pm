# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoX::Routes::Match;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::URL;

__PACKAGE__->attr('captures', default => sub { {} });
__PACKAGE__->attr('endpoint');
__PACKAGE__->attr('method', default => sub {'get'});
__PACKAGE__->attr('path',   default => sub {'/'});
__PACKAGE__->attr('stack',  default => sub { [] });

# I'm Bender, baby, please insert liquor!
sub new {
    my $self = shift->SUPER::new();

    # Method and path
    if ($_[1]) { $self->method($_[0])->path($_[1]) }

    # Path only
    else { $self->path($_[0]) }

    return $self;
}

sub is_path_empty {
    my $self = shift;
    return 1 if !length $self->path || $self->path eq '/';
    return;
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

        # Find root
        my $stop = $endpoint;
        while ($stop->parent) {
            $stop = $stop->parent;
        }

        # Find endpoint
        my @children = ($stop);
        while (my $child = shift @children) {

            if (($child->name || '') eq $name) {
                $endpoint = $child;
                last;
            }

            # Append
            push @children, @{$child->children};
        }
    }

    # Merge values
    $values = {%{$self->captures}, %$values};

    my $url = Mojo::URL->new;

    # No endpoint
    return $url unless $endpoint;

    # Render
    $endpoint->url_for($url, $values);

    return $url;
}

1;
__END__

=head1 NAME

MojoX::Routes::Match - Match

=head1 SYNOPSIS

    use MojoX::Routes::Match;

    my $match = MojoX::Routes::Match->new;

=head1 DESCRIPTION

L<MojoX::Routes::Match> is a match container.

=head2 ATTRIBUTES

L<MojoX::Routes::Match> implements the following attributes.

=head2 C<captures>

    my $captures = $match->captures;
    $match       = $match->captures({foo => 'bar'});

=head2 C<endpoint>

    my $endpoint = $match->endpoint;
    $match       = $match->endpoint(1);

=head2 C<method>

    my $method = $match->method;
    $match     = $match->method('get');

=head2 C<path>

    my $path = $match->path;
    $match   = $match->path('/foo/bar/baz');

=head2 C<stack>

    my $stack = $match->stack;
    $match    = $match->stack([{foo => 'bar'}]);

=head1 METHODS

L<MojoX::Routes::Match> inherits all methods from L<Mojo::Base> and
implements the follwing the ones.

=head2 C<new>

    my $match = MojoX::Routes::Match->new;
    my $match = MojoX::Routes::Match->new('/foo/bar');

=head2 C<is_path_empty>

    my $result = $match->is_path_empty;

=head2 C<url_for>

    my $url = $match->url_for;
    my $url = $match->url_for(foo => 'bar');
    my $url = $match->url_for({foo => 'bar'});
    my $url = $match->url_for('named');
    my $url = $match->url_for('named', foo => 'bar');
    my $url = $match->url_for('named', {foo => 'bar'});

=cut
