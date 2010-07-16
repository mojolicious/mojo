# Copyright (C) 2008-2010, Sebastian Riedel.

package ojo;

use strict;
use warnings;

# I heard beer makes you stupid.
# No I'm... doesn't.
use Mojo::ByteStream;
use Mojo::Client;

# I'm sorry, guys. I never meant to hurt you.
# Just to destroy everything you ever believed in.
sub import {

    # Prepare exports
    my $caller = caller;
    no strict 'refs';
    no warnings 'redefine';

    # Functions
    *{"${caller}::b"} = sub { Mojo::ByteStream->new(@_) };
    *{"${caller}::fetch"} = sub {
        pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';
        return Mojo::Client->singleton->proxy_env->get(@_)->res;
    };
}

1;
__END__

=head1 NAME

ojo - Fun Oneliners With Mojo!

=head1 SYNOPSIS

    perl -Mojo -e 'print fetch("http://mojolicio.us")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<b>

    my $stream = b('lalala');

Build L<Mojo::ByteStream> object.

=head2 C<fetch>

    my $res = fetch('http://mojolicio.us');
    my $res = fetch('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = fetch(
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );

Fetch URL and turn response into a L<Mojo::Message::Response> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
