package ojo;
use Mojo::Base -strict;

use Mojo::ByteStream 'b';
use Mojo::Collection 'c';
use Mojo::DOM;
use Mojo::JSON 'j';
use Mojo::UserAgent;
use Mojo::Util 'monkey_patch';

# Silent oneliners
$ENV{MOJO_LOG_LEVEL} ||= 'fatal';

# Singleton user agent for oneliners
my $UA = Mojo::UserAgent->new;

sub import {

  # Mojolicious::Lite
  my $caller = caller;
  eval "package $caller; use Mojolicious::Lite;";
  $UA->app($caller->app);

  $UA->max_redirects(10) unless defined $ENV{MOJO_MAX_REDIRECTS};
  $UA->detect_proxy unless defined $ENV{MOJO_PROXY};

  # The ojo DSL
  monkey_patch $caller,
    a => sub { $caller->can('any')->(@_) and return $UA->app },
    b => \&b,
    c => \&c,
    d => sub { _request($UA->build_tx(DELETE  => @_)) },
    g => sub { _request($UA->build_tx(GET     => @_)) },
    h => sub { _request($UA->build_tx(HEAD    => @_)) },
    j => \&j,
    o => sub { _request($UA->build_tx(OPTIONS => @_)) },
    p => sub { _request($UA->build_tx(POST    => @_)) },
    r => sub { $UA->app->dumper(@_) },
    t => sub { _request($UA->build_tx(PATCH => @_)) },
    u => sub { _request($UA->build_tx(PUT => @_)) },
    x => sub { Mojo::DOM->new(@_) };
}

sub _request {
  my $tx = $UA->start(@_);
  my ($err, $code) = $tx->error;
  warn qq/Problem loading URL "@{[$tx->req->url->to_abs]}". ($err)\n/
    if $err && !$code;
  return $tx->res;
}

1;

=head1 NAME

ojo - Fun oneliners with Mojo!

=head1 SYNOPSIS

  $ perl -Mojo -E 'say g("mojolicio.us")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners. Ten
redirects will be followed by default, you can change this behavior with the
MOJO_MAX_REDIRECTS environment variable.

  $ MOJO_MAX_REDIRECTS=0 perl -Mojo -E 'say g("example.com")->code'

Proxy detection is enabled by default, but you can disable it with the
MOJO_PROXY environment variable.

  $ MOJO_PROXY=0 perl -Mojo -E 'say g("example.com")->body'

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 a

  my $app = a('/hello' => sub { shift->render(json => {hello => 'world'}) });

Create a route with L<Mojolicious::Lite/"any"> and return the current
L<Mojolicious::Lite> object. See also the L<Mojolicious::Lite> tutorial for
more argument variations.

  $ perl -Mojo -E 'a("/hello" => {text => "Hello Mojo!"})->start' daemon

=head2 b

  my $stream = b('lalala');

Turn string into a L<Mojo::ByteStream> object.

  $ perl -Mojo -E 'b(g("mojolicio.us")->body)->html_unescape->say'

=head2 c

  my $collection = c(1, 2, 3);

Turn list into a L<Mojo::Collection> object.

=head2 d

  my $res = d('example.com');
  my $res = d('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<DELETE> request with L<Mojo::UserAgent/"delete"> and return
resulting L<Mojo::Message::Response> object.

=head2 g

  my $res = g('example.com');
  my $res = g('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<GET> request with L<Mojo::UserAgent/"get"> and return resulting
L<Mojo::Message::Response> object.

  $ perl -Mojo -E 'say g("mojolicio.us")->dom("h1, h2, h3")->pluck("text")'

=head2 h

  my $res = h('example.com');
  my $res = h('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<HEAD> request with L<Mojo::UserAgent/"head"> and return resulting
L<Mojo::Message::Response> object.

=head2 j

  my $bytes = j({foo => 'bar'});
  my $array = j($bytes);
  my $hash  = j($bytes);

Encode Perl data structure or decode JSON with L<Mojo::JSON>.

  $ perl -Mojo -E 'b(j({hello => "world!"}))->spurt("hello.json")'

=head2 o

  my $res = o('example.com');
  my $res = o('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<OPTIONS> request with L<Mojo::UserAgent/"options"> and return
resulting L<Mojo::Message::Response> object.

=head2 p

  my $res = p('example.com');
  my $res = p('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<POST> request with L<Mojo::UserAgent/"post"> and return resulting
L<Mojo::Message::Response> object.

=head2 r

  my $perl = r({data => 'structure'});

Dump a Perl data structure with L<Data::Dumper>.

  perl -Mojo -E 'say r(g("example.com")->headers->to_hash)'

=head2 t

  my $res = t('example.com');
  my $res = t('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<PATCH> request with L<Mojo::UserAgent/"patch"> and return resulting
L<Mojo::Message::Response> object.

=head2 u

  my $res = u('example.com');
  my $res = u('http://example.com' => {DNT => 1} => 'Hi!');

Perform C<PUT> request with L<Mojo::UserAgent/"put"> and return resulting
L<Mojo::Message::Response> object.

=head2 x

  my $dom = x('<div>Hello!</div>');

Turn HTML/XML input into L<Mojo::DOM> object.

  $ perl -Mojo -E 'say x(b("test.html")->slurp)->at("title")->text'

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
