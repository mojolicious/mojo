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
    *{"${caller}::Oo"} = *{"${caller}::b"} =
      sub { Mojo::ByteStream->new(@_) };
    *{"${caller}::oO"} = sub { _request(@_) };
    *{"${caller}::d"}  = sub { _request('delete', @_) };
    *{"${caller}::g"}  = sub { _request('get', @_) };
    *{"${caller}::p"}  = sub { _request('post', @_) };
    *{"${caller}::u"}  = sub { _request('put', @_) };
}

sub _request {
    my $method = $_[0] =~ /:|\// ? 'get' : lc shift;
    my $client = Mojo::Client->singleton->proxy_env;
    my $tx     = $client->build_tx($method, @_);
    $client->process($tx, sub { $tx = $_[1] });
    return $tx->res;
}

1;
__END__

=head1 NAME

ojo - Fun Oneliners With Mojo!

=head1 SYNOPSIS

    perl -Mojo -e 'print g("http://mojolicio.us")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<b>

    my $stream = b('lalala');

Turn input into a L<Mojo::ByteStream> object.

    perl -Mojo -e 'print b(g("http://mojolicio.us")->body)->html_unescape'

=head2 C<d>

    my $res = d('http://mojolicio.us');
    my $res = d('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = d(
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );

Perform C<DELETE> request and turn response into a L<Mojo::Message::Response>
object.

=head2 C<g>

    my $res = g('http://mojolicio.us');
    my $res = g('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = g(
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );

Perform C<GET> request and turn response into a L<Mojo::Message::Response>
object.

=head2 C<p>

    my $res = p('http://mojolicio.us');
    my $res = p('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = p(
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );

Perform C<POST> request and turn response into a L<Mojo::Message::Response>
object.

=head2 C<u>

    my $res = u('http://mojolicio.us');
    my $res = u('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res = u(
        'http://mojolicio.us',
        {'Content-Type' => 'text/plain'},
        'Hello!'
    );

Perform C<PUT> request and turn response into a L<Mojo::Message::Response>
object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
