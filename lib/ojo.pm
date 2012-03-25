package ojo;
use Mojo::Base -strict;

# "I heard beer makes you stupid.
#  No I'm... doesn't."
use Mojo::ByteStream 'b';
use Mojo::Collection 'c';
use Mojo::DOM;
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

  # Executable
  $ENV{MOJO_EXE} ||= (caller)[1];

  # Mojolicious::Lite
  eval "package $caller; use Mojolicious::Lite;";

  # Allow redirects
  $UA->max_redirects(10) unless defined $ENV{MOJO_MAX_REDIRECTS};

  # Application
  $UA->app(*{"${caller}::app"}->());

  # Functions
  *{"${caller}::Oo"} = *{"${caller}::b"} = \&b;
  *{"${caller}::c"} = \&c;
  *{"${caller}::oO"} = sub { _request(@_) };
  *{"${caller}::a"} =
    sub { *{"${caller}::any"}->(@_) and return *{"${caller}::app"}->() };
  *{"${caller}::d"} = sub { _request(DELETE  => @_) };
  *{"${caller}::f"} = sub { _request(FORM    => @_) };
  *{"${caller}::g"} = sub { _request(GET     => @_) };
  *{"${caller}::h"} = sub { _request(HEAD    => @_) };
  *{"${caller}::o"} = sub { _request(OPTIONS => @_) };
  *{"${caller}::p"} = sub { _request(POST    => @_) };
  *{"${caller}::t"} = sub { _request(PATCH   => @_) };
  *{"${caller}::u"} = sub { _request(PUT     => @_) };
  *{"${caller}::x"} = sub { Mojo::DOM->new(@_) };
}

# "I wonder what the shroud of Turin tastes like."
sub _request {

  # Method
  my $method = $_[0] =~ m#:|/# ? 'GET' : shift;

  # Transaction
  my $tx =
    $method eq 'FORM' ? $UA->build_form_tx(@_) : $UA->build_tx($method => @_);

  # Process
  $tx = $UA->start($tx);

  # Error
  my ($message, $code) = $tx->error;
  warn qq/Problem loading URL "$_[0]". ($message)\n/ if $message && !$code;

  return $tx->res;
}

1;
__END__

=head1 NAME

ojo - Fun Oneliners with Mojo!

=head1 SYNOPSIS

  $ perl -Mojo -E 'say g("mojolicio.us")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl oneliners.

=head1 FUNCTIONS

L<ojo> implements the following functions.

=head2 C<a>

  my $app = a('/' => sub { shift->render(json => {hello => 'world'}) });

Create a route with L<Mojolicious::Lite/"any"> and return the current
L<Mojolicious::Lite> object. See also the L<Mojolicious::Lite> tutorial for
more argument variations.

  $ perl -Mojo -E 'a("/" => {text => "Hello Mojo!"})->start' daemon

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

Perform C<POST> form request with L<Mojo::UserAgent/"post_form"> and return
resulting L<Mojo::Message::Response> object.

=head2 C<g>

  my $res = g('mojolicio.us');
  my $res = g('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<GET> request with L<Mojo::UserAgent/"get"> and return resulting
L<Mojo::Message::Response> object. Ten redirects will be followed by default,
you can change this behavior with the C<MOJO_MAX_REDIRECTS> environment
variable.

  $ MOJO_MAX_REDIRECTS=0 perl -Mojo -E 'say g("mojolicio.us")->code'

=head2 C<h>

  my $res = h('mojolicio.us');
  my $res = h('http://mojolicio.us' => {DNT => 1} => 'Hi!');

Perform C<HEAD> request with L<Mojo::UserAgent/"head"> and return resulting
L<Mojo::Message::Response> object.

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

  $ perl -Mojo -E 'say x("<div>Hello!</div>")->at("div")->text'

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
