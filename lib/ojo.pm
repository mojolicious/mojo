package ojo;

use strict;
use warnings;

# "I heard beer makes you stupid.
#  No I'm... doesn't."
use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::DOM;

# Silent oneliners
$ENV{MOJO_LOG_LEVEL} ||= 'fatal';

# "I'm sorry, guys. I never meant to hurt you.
#  Just to destroy everything you ever believed in."
sub import {

  # Prepare exports
  my $caller = caller;
  no strict 'refs';
  no warnings 'redefine';

  # Executable
  $ENV{MOJO_EXE} ||= (caller)[1];

  # Mojolicious::Lite
  eval "package $caller; use Mojolicious::Lite;";

  # Allow redirects
  Mojo::Client->singleton->max_redirects(1)
    unless defined $ENV{MOJO_MAX_REDIRECTS};

  # Functions
  *{"${caller}::Oo"} = *{"${caller}::b"} = \&b;
  *{"${caller}::oO"} = sub { _request(@_) };
  *{"${caller}::a"} =
    sub { *{"${caller}::any"}->(@_) and return *{"${caller}::app"}->() };
  *{"${caller}::d"} = sub { _request('delete',    @_) };
  *{"${caller}::f"} = sub { _request('post_form', @_) };
  *{"${caller}::g"} = sub { _request('get',       @_) };
  *{"${caller}::h"} = sub { _request('head',      @_) };
  *{"${caller}::p"} = sub { _request('post',      @_) };
  *{"${caller}::u"} = sub { _request('put',       @_) };
  *{"${caller}::w"} = sub { Mojo::Client->singleton->websocket(@_)->start };
  *{"${caller}::x"} = sub { Mojo::DOM->new->parse(@_) };
}

# "I wonder what the shroud of Turin tastes like."
sub _request {

  # Method
  my $method = $_[0] =~ /:|\// ? 'get' : lc shift;

  # Client
  my $client = Mojo::Client->singleton;

  # Transaction
  my $tx =
      $method eq 'post_form'
    ? $client->build_form_tx(@_)
    : $client->build_tx($method, @_);

  # Process
  $client->start($tx, sub { $tx = $_[1] });

  # Error
  my ($message, $code) = $tx->error;
  warn qq/Problem loading URL "$_[0]". ($message)\n/ if $message && !$code;

  return $tx->res;
}

1;
__END__

=head1 NAME

ojo - Fun Oneliners With Mojo!

=head1 SYNOPSIS

  perl -Mojo -e 'b(g("mojolicio.us")->dom->at("title")->text)->say'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners.

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<a>

  my $app = a('/' => sub { shift->render(json => {hello => 'world'}) });

Create a L<Mojolicious::Lite> route accepting all request methods and return
the application.

  perl -Mojo -e 'a("/" => {text => "Hello Mojo!"})->start' daemon

=head2 C<b>

  my $stream = b('lalala');

Turn input into a L<Mojo::ByteStream> object.

  perl -Mojo -e 'b(g("mojolicio.us")->body)->html_unescape->say'

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

=head2 C<f>

  my $res = f('http://kraih.com/foo' => {test => 123});
  my $res = f('http://kraih.com/foo', 'UTF-8', {test => 123});
  my $res = f(
    'http://kraih.com/foo',
    {test => 123},
    {'Content-Type' => 'multipart/form-data'}
  );
  my $res = f(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {'Content-Type' => 'multipart/form-data'}
  );
  my $res = f('http://kraih.com/foo', {file => {file => '/foo/bar.txt'}});
  my $res = f('http://kraih.com/foo', {file => {content => 'lalala'}});
  my $res = f(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}}
  );

Perform a C<POST> request for a form and turn response into a
L<Mojo::Message::Response> object.

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
One redirect will be followed by default, you can change this behavior with
the C<MOJO_MAX_REDIRECTS> environment variable.

  MOJO_MAX_REDIRECTS=0 perl -Mojo -e 'b(g("mojolicio.us")->code)->say'

=head2 C<h>

  my $res = h('http://mojolicio.us');
  my $res = h('http://mojolicio.us', {'X-Bender' => 'X_x'});
  my $res = h(
    'http://mojolicio.us',
    {'Content-Type' => 'text/plain'},
    'Hello!'
  );

Perform C<HEAD> request and turn response into a L<Mojo::Message::Response>
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

=head2 C<w>

  w('ws://mojolicio.us' => sub {...});

Open a WebSocket connection.

=head2 C<x>

  my $dom = x('<div>Hello!</div>');

Turn HTML5/XML input into L<Mojo::DOM> object.

  print x('<div>Hello!</div>')->at('div')->text;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
