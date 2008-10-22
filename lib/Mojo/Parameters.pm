# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Parameters;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Mojo::ByteStream;
use Mojo::URL;

__PACKAGE__->attr('pair_separator', chained => 1, default => sub { '&' });
__PACKAGE__->attr('parameters',     chained => 1, default => sub { [] });

*param  = \&parameter;
*params = \&parameters;

# Yeah, Moe, that team sure did suck last night. They just plain sucked!
# I've seen teams suck before,
# but they were the suckiest bunch of sucks that ever sucked!
# HOMER!
# I gotta go Moe my damn weiner kids are listening.
sub new {
    my $self = shift->SUPER::new();

    # Hash/Array
    if ($_[1]) { $self->append(@_) }

    # String
    else { $self->parse(@_) }

    return $self;
}

sub append {
    my $self   = shift;

    # Append
    push @{$self->params}, @_;

    return $self;
}

sub clone {
    my $self  = shift;
    my $clone = Mojo::Parameters->new;
    $clone->params([@{$self->params}]);
    return $clone;
}

sub merge {
    my $self = shift;
    push @{$self->params}, @{$_->params} for @_;
    return $self;
}

sub parameter {
    my $self = shift;
    my $name = shift;

    # Cleanup
    $self->remove($name) if defined $_[0];

    # Append
    for my $value (@_) {
        $self->append($name, $value);
    }

    # List
    my @values;
    my $params = $self->params;
    for (my $i = 0; $i < @$params; $i += 2) {
        push @values, $params->[$i + 1] if $params->[$i] eq $name;
    }

    return defined $values[1] ? \@values : $values[0];
}

sub parse {
    my $self = shift;

    # Shortcut
    return $self unless defined $_[0];

    # W3C suggests to also accept ";" as a separator
    for my $pair (split /[\&\;]+/, $_[0]) {

        # We replace "+" with whitespace
        $pair =~ s/\+/\ /g;

        $pair =~ /^([^\=]*)=(.*)$/;

        # Unescape
        my $name  = Mojo::ByteStream->new($1)->url_unescape->to_string;
        my $value = Mojo::ByteStream->new($2)->url_unescape->to_string;

        push @{$self->params}, $name, $value;
    }

    return $self;
}

sub remove {
    my ($self, $name) = @_;

    # Remove
    my $params = $self->params;
    for (my $i = 0; $i < @$params; $i += 2) {
        splice @$params, $i, 2 if $params->[$i] eq $name;
    }

    return $self;
}

sub to_hash {
    my $self   = shift;
    my $params = $self->params;

    # Format
    my %params;
    for (my $i = 0; $i < @$params; $i += 2) {
        my $name  = $params->[$i];
        my $value = $params->[$i + 1];

        # Array
        if (exists $params{$name}) {
            $params{$name} = [$params{$name}]
              unless ref $params{$name} eq 'ARRAY';
            push @{$params{$name}}, $value;
        }

        # String
        else { $params{$name} = $value }
    }

    return \%params;
}

sub to_string {
    my $self   = shift;
    my $params = $self->params;

    # Format
    my @params;
    for (my $i = 0; $i < @$params; $i += 2) {
        my $name  = $params->[$i];
        my $value = $params->[$i + 1];

        # We replace whitespace with "+"
        $name  =~ s/\ /\+/g;
        $value =~ s/\ /\+/g;

        # *( pchar / "/" / "?" )
        $name  = Mojo::ByteStream->new($name)
          ->url_escape($Mojo::URL::PCHAR . '\/\?');
        $value = Mojo::ByteStream->new($value)
          ->url_escape($Mojo::URL::PCHAR . '\/\?');

        push @params, "$name=$value";
    }

    my $separator = $self->pair_separator;
    return join $separator, @params;
}

1;
__END__

=head1 NAME

Mojo::Parameters - Parameters

=head1 SYNOPSIS

    use Mojo::Parameters;

    my $params = Mojo::Parameters->new(foo => 'bar', baz => 23);
    print "$params";

=head1 DESCRIPTION

L<Mojo::Parameters> is a container for form parameters.

=head1 ATTRIBUTES

=head2 C<pair_separator>

    my $separator = $params->pair_separator;
    $params       = $params->pair_separator(';');

=head2 C<params>

=head2 C<parameters>

    my $parameters = $params->params;
    my $parameters = $params->parameters;
    $params        = $params->parameters(foo => 'b;ar', baz => 23);

=head1 METHODS

L<Mojo::Parameters> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

    my $params = Mojo::Parameters->new;
    my $params = Mojo::Parameters->new('foo=b%3Bar&baz=23');
    my $params = Mojo::Parameters->new(foo => 'b;ar', baz => 23);

=head2 C<append>

    $params = $params->append(foo => 'ba;r');

=head2 C<clone>

    my $params2 = $params->clone;

=head2 C<merge>

    $params = $params->merge($params2, $params3);

=head2 C<param>

=head2 C<parameter>

    my $foo = $params->param('foo');
    my $foo = $params->parameter('foo');
    my $foo = $params->parameter(foo => 'ba;r');

=head2 C<parse>

    $params = $params->parse('foo=b%3Bar&baz=23');

=head2 C<remove>

    $params = $params->remove('foo');

=head2 C<to_hash>

    my $hash = $params->to_hash;

=head2 C<to_string>

    my $string = $params->to_string;

=cut
