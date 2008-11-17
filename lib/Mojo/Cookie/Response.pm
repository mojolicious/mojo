# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Cookie::Response;

use strict;
use warnings;

use base 'Mojo::Cookie';

use Mojo::ByteStream;

# Remember the time he ate my goldfish?
# And you lied and said I never had goldfish.
# Then why did I have the bowl Bart? Why did I have the bowl?
sub parse {
    my ($self, $string) = @_;

    my @cookies;
    for my $knot ($self->_tokenize($string)) {

        my $first = 1;
        for my $token (@{$knot}) {

            my $name  = $token->[0];
            my $value = $token->[1];

            # Value might be quoted
            $value = Mojo::ByteStream->new($value)->unquote->to_string
              if $value;

            # Name and value
            if ($first) {
                push @cookies, Mojo::Cookie::Response->new;
                $cookies[-1]->name($name);
                $cookies[-1]->value($value);
                $first = 0;
            }

            # Version
            elsif ($name =~ /^Version$/i) { $cookies[-1]->version($value) }

            # Path
            elsif ($name =~ /^Path$/i) { $cookies[-1]->path($value) }

            # Domain
            elsif ($name =~ /^Domain$/i) { $cookies[-1]->domain($value) }

            # Max-Age
            elsif ($name =~ /^Max-Age$/i) { $cookies[-1]->max_age($value) }

            # expires
            elsif ($name =~ /^Expires$/i) { $cookies[-1]->expires($value) }

            # Secure
            elsif ($name =~ /^Secure$/i) { $cookies[-1]->secure($value) }

            # Comment
            elsif ($name =~ /^Comment$/i) { $cookies[-1]->comment($value) }
        }
    }

    return \@cookies;
}

sub to_string {
    my $self = shift;

    return '' unless $self->name;

    my $name = $self->name;
    my $value = $self->value;
    my $cookie .= "$name=$value";

    $cookie .= '; Version=';
    $cookie .= $self->version || 1;

    if (my $domain = $self->domain)   { $cookie .= "; Domain=$domain"   }
    if (my $path = $self->path)       { $cookie .= "; Path=$path"       }
    if (defined(my $max_age = $self->max_age)) { $cookie .= "; Max-Age=$max_age" }
    if (defined(my $expires = $self->expires)) { $cookie .= "; Expires=$expires" }
    if (my $secure = $self->secure)   { $cookie .= "; Secure=$secure"   }
    if (my $comment = $self->comment) { $cookie .= "; Comment=$comment" }

    return $cookie;
}

1;
__END__

=head1 NAME

Mojo::Cookie::Response - Response Cookies

=head1 SYNOPSIS

    use Mojo::Cookie::Response;

    my $cookie = Mojo::Cookie::Response->new;
    $cookie->name('foo');
    $cookie->value('bar');

    print "$cookie";

=head1 DESCRIPTION

L<Mojo::Cookie::Response> is a generic container for HTTP response cookies.

=head1 ATTRIBUTES

L<Mojo::Cookie::Response> inherits all attributes from L<Mojo::Cookie>.

=head1 METHODS

L<Mojo::Cookie::Response> inherits all methods from L<Mojo::Cookie> and
implements the following new ones.

=head2 C<parse>

    my @cookies = $cookie->parse('f=b; Version=1; Path=/');

=head2 C<to_string>

    my $string = $cookie->to_string;

=cut
