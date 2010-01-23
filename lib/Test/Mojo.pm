# Copyright (C) 2008-2010, Sebastian Riedel.

package Test::Mojo;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::JSON;

require Test::More;

__PACKAGE__->attr(app => sub { return $ENV{MOJO_APP} if ref $ENV{MOJO_APP} });
__PACKAGE__->attr(client    => sub { Mojo::Client->new });
__PACKAGE__->attr(redirects => sub { [] });
__PACKAGE__->attr('tx');
__PACKAGE__->attr(max_redirects => 0);

# Ooh, a graduate student huh?
# How come you guys can go to the moon but can't make my shoes smell good?
sub content_is {
    my ($self, $value, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::is($self->_get_content($tx), $value, $desc);

    return $self;
}

sub content_like {
    my ($self, $regex, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::like($self->_get_content($tx), $regex, $desc);

    return $self;
}

# Marge, I can't wear a pink shirt to work.
# Everybody wears white shirts.
# I'm not popular enough to be different.
sub content_type_is {
    my ($self, $type, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::is($tx->res->headers->content_type, $type, $desc);

    return $self;
}

sub content_type_like {
    my ($self, $regex, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::like($tx->res->headers->content_type, $regex, $desc);

    return $self;
}

# A job's a job. I mean, take me.
# If my plant pollutes the water and poisons the town,
# by your logic, that would make me a criminal.
sub delete_ok { shift->_request_ok('delete', @_) }
sub get_ok    { shift->_request_ok('get',    @_) }
sub head_ok   { shift->_request_ok('head',   @_) }

sub header_is {
    my ($self, $name, $value, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::is($tx->res->headers->header($name), $value, $desc);

    return $self;
}

sub header_like {
    my ($self, $name, $regex, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::like($tx->res->headers->header($name), $regex, $desc);

    return $self;
}

sub json_content_is {
    my ($self, $struct, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::is_deeply(Mojo::JSON->new->decode($tx->res->body),
        $struct, $desc);

    return $self;
}

# God bless those pagans.
sub post_ok { shift->_request_ok('post', @_) }

# Hey, I asked for ketchup! I'm eatin' salad here!
sub post_form_ok {
    my $self = shift;

    # Description
    my $desc = ref $_[-1] ? undef : pop @_;

    # Client
    my $client = $self->client;
    $client->app($self->app);
    $client->max_redirects($self->max_redirects);

    # Request
    $client->post_form(@_,
        sub { $self->tx($_[1]) and $self->redirects($_[2]) })->process;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::ok($self->tx->is_done, $desc);

    return $self;
}

# WHO IS FONZY!?! Don't they teach you anything at school?
sub put_ok { shift->_request_ok('put', @_) }

sub reset_session {
    my $self = shift;

    # Client
    $self->client->cookie_jar->empty;
    $self->client->max_redirects($self->max_redirects);

    # Transaction
    $self->tx(undef);

    return $self;
}

# Internet! Is that thing still around?
sub status_is {
    my ($self, $status, $desc) = @_;

    # Transaction
    my $tx = $self->tx;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::is($tx->res->code, $status, $desc);

    return $self;
}

sub _get_content {
    my ($self, $tx) = @_;

    # Charset
    ($tx->res->headers->content_type || '') =~ /charset=\"?([^"\s]+)\"?/;
    my $charset = $1;

    # Content
    return $charset
      ? b($tx->res->body)->decode($charset)->to_string
      : $tx->res->body;
}

# Are you sure this is the Sci-Fi Convention? It's full of nerds!
sub _request_ok {
    my ($self, $method, $url, $headers, $desc) = @_;

    # Description
    $desc = $headers unless ref $headers;
    $headers ||= {};

    # Client
    my $client = $self->client;
    $client->app($self->app);
    $client->max_redirects($self->max_redirects);

    # Request
    $client->$method($url, $headers,
        sub { $self->tx($_[1]) and $self->redirects($_[2]) })->process;

    # Test
    local $Test::Builder::Level = $Test::Builder::Level + 2;
    Test::More::ok($self->tx->is_done, $desc);

    return $self;
}

1;
__END__

=head1 NAME

Test::Mojo - Testing Mojo!

=head1 SYNOPSIS

    use Test::Mojo;
    my $t = Test::Mojo->new(app => 'MyApp');

    $t->get_ok('/welcome')
      ->status_is(200)
      ->content_like(qr/Hello!/, 'welcome message!');

    $t->post_form_ok('/search', {title => 'Perl', author => 'taro'})
      ->status_is(200)
      ->content_like(qr/Perl.+taro/);

    $t->delete_ok('/something')
      ->status_is(200)
      ->header_is('X-Powered-By' => 'Mojo (Perl)')
      ->content_is('Hello world!');

=head1 DESCRIPTION

L<Test::Mojo> is a collection of testing helpers for everyone developing
L<Mojo> and L<Mojolicious> applications.

=head1 ATTRIBUTES

L<Test::Mojo> implements the following attributes.

=head2 C<app>

    my $app = $t->app;
    $t      = $t->app(MyApp->new);

=head2 C<client>

    my $client = $t->client;
    $t         = $t->client(Mojo::Client->new);

=head2 C<redirects>

    my $redirects = $t->redirects;
    $t            = $t->redirects([]);

=head2 C<tx>

    my $tx = $t->tx;
    $t     = $t->tx(Mojo::Transaction::Simple->new);

=head2 C<max_redirects>

    my $max_redirects = $t->max_redirects;
    $t                = $t->max_redirects(3);

=head1 METHODS

L<Test::Mojo> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<content_is>

    $t = $t->content_is('working!');
    $t = $t->content_is('working!', 'right content!');

=head2 C<content_like>

    $t = $t->content_like(qr/working!/);
    $t = $t->content_like(qr/working!/, 'right content!');

=head2 C<content_type_is>

    $t = $t->content_type_is('text/html');
    $t = $t->content_type_is('text/html', 'right content type!');

=head2 C<content_type_like>

    $t = $t->content_type_like(qr/text/);
    $t = $t->content_type_like(qr/text/, 'right content type!');

=head2 C<delete_ok>

    $t = $t->delete_ok('/foo');
    $t = $t->delete_ok('/foo', {Expect => '100-continue'});
    $t = $t->delete_ok('/foo', 'request worked!');
    $t = $t->delete_ok('/foo', {Expect => '100-continue'}, 'request worked!');

=head2 C<get_ok>

    $t = $t->get_ok('/foo');
    $t = $t->get_ok('/foo', {Expect => '100-continue'});
    $t = $t->get_ok('/foo', 'request worked!');
    $t = $t->get_ok('/foo', {Expect => '100-continue'}, 'request worked!');

=head2 C<head_ok>

    $t = $t->head_ok('/foo');
    $t = $t->head_ok('/foo', {Expect => '100-continue'});
    $t = $t->head_ok('/foo', 'request worked!');
    $t = $t->head_ok('/foo', {Expect => '100-continue'}, 'request worked!');

=head2 C<header_is>

    $t = $t->header_is(Expect => '100-continue');
    $t = $t->header_is(Expect => '100-continue', 'right header!');

=head2 C<header_like>

    $t = $t->header_like(Expect => qr/100-continue/);
    $t = $t->header_like(Expect => qr/100-continue/, 'right header!');

=head2 C<json_content_is>

    $t = $t->json_content_is([1, 2, 3]);
    $t = $t->json_content_is([1, 2, 3], 'right content!');

=head2 C<post_ok>

    $t = $t->post_ok('/foo');
    $t = $t->post_ok('/foo', {Expect => '100-continue'});
    $t = $t->post_ok('/foo', 'request worked!');
    $t = $t->post_ok('/foo', {Expect => '100-continue'}, 'request worked!');

=head2 C<post_form_ok>

    $t = $t->post_form_ok('/foo' => {test => 123});
    $t = $t->post_form_ok('/foo' => 'UTF-8' => {test => 123});
    $t = $t->post_form_ok('/foo', {test => 123}, {Expect => '100-continue'});
    $t = $t->post_form_ok(
        '/foo',
        'UTF-8',
        {test => 123},
        {Expect => '100-continue'}
    );
    $t = $t->post_form_ok('/foo', {test => 123}, 'request worked!');
    $t = $t->post_form_ok('/foo', 'UTF-8', {test => 123}, 'request worked!');
    $t = $t->post_form_ok(
        '/foo',
        {test   => 123},
        {Expect => '100-continue'},
        'request worked!'
    );
    $t = $t->post_form_ok(
        '/foo',
        'UTF-8',
        {test   => 123},
        {Expect => '100-continue'},
        'request worked!'
    );

=head2 C<put_ok>

    $t = $t->put_ok('/foo');
    $t = $t->put_ok('/foo', {Expect => '100-continue'});
    $t = $t->put_ok('/foo', 'request worked!');
    $t = $t->put_ok('/foo', {Expect => '100-continue'}, 'request worked!');

=head2 C<reset_session>

    $t = $t->reset_session;

=head2 C<status_is>

    $t = $t->status_is(200);
    $t = $t->status_is(200, 'right status!');

=cut
