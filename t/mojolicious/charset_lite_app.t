use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::ByteStream 'b';
use Mojolicious::Lite;
use Test::Mojo;

my $yatta      = 'やった';
my $yatta_sjis = b($yatta)->encode('shift_jis')->to_string;

# Charset plugin
plugin Charset => {charset => 'Shift_JIS'};

# UTF-8 text renderer
app->renderer->add_handler(
  test => sub {
    my ($renderer, $c, $output, $options) = @_;
    delete $options->{encoding};
    $$output = b($c->stash->{test})->encode('UTF-8')->to_string;
  }
);

get '/' => 'index';

post '/' => sub {
  my $c = shift;
  $c->render(text => "foo: " . $c->param('foo'));
};

post '/data' => sub {
  my $c = shift;
  $c->render(data => $c->req->body, format => 'bin');
};

get '/unicode' => sub {
  my $c = shift;
  $c->render(test => $yatta, handler => 'test', format => 'txt');
};

get '/json' => sub { shift->render(json => {test => $yatta}) };

get '/привет/мир' => sub { shift->render(json => {foo => $yatta}) };

get '/params' => sub {
  my $c = shift;
  $c->render(json =>
      {params => $c->req->url->query->to_hash, yatta => $c->param(['yatta'])});
};

my $t = Test::Mojo->new;

# Plain old ASCII
$t->post_ok('/' => form => {foo => 'yatta'})->status_is(200)
  ->content_is('foo: yatta');

# Send raw Shift_JIS octets (like browsers do)
$t->post_ok('/' => form => {foo => $yatta_sjis} => charset => '')
  ->status_is(200)->content_type_unlike(qr/application/)
  ->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Send raw Shift_JIS octets (like browsers do, multipart message)
$t->post_ok('/' => {'Content-Type' => 'multipart/form-data'} => form =>
    {foo => $yatta_sjis} => charset => '')->status_is(200)
  ->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Send as string
$t->post_ok('/' => form => {foo => $yatta} => charset => 'shift_jis')
  ->status_is(200)->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Send as string (multipart message)
$t->post_ok('/' => {'Content-Type' => 'multipart/form-data'} => form =>
    {foo => $yatta} => charset => 'shift_jis')->status_is(200)
  ->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Unicode renderer
$t->get_ok('/unicode')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')->content_is($yatta);

# Templates in the DATA section should be written in UTF-8,
# and those in separate files in Shift_JIS (Mojo will do the decoding)
$t->get_ok('/')->status_is(200)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Unicode format
$t->get_ok("/.$yatta")->status_is(404);

# Send and receive raw Shift_JIS octets (like browsers do)
$t->post_ok('/data', $yatta_sjis)->status_is(200)->content_is($yatta_sjis);

# JSON data
$t->get_ok('/json')->status_is(200)->content_type_is('application/json')
  ->json_is({test => $yatta});

# IRI
$t->get_ok('/привет/мир')->status_is(200)
  ->content_type_is('application/json')->json_is({foo => $yatta});

# Shift_JIS parameters
my $url
  = $t->ua->server->url->path('/params')->query(foo => 3, yatta => $yatta);
$url->query->charset('shift_jis');
$t->get_ok($url)->status_is(200)
  ->json_is({params => {foo => 3, yatta => $yatta}, yatta => $yatta});

done_testing();

__DATA__
@@ index.html.ep
<p>やった</p>
