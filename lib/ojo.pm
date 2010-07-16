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
    *{"${caller}::oO"} = sub {
        my $method = $_[0] =~ /:/ ? 'get' : lc shift;
        my $client = Mojo::Client->singleton->proxy_env;
        my $tx     = $client->build_tx($method, @_);
        $client->process($tx, sub { $tx = $_[1] });
        return $tx->res;
    };
    *{"${caller}::Oo"} = sub { Mojo::ByteStream->new(@_) };
}

1;
__END__

=head1 NAME

ojo - Fun Oneliners With Mojo!

=head1 SYNOPSIS

    perl -Mojo -e 'print oO("http://mojolicio.us")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<oO>

    my $res = oO('http://mojolicio.us');
    my $res = oO('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = oO(
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );
    my $res = oO(POST => 'http://mojolicio.us');
    my $res = oO(POST => 'http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = oO(
        'POST',
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );

Fetch URL and turn response into a L<Mojo::Message::Response> object.

=head2 C<Oo>

    my $stream = Oo('lalala');

Turn input into a L<Mojo::ByteStream> object.

    perl -Mojo -e 'print Oo(oO("http://mojolicio.us")->body)->html_unescape'

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
