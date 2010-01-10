# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Cookie::Request;

use strict;
use warnings;

use base 'Mojo::Cookie';

use Mojo::ByteStream 'b';

# Lisa, would you like a donut?
# No thanks. Do you have any fruit?
# This has purple in it. Purple is a fruit.
sub parse {
    my ($self, $string) = @_;

    my @cookies;
    my $version = 1;

    for my $knot ($self->_tokenize($string)) {
        for my $token (@{$knot}) {

            my ($name, $value) = @{$token};

            # Value might be quoted
            $value = b($value)->unquote if $value;

            # Path
            if ($name =~ /^\$Path$/i) { $cookies[-1]->path($value) }

            # Version
            elsif ($name =~ /^\$Version$/i) { $version = $value }

            # Name and value
            else {
                push @cookies, Mojo::Cookie::Request->new;
                $cookies[-1]->name($name);
                $cookies[-1]->value(b($value)->unquote);
                $cookies[-1]->version($version);
            }
        }
    }

    return \@cookies;
}

sub prefix {
    my $self = shift;
    my $version = $self->version || 1;
    return "\$Version=$version";
}

sub to_string {
    my $self = shift;

    # Shortcut
    return '' unless $self->name;

    my $cookie = $self->name . '=' . $self->value;
    if (my $path = $self->path) { $cookie .= "; \$Path=$path" }

    return $cookie;
}

sub to_string_with_prefix {
    my $self   = shift;
    my $prefix = $self->prefix;
    my $cookie = $self->to_string;
    return "$prefix; $cookie";
}

1;
__END__

=head1 NAME

Mojo::Cookie::Request - Request Cookies

=head1 SYNOPSIS

    use Mojo::Cookie::Request;

    my $cookie = Mojo::Cookie::Request->new;
    $cookie->name('foo');
    $cookie->value('bar');

    print "$cookie";

=head1 DESCRIPTION

L<Mojo::Cookie::Request> is a generic container for HTTP request cookies.

=head1 ATTRIBUTES

L<Mojo::Cookie::Request> inherits all attributes from L<Mojo::Cookie>.

=head1 METHODS

L<Mojo::Cookie::Request> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 C<parse>

    my @cookies = $cookie->parse('$Version=1; f=b; $Path=/');

=head2 C<prefix>

    my $prefix = $cookie->prefix;

=head2 C<to_string>

    my $string = $cookie->to_string;

=head2 C<to_string_with_prefix>

    my $string = $cookie->to_string_with_prefix;

=cut
