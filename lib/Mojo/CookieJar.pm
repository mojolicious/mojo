# Copyright (C) 2008-2009, Sebastian Riedel

package Mojo::CookieJar;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

use Mojo::Cookie::Request;

__PACKAGE__->attr(max_cookie_size => 4096);

__PACKAGE__->attr(_jar => sub { {} });
__PACKAGE__->attr(_size => 0);

# I can't help but feel this is all my fault.
# It was those North Korean fortune cookies - they were so insulting.
# "You are a coward."
# Nobody wants to hear that after a nice meal.
# Marge, you can't keep blaming yourself.
# Just blame yourself once, then move on.
sub add {
    my ($self, @cookies) = @_;

    # Add cookies
    for my $cookie (@cookies) {

        # Unique cookie id
        my $domain = $cookie->domain;
        my $path   = $cookie->path;
        my $name   = $cookie->name;

        # Convert max age to expires
        $cookie->expires($cookie->max_age + time) if $cookie->max_age;

        # Default to session cookie
        $cookie->max_age(0) unless $cookie->expires || $cookie->max_age;

        # Cookie too big
        next if length $cookie->value > $self->max_cookie_size;

        # Initialize
        $self->_jar->{$domain} ||= [];

        # Check if we already have the same cookie
        my @new;
        for my $old (@{$self->_jar->{$domain}}) {

            # Unique cookie id
            my $opath = $old->path;
            my $oname = $old->name;

            push @new, $old unless $opath eq $path && $oname eq $name;
        }

        # Add
        push @new, $cookie;
        $self->_jar->{$domain} = \@new;
    }

    return $self;
}

sub find {
    my ($self, $url) = @_;

    # Pattern
    my $domain = $url->host;
    my $path = $url->path || '/';

    # Shortcut
    return unless $domain;

    # Find
    my @found;
    while ($domain =~ /[^\.]+\.[^\.]+$/) {

        # Nothing
        next unless my $jar = $self->_jar->{$domain};

        # Look inside
        my @new;
        for my $cookie (@$jar) {

            # Session cookie?
            my $session =
              defined $cookie->max_age && $cookie->max_age > 0 ? 1 : 0;
            if ($cookie->expires || !$session) {

                # Expired
                next if $cookie->expires && time > $cookie->expires->epoch;
            }

            # Port
            my $port = $url->port || 80;
            next if $cookie->port && $port != $cookie->port;

            # Path
            my $cpath = $cookie->path;
            push @found,
              Mojo::Cookie::Request->new(
                name    => $cookie->name,
                value   => $cookie->value,
                path    => $cookie->path,
                version => $cookie->version
              ) if $path =~ /^$cpath/;

            # Not expired
            push @new, $cookie;
        }
        $self->_jar->{$domain} = \@new;
    }

    # Remove leading dot or part
    continue { $domain =~ s/^(?:\.|[^\.]+)// }

    return @found;
}

1;
__END__

=head1 NAME

Mojo::CookieJar - CookieJar

=head1 SYNOPSIS

    use Mojo::CookieJar;
    my $jar = Mojo::CookieJar->new;

=head1 DESCRIPTION

L<Mojo::CookieJar> is a minimalistic cookie jar for HTTP user agents.

=head1 ATTRIBUTES

L<Mojo::CookieJar> implements the following attributes.

=head2 C<max_cookie_size>

    my $max_cookie_size = $jar->max_cookie_size;
    $jar                = $jar->max_cookie_size(4096);

=head1 METHODS

L<Mojo::CookieJar> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<add>

    $jar = $jar->add(@cookies);

=head2 C<find>

    my @cookies = $jar->find($url);

=cut
