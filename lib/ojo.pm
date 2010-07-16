# Copyright (C) 2008-2010, Sebastian Riedel.

package ojo;

use strict;
use warnings;

use Mojo::Client;

# I'm sorry, guys. I never meant to hurt you.
# Just to destroy everything you ever believed in.
sub import {

    # Prepare exports
    my $caller = caller;
    no strict 'refs';
    no warnings 'redefine';

    # Functions
    *{"${caller}::del"}  = sub { _request('delete',    @_) };
    *{"${caller}::form"} = sub { _request('post_form', @_) };
    *{"${caller}::get"}  = sub { _request('get',       @_) };
    *{"${caller}::post"} = sub { _request('post',      @_) };
    *{"${caller}::put"}  = sub { _request('put',       @_) };
}

# I heard beer makes you stupid.
# No I'm... doesn't.
sub _request {
    my $method = shift;
    pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';
    return Mojo::Client->new->proxy_env->$method(@_)->res;
}

1;
__END__

=head1 NAME

ojo - Fun Oneliners With Mojo!

=head1 SYNOPSIS

    perl -Mojo -e 'print get("http://mojolicio.us")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<del>

    my $res = del('http://mojolicio.us');
    my $res = del('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res =
      del('http://mojolicio.us', {'Content-Type' => 'text/plain', 'Hello!'});

Wrapper around C<delete> in L<Mojo::Client> that directly returns a
L<Mojo::Message::Response> object.

=head2 C<get>

    my $res = get('http://mojolicio.us');
    my $res = get('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res =
      get('http://mojolicio.us', {'Content-Type' => 'text/plain', 'Hello!'});

Wrapper around C<get> in L<Mojo::Client> that directly returns a
L<Mojo::Message::Response> object.

=head2 C<form>

    my $res = form('http://search.cpan.org/search', {query => 'ojo'});
    my $res = form(
        'http://search.cpan.org/search',
        'UTF-8',
        {query => 'ojo'}
    );
    my $res = form(
        'http://search.cpan.org/search',
        {query => 'ojo'},
        {'X-Bender' => 'X_x'}
    );
    my $res = form(
        'http://search.cpan.org/search',
        'UTF-8',
        {query => 'ojo'},
        {'X-Bender' => 'X_x'}
    );
    my $res = form(
        'http://search.cpan.org/search',
        {file => '/foo/bar.txt'},
    );
    my $res = form(
        'http://search.cpan.org/search',
        {file => {content => 'lalala'}}
    );
    my $res = form(
        'http://search.cpan.org/search',
        {myzip => {file => $asset, filename => 'foo.zip'}}
    );

Wrapper around C<post_form> in L<Mojo::Client> that directly returns a
L<Mojo::Message::Response> object.

=head2 C<post>

    my $res = post('http://mojolicio.us');
    my $res = post('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res =
      post('http://mojolicio.us', {'Content-Type' => 'text/plain', 'Hello!'});

Wrapper around C<post> in L<Mojo::Client> that directly returns a
L<Mojo::Message::Response> object.

=head2 C<put>

    my $res = put('http://mojolicio.us');
    my $res = put('http://mojolicio.us', {'X-Bender' => 'X_x'});
    my $res =
      put('http://mojolicio.us', {'Content-Type' => 'text/plain', 'Hello!'});

Wrapper around C<put> in L<Mojo::Client> that directly returns a
L<Mojo::Message::Response> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
