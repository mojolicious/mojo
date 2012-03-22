use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 19;

# "Pizza delivery for...
#  I. C. Weiner. Aww... I always thought by this stage in my life I'd be the
#  one making the crank calls."
use Mojolicious::Lite;
use Test::Mojo;

# Twinkle template syntax
my $twinkle = {
  capture_end     => '-',
  capture_start   => '+',
  escape_mark     => '*',
  expression_mark => '*',
  line_start      => '.',
  tag_end         => '**',
  tag_start       => '**',
  trim_mark       => '*'
};

# Plugins
plugin EPRenderer => {name => 'twinkle', template => $twinkle};
plugin PODRenderer => {no_perldoc => 1};
plugin PODRenderer =>
  {name => 'teapod', preprocess => 'twinkle', no_perldoc => 1};
my $config = plugin JSONConfig =>
  {default => {foo => 'bar'}, ext => 'conf', template => $twinkle};
is $config->{foo},  'bar', 'right value';
is $config->{test}, 23,    'right value';

# GET /
get '/' => {name => '<sebastian>'} => 'index';

# GET /advanced
get '/advanced' => 'advanced';

# GET /docs
get '/docs' => {codename => 'snowman'} => 'docs';

# GET /docs
get '/docs2' => {codename => 'snowman'} => 'docs2';

# GET /docs3
get '/docs3' => sub { shift->stash(codename => undef) } => 'docs';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/testHello <sebastian>!123/);

# GET /advanced
$t->get_ok('/advanced')->status_is(200)
  ->content_is("&lt;escape me&gt;\n123423");

# GET /docs
$t->get_ok('/docs')->status_is(200)->content_like(qr#<h3>snowman</h3>#);

# GET /docs2
$t->get_ok('/docs2')->status_is(200)->content_like(qr#<h2>snowman</h2>#);

# GET /docs3
$t->get_ok('/docs3')->status_is(200)->content_like(qr#<h3></h3>#);

# GET /perldoc (disabled)
$t->get_ok('/perldoc')->status_is(404);

__DATA__
@@ index.html.twinkle
. layout 'twinkle';
Hello **** $name **!\

@@ layouts/twinkle.html.ep
test<%= content %>123\

@@ advanced.html.twinkle
.* '<escape me>'
. my $numbers = [1 .. 4];
 ** for my $i (@$numbers) { ***
 *** $i ***
 ** } ***
 ** my $foo = capture +*** 23 **-*** *** $foo ***

@@ docs.html.pod
% no warnings;
<%= '=head3 ' . $codename %>

@@ docs2.html.teapod
.** '=head2 ' . $codename
