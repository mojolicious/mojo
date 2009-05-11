# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Cookie::Response;

use strict;
use warnings;

use base 'Mojo::Cookie';

use constant RE_COOKIE_FIELDS => qr{
    \A (
          Version
        | Path
        | Domain
        | Max-Age
        | expires
        | Secure
        | HttpOnly # IE6 FF3 Opera 9.5
        | Comment
    ) \z
}xmsi;
use constant RE_COOKIE_FLAGS => qr{
    # these don't have any value. either exists or not
    \A (?: Secure | HttpOnly ) \z
}xmsi;

use Mojo::ByteStream;

# Remember the time he ate my goldfish?
# And you lied and said I never had goldfish.
# Then why did I have the bowl Bart? Why did I have the bowl?
sub parse {
    my ($self, $string) = @_;
    my @cookies;

    PARSE_OUT: for my $knot ( $self->_tokenize($string) ) {
        PARSE_IN: for my $i (0..$#{$knot}) {
            my($name, $value) = @{ $knot->[$i] };

            # Value might be quoted
            $value = Mojo::ByteStream->new($value)->unquote->to_string
              if $value;

            if ( not $i ) { # this'll only run once
                push @cookies, Mojo::Cookie::Response->new;
                $cookies[-1]->name($name);
                $cookies[-1]->value($value);
                next PARSE_IN;
            }

            if ( my @match = $name =~ RE_COOKIE_FIELDS ) {
                (my $id = lc $match[0]) =~ tr/-/_/d; # faster than s///
                $cookies[-1]->$id( $id =~ RE_COOKIE_FLAGS ? 1 : $value);
            }
        }
    }

    return \@cookies;
}

sub to_string {
    my $self = shift;

    return '' unless $self->name;

    my $name  = $self->name;
    my $value = $self->value;
    my $cookie .= "$name=$value";

    $cookie .= '; Version=';
    $cookie .= $self->version || 1;

    if (my $domain = $self->domain) { $cookie .= "; Domain=$domain" }
    if (my $path   = $self->path)   { $cookie .= "; Path=$path" }
    if (defined(my $max_age = $self->max_age)) {
        $cookie .= "; Max-Age=$max_age";
    }
    if (defined(my $expires = $self->expires)) {
        $cookie .= "; expires=$expires";
    }
    if (my $secure   = $self->secure)   { $cookie .= "; Secure" }
    if (my $httponly = $self->httponly) { $cookie .= "; HttpOnly" }
    if (my $comment  = $self->comment)  { $cookie .= "; Comment=$comment" }

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
