# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Path;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::ByteStream 'b';
use Mojo::URL;

__PACKAGE__->attr([qw/leading_slash trailing_slash/] => 0);
__PACKAGE__->attr(parts => sub { [] });

sub new {
    my $self = shift->SUPER::new();
    $self->parse(@_);
    return $self;
}

sub append {
    my $self = shift;

    for (@_) {
        my $value = "$_";

        # *( pchar / "/" / "?" )
        $value = b($value)->url_escape($Mojo::URL::PCHAR)->to_string;

        push @{$self->parts}, $value;
    }
    return $self;
}

sub canonicalize {
    my $self = shift;

    # Resolve path
    my @path;
    for my $part (@{$self->parts}) {

        # ".."
        if ($part eq '..') {

            # Leading '..' can't be resolved
            unless (@path && $path[-1] ne '..') { push @path, '..' }

            # Uplevel
            else { pop @path }
            next;
        }

        # "."
        next if $part eq '.';

        # Part
        push @path, $part;
    }
    $self->parts(\@path);

    return $self;
}

# Homer, the plant called.
# They said if you don't show up tomorrow don't bother showing up on Monday.
# Woo-hoo. Four-day weekend.
sub clone {
    my $self  = shift;
    my $clone = Mojo::Path->new;

    $clone->parts([@{$self->parts}]);
    $clone->leading_slash($self->leading_slash);
    $clone->trailing_slash($self->trailing_slash);

    return $clone;
}

sub parse {
    my ($self, $path) = @_;
    $path ||= '';

    # Meta
    $self->leading_slash(1)  if $path =~ /^\//;
    $self->trailing_slash(1) if $path =~ /\/$/;

    # Parse
    my @parts;
    for my $part (split '/', $path) {

        # Garbage
        next unless length $part;

        # Store
        push @parts, $part;
    }

    $self->parts(\@parts);

    return $self;
}

sub to_string {
    my $self = shift;

    # Escape
    my @path;
    for my $part (@{$self->parts}) {

        # *( pchar / "/" / "?" )
        push @path, b($part)->url_escape($Mojo::URL::PCHAR)->to_string;
    }

    # Format
    my $path = join '/', @path;
    $path = "/$path" if $self->leading_slash;
    $path = "$path/" if @path && $self->trailing_slash;

    return $path;
}

1;
__END__

=head1 NAME

Mojo::Path - Path

=head1 SYNOPSIS

    use Mojo::Path;

    my $path = Mojo::Path->new('/foo/bar%3B/baz.html');
    print "$path";

=head1 DESCRIPTION

L<Mojo::Path> is a container for URL paths.

=head1 ATTRIBUTES

L<Mojo::Path> implements the following attributes.

=head2 C<leading_slash>

    my $leading_slash = $path->leading_slash;
    $path             = $path->leading_slash(1);

=head2 C<parts>

    my $parts = $path->parts;
    $path     = $path->parts(qw/foo bar baz/);

=head2 C<trailing_slash>

    my $trailing_slash = $path->trailing_slash;
    $path              = $path->trailing_slash(1);

=head1 METHODS

L<Mojo::Path> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $path = Mojo::Path->new;
    my $path = Mojo::Path->new('/foo/bar%3B/baz.html');

=head2 C<append>

    $path = $path->append(qw/foo bar/);

=head2 C<canonicalize>

    $path = $path->canonicalize;

=head2 C<clone>

    my $clone = $path->clone;

=head2 C<parse>

    $path = $path->parse('/foo/bar%3B/baz.html');

=head2 C<to_string>

    my $string = $path->to_string;

=cut
