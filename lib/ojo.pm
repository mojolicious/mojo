package ojo;
use Mojo::Base -strict;

# "I heard beer makes you stupid.
#  No I'm... doesn't."
use Mojo::ByteStream 'b';
use Mojo::Collection 'c';
use Mojo::DOM;
use Mojo::JSON;
use Mojo::UserAgent;

# Silent oneliners
$ENV{MOJO_LOG_LEVEL} ||= 'fatal';

# User agent
my $UA = Mojo::UserAgent->new;

# "I'm sorry, guys. I never meant to hurt you.
#  Just to destroy everything you ever believed in."
sub import {

  # Prepare exports
  my $caller = caller;
  no strict 'refs';
  no warnings 'redefine';

  # Mojolicious::Lite
  eval "package $caller; use Mojolicious::Lite;";

  # Allow redirects
  $UA->max_redirects(10) unless defined $ENV{MOJO_MAX_REDIRECTS};

  # Detect proxy
  $UA->detect_proxy unless defined $ENV{MOJO_PROXY};

  # Application
  $UA->app(*{"${caller}::app"}->());

  # Functions
  *{"${caller}::a"} = sub { *{"${caller}::any"}->(@_) and return $UA->app };
  *{"${caller}::b"} = \&b;
  *{"${caller}::c"} = \&c;
  *{"${caller}::d"} = sub { _request($UA->build_tx(DELETE => @_)) };
  *{"${caller}::f"} = sub { _request($UA->build_form_tx(@_)) };
  *{"${caller}::g"} = sub { _request($UA->build_tx(GET => @_)) };
  *{"${caller}::h"} = sub { _request($UA->build_tx(HEAD => @_)) };
  *{"${caller}::j"} = sub {
    my $d = shift;
    my $j = Mojo::JSON->new;
    return ref $d ~~ [qw(ARRAY HASH)] ? $j->encode($d) : $j->decode($d);
  };
  *{"${caller}::n"} = sub { _request($UA->build_json_tx(@_)) };
  *{"${caller}::o"} = sub { _request($UA->build_tx(OPTIONS => @_)) };
  *{"${caller}::p"} = sub { _request($UA->build_tx(POST    => @_)) };
  *{"${caller}::r"} = sub { $UA->app->dumper(@_) };
  *{"${caller}::t"} = sub { _request($UA->build_tx(PATCH   => @_)) };
  *{"${caller}::u"} = sub { _request($UA->build_tx(PUT     => @_)) };
  *{"${caller}::x"} = sub { Mojo::DOM->new(@_) };
}

# "I wonder what the shroud of Turin tastes like."
sub _request {
  my $tx = $UA->start(@_);
  my ($message, $code) = $tx->error;
  warn qq/Problem loading URL "@{[$tx->req->url->to_abs]}". ($message)\n/
    if $message && !$code;
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
C<MOJO_MAX_REDIRECTS> environment variable.

  $ MOJO_MAX_REDIRECTS=0 perl -Mojo -E 'say g("mojolicio.us")->code'

Proxy detection is enabled by default, but you can disable it with the
C<MOJO_PROXY> environment variable.

  $ MOJO_PROXY=0 perl -Mojo -E 'say g("mojolicio.us")->body'

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<a>

  my $app = a('/hello' => sub { shift->render(json => {hello => 'world'}) });

Create a route with L<Mojolicious::Lite/"any"> and return the current
L<Mojolicious::Lite> object. See also the L<Mojolicious::Lite> tutorial for
more argument variations.

  $ perl -Mojo -E 'a("/hello" => {text => "Hello Mojo!"})->start' daemon

=head2 C<b>

  my $stream = b('lalala');

Turn string into a L<Mojo::ByteStream> object.

  $ perl -Mojo -E 'b(g("mojolicio.us")->body)->html_unescape->say'

=head2 C<c>

  my $collection = c(1, 2, 3);

Turn list into a L<Mojo::Collection> object.

=head2 C<d>

  my $res = d('mojolicio.us');
  my $res = d('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<DELETE> request with L<Mojo::UserAgent/"delete"> and return
resulting L<Mojo::Message::Response> object.

=head2 C<f>

  my $res = f('http://kraih.com' => {a => 'b'});
  my $res = f('kraih.com' => 'UTF-8' => {a => 'b'} => {DNT => 1});

Perform C<POST> request with L<Mojo::UserAgent/"post_form"> and return
resulting L<Mojo::Message::Response> object.

=head2 C<g>

  my $res = g('mojolicio.us');
  my $res = g('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<GET> request with L<Mojo::UserAgent/"get"> and return resulting
L<Mojo::Message::Response> object.

  $ perl -Mojo -E 'say g("mojolicio.us")->dom("h1, h2, h3")->pluck("text")'

=head2 C<h>

  my $res = h('mojolicio.us');
  my $res = h('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<HEAD> request with L<Mojo::UserAgent/"head"> and return resulting
L<Mojo::Message::Response> object.

=head2 C<j>

  my $bytes = j({foo => 'bar'});
  my $array = j($bytes);
  my $hash  = j($bytes);

Encode Perl data structure or decode JSON with L<Mojo::JSON>.

  $ perl -Mojo -E 'b(j({hello => "world!"}))->spurt("hello.json")'

=head2 C<n>

  my $res = n('http://kraih.com' => {a => 'b'});
  my $res = n('kraih.com' => {a => 'b'} => {DNT => 1});

Perform C<POST> request with L<Mojo::UserAgent/"post_json"> and return
resulting L<Mojo::Message::Response> object.

=head2 C<o>

  my $res = o('mojolicio.us');
  my $res = o('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<OPTIONS> request with L<Mojo::UserAgent/"options"> and return
resulting L<Mojo::Message::Response> object.

=head2 C<p>

  my $res = p('mojolicio.us');
  my $res = p('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<POST> request with L<Mojo::UserAgent/"post"> and return resulting
L<Mojo::Message::Response> object.

=head2 C<r>

  my $perl = r({data => 'structure'});

Dump a Perl data structure using L<Data::Dumper>.

  perl -Mojo -E 'say r(g("mojolicio.us")->headers->to_hash)'

=head2 C<t>

  my $res = t('mojolicio.us');
  my $res = t('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<PATCH> request with L<Mojo::UserAgent/"patch"> and return resulting
L<Mojo::Message::Response> object.

=head2 C<u>

  my $res = u('mojolicio.us');
  my $res = u('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<PUT> request with L<Mojo::UserAgent/"put"> and return resulting
L<Mojo::Message::Response> object.

=head2 C<x>

  my $dom = x('<div>Hello!</div>');

Turn HTML5/XML input into L<Mojo::DOM> object.

  $ perl -Mojo -E 'say x(b("test.html")->slurp)->at("title")->text'

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
