package ojo;
use Mojo::Base -strict;

use Benchmark qw(timeit timestr :hireswallclock);
use Mojo::ByteStream qw(b);
use Mojo::Collection qw(c);
use Mojo::DOM;
use Mojo::File qw(path);
use Mojo::JSON qw(j);
use Mojo::URL;
use Mojo::Util qw(dumper monkey_patch);

# Silent one-liners
$ENV{MOJO_LOG_LEVEL} ||= 'fatal';

sub import {

  # Mojolicious::Lite
  my $caller = caller;
  eval "package $caller; use Mojolicious::Lite; 1" or die $@;
  Mojo::Base->import(-strict, $] < 5.020 ? () : (-signatures));
  my $ua = $caller->app->ua;
  $ua->server->app->hook(around_action => sub { local $_ = $_[1]; $_[0]() });

  $ua->max_redirects(10) unless defined $ENV{MOJO_MAX_REDIRECTS};
  $ua->proxy->detect     unless defined $ENV{MOJO_PROXY};

  # The ojo DSL
  monkey_patch $caller,
    a => sub { $caller->can('any')->(@_) and return $ua->server->app },
    b => \&b,
    c => \&c,
    d => sub { $ua->delete(@_)->result },
    f => \&path,
    g => sub { $ua->get(@_)->result },
    h => sub { $ua->head(@_)->result },
    j => \&j,
    l => sub { Mojo::URL->new(@_) },
    n => sub (&@) { say STDERR timestr timeit($_[1] // 1, $_[0]) },
    o => sub { $ua->options(@_)->result },
    p => sub { $ua->post(@_)->result },
    r => \&dumper,
    t => sub { $ua->patch(@_)->result },
    u => sub { $ua->put(@_)->result },
    x => sub { Mojo::DOM->new(@_) };
}

1;

=encoding utf8

=head1 NAME

ojo - Fun one-liners with Mojo

=head1 SYNOPSIS

  $ perl -Mojo -E 'say g("mojolicious.org")->dom->at("title")->text'

=head1 DESCRIPTION

A collection of automatically exported functions for fun Perl one-liners. Ten redirects will be followed by default,
you can change this behavior with the C<MOJO_MAX_REDIRECTS> environment variable.

  $ MOJO_MAX_REDIRECTS=0 perl -Mojo -E 'say g("example.com")->code'

Proxy detection is enabled by default, but you can disable it with the C<MOJO_PROXY> environment variable.

  $ MOJO_PROXY=0 perl -Mojo -E 'say g("example.com")->body'

TLS certificate verification can be disabled with the C<MOJO_INSECURE> environment variable.

  $ MOJO_INSECURE=1 perl -Mojo -E 'say g("https://127.0.0.1:3000")->body'

Every L<ojo> one-liner is also a L<Mojolicious::Lite> application.

  $ perl -Mojo -E 'get "/" => {inline => "%= time"}; app->start' get /

On Perl 5.20+ L<subroutine signatures|perlsub/"Signatures"> will be enabled automatically.

  $ perl -Mojo -E 'a(sub ($c) { $c->render(text => "Hello!") })->start' get /

If it is not already defined, the C<MOJO_LOG_LEVEL> environment variable will be set to C<fatal>.

=head1 FUNCTIONS

L<ojo> implements the following functions, which are automatically exported.

=head2 a

  my $app = a('/hello' => sub { $_->render(json => {hello => 'world'}) });

Create a route with L<Mojolicious::Lite/"any"> and return the current L<Mojolicious::Lite> object. The current
controller object is also available to actions as C<$_>. See also L<Mojolicious::Guides::Tutorial> for more argument
variations.

  $ perl -Mojo -E 'a("/hello" => {text => "Hello Mojo!"})->start' daemon

=head2 b

  my $stream = b('lalala');

Turn string into a L<Mojo::ByteStream> object.

  $ perl -Mojo -E 'b(g("mojolicious.org")->body)->html_unescape->say'

=head2 c

  my $collection = c(1, 2, 3);

Turn list into a L<Mojo::Collection> object.

=head2 d

  my $res = d('example.com');
  my $res = d('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = d('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = d('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<DELETE> request with L<Mojo::UserAgent/"delete"> and return resulting L<Mojo::Message::Response> object.

=head2 f

  my $path = f('/home/sri/foo.txt');

Turn string into a L<Mojo::File> object.

  $ perl -Mojo -E 'say r j f("hello.json")->slurp'

=head2 g

  my $res = g('example.com');
  my $res = g('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = g('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = g('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<GET> request with L<Mojo::UserAgent/"get"> and return resulting L<Mojo::Message::Response> object.

  $ perl -Mojo -E 'say g("mojolicious.org")->dom("h1")->map("text")->join("\n")'

=head2 h

  my $res = h('example.com');
  my $res = h('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = h('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = h('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<HEAD> request with L<Mojo::UserAgent/"head"> and return resulting L<Mojo::Message::Response> object.

=head2 j

  my $bytes = j([1, 2, 3]);
  my $bytes = j({foo => 'bar'});
  my $value = j($bytes);

Encode Perl data structure or decode JSON with L<Mojo::JSON/"j">.

  $ perl -Mojo -E 'f("hello.json")->spurt(j {hello => "world!"})'

=head2 l

  my $url = l('https://mojolicious.org');

Turn a string into a L<Mojo::URL> object.

  $ perl -Mojo -E 'say l("/perldoc")->to_abs(l("https://mojolicious.org"))'

=head2 n

  n {...};
  n {...} 100;

Benchmark block and print the results to C<STDERR>, with an optional number of iterations, which defaults to C<1>.

  $ perl -Mojo -E 'n { say g("mojolicious.org")->code }'

=head2 o

  my $res = o('example.com');
  my $res = o('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = o('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = o('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<OPTIONS> request with L<Mojo::UserAgent/"options"> and return resulting L<Mojo::Message::Response> object.

=head2 p

  my $res = p('example.com');
  my $res = p('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = p('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = p('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<POST> request with L<Mojo::UserAgent/"post"> and return resulting L<Mojo::Message::Response> object.

=head2 r

  my $perl = r({data => 'structure'});

Dump a Perl data structure with L<Mojo::Util/"dumper">.

  perl -Mojo -E 'say r g("example.com")->headers->to_hash'

=head2 t

  my $res = t('example.com');
  my $res = t('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = t('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = t('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<PATCH> request with L<Mojo::UserAgent/"patch"> and return resulting L<Mojo::Message::Response> object.

=head2 u

  my $res = u('example.com');
  my $res = u('http://example.com' => {Accept => '*/*'} => 'Hi!');
  my $res = u('http://example.com' => {Accept => '*/*'} => form => {a => 'b'});
  my $res = u('http://example.com' => {Accept => '*/*'} => json => {a => 'b'});

Perform C<PUT> request with L<Mojo::UserAgent/"put"> and return resulting L<Mojo::Message::Response> object.

=head2 x

  my $dom = x('<div>Hello!</div>');

Turn HTML/XML input into L<Mojo::DOM> object.

  $ perl -Mojo -E 'say x(f("test.html")->slurp)->at("title")->text'

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
