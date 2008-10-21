# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Cookie;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_string }, fallback => 1;

use Carp;
use Mojo::Date;

__PACKAGE__->attr([qw/comment domain name path secure value version/],
    chained => 1
);

# My Homer is not a communist.
# He may be a liar, a pig, an idiot, a communist, but he is not a porn star.
sub expires {
    my ($self, $expires) = @_;
    if ($expires) {
        $self->{expires} = Mojo::Date->parse($expires) unless ref $expires;
    }
    return $self->{expires};
}

sub max_age {
    my ($self, $max_age) = @_;
    if ($max_age) {
        $self->{max_age} = Mojo::Date->parse("$max_age");
    }
    return $self->{max_age} ? $self->{max_age}->epoch : 0;
}

sub to_string { croak 'Method "to_string" not implemented by subclass' }

sub _tokenize {
    my ($self, $string) = @_;

    my (@tree, @token);
    while (length $string) {

        # Name
        if ($string =~ s/
            ^\s*           # Start
            ([^\=\;\,]+)   # Relaxed Netscape token, allowing whitespace
            \s*\=?\s*      # '=' (optional)
        //x) {

            my $name = $1;
            my $value;

            # Quoted value
            if ($string =~ s/
                ^\s*               # Start
                (\"                # Quote
                (!:\\(!:\\\")?)*   # Value
                \")                # Quote
            //x) { $value = Mojo::ByteStream->new($1)->unquote }

            # "expires" is a special case, thank you Netscape...
            elsif ($name =~ /expires/i && $string =~ s/^([^\;]+)\s*//) {
                $value = $1;
            }

            # Unquoted string
            elsif ($string =~ s/^([^\;\,]+)\s*//) {
                $value = $1;
            }

            push @token, [$name, $value];

            # Separator
            $string =~ s/^\s*\;\s*//;

            # Cookie separator
            if ($string =~ s/^\s*\,\s*//) {
                push @tree, [@token];
                @token = ();
            }
        }

        # Bad format
        else { last }

    }

    # No separator
    push @tree, [@token] if @token;

    return @tree;
}

1;
__END__

=head1 NAME

Mojo::Cookie - Cookie Base Class

=head1 SYNOPSIS

    use base 'Mojo::Cookie';

=head1 DESCRIPTION

L<Mojo::Cookie> is a cookie base class.

=head1 ATTRIBUTES

=head2 C<comment>

    my $comment = $cookie->comment;
    $cookie     = $cookie->comment('test 123');

=head2 C<domain>

    my $domain = $cookie->domain;
    $cookie    = $cookie->domain('localhost');

=head2 C<expires>

    my $expires = $cookie->expires;
    $cookie     = $cookie->expires(time + 60);

=head2 C<max_age>

    my $max_age = $cookie->max_age;
    $cookie     = $cookie->max_age(time + 60);

=head2 C<name>

    my $name = $cookie->name;
    $cookie  = $cookie->name('foo');

=head2 C<path>

    my $path = $cookie->path;
    $cookie  = $cookie->path('/test');

=head2 C<secure>

    my $secure = $cookie->secure;
    $cookie    = $cookie->secure(1);

=head2 C<value>

    my $value = $cookie->value;
    $cookie   = $cookie->value('/test');

=head2 C<version>

    my $version = $cookie->version;
    $cookie     = $cookie->version(1);

=head1 METHODS

L<Mojo::Cookie> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<to_string>

    my $string = $cookie->to_string;

=cut