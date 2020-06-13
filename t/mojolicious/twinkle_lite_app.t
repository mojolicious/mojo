use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojolicious::Lite;
use Mojo::Util;

# Custom format
app->renderer->default_format('foo');

# Twinkle template syntax
my $twinkle = {
  append        => '$self->res->headers->header("X-Append" => $prepended);',
  auto_escape   => 0,
  capture_end   => '-',
  capture_start => '+',
  escape        => sub {
    my $str = shift;
    $str =~ s/</&LT;/g;
    return $str;
  },
  escape_mark     => '*',
  expression_mark => '*',
  line_start      => '.',
  namespace       => 'TwinkleSandBoxTest',
  prepend         => 'my $prepended = $self->config("foo");',
  tag_end         => '**',
  tag_start       => '**',
  trim_mark       => '*'
};

# Renderer
plugin EPRenderer => {name => 'twinkle', template => $twinkle};

# Configuration
app->defaults(foo_test => 23);
my $config = plugin JSONConfig => {
  default  => {foo => 'bar'},
  ext      => 'conf',
  template => {%$twinkle, append => '$app->defaults(foo_test => 24)', prepend => 'my $foo = app->defaults("foo_test");'}
};
is $config->{foo},  'bar', 'right value';
is $config->{test}, 23,    'right value';
is app->defaults('foo_test'), 24, 'right value';

get '/' => {name => '<sebastian>'} => 'index';

get '/advanced' => 'advanced';

get '/rest' => sub {
  shift->respond_to(foo => {text => 'foo works!'}, html => {text => 'html works!'})
    ->res->headers->header('X-Rest' => 1);
};

get '/dead' => sub {die};

my $t = Test::Mojo->new;

# Basic template with "twinkle" syntax and "ep" layout
$t->get_ok('/')->status_is(200)->header_is('X-Append' => 'bar')
  ->content_like(qr/testHello <sebastian>!bar TwinkleSandBoxTest123/);

# Advanced template with "twinkle" syntax
$t->get_ok('/advanced')->status_is(200)->header_is('X-Append' => 'bar')->content_is("&LT;escape me>\n123423");

# REST request for "foo" format
$t->get_ok('/rest')->status_is(200)->header_is('X-Rest' => 1)->content_is('foo works!');

# REST request for "html" format
$t->get_ok('/rest.html')->status_is(200)->header_is('X-Rest' => 1)->content_is('html works!');

# Exception template with custom format
$t->get_ok('/dead')->status_is(500)->content_is("foo exception!\n");

done_testing();

__DATA__
@@ index.foo.twinkle
. layout 'twinkle';
Hello *** $name **!\
*** $prepended ** *** __PACKAGE__ **\

@@ layouts/twinkle.foo.ep
test<%= content %>123\

@@ advanced.foo.twinkle
.** "<escape me>"
. my $numbers = [1 .. 4];
 ** for my $i (@$numbers) { ***
 *** $i ***
 ** } ***
 ** my $foo = (+*** 23 **-)->();*** *** $foo ***

@@ exception.foo.ep
foo exception!

@@ not_found.foo.ep
foo not found!
