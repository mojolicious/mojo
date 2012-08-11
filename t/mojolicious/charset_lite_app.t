use Mojo::Base -strict;

use utf8;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 41;

# "In the game of chess you can never let your adversary see your pieces."
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
    my ($r, $c, $output, $options) = @_;
    delete $options->{encoding};
    $$output = b($c->stash->{test})->encode('UTF-8')->to_string;
  }
);

# GET /
get '/' => 'index';

# POST /
post '/' => sub {
  my $self = shift;
  $self->render_text("foo: " . $self->param('foo'));
};

# POST /data
post '/data' => sub {
  my $self = shift;
  $self->render_data($self->req->body, format => 'bin');
};

# GET /unicode
get '/unicode' => sub {
  my $self = shift;
  $self->render(test => $yatta, handler => 'test', format => 'txt');
};

# GET /json
get '/json' => sub { shift->render_json({test => $yatta}) };

# GET /привет/мир
get '/привет/мир' => sub { shift->render_json({foo => $yatta}) };

my $t = Test::Mojo->new;

# Plain old ASCII
$t->post_form_ok('/' => {foo => 'yatta'})->status_is(200)
  ->content_is('foo: yatta');

# Send raw Shift_JIS octets (like browsers do)
$t->post_form_ok('/' => '' => {foo => $yatta_sjis})->status_is(200)
  ->content_type_unlike(qr/application/)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Send raw Shift_JIS octets (like browsers do, multipart message)
$t->post_form_ok(
  '/' => '' => {foo => $yatta_sjis},
  {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Send as string
$t->post_form_ok('/' => 'shift_jis' => {foo => $yatta})->status_is(200)
  ->content_type_like(qr/Shift_JIS/)->content_like(qr/$yatta/);

# Send as string (multipart message)
$t->post_form_ok(
  '/' => 'shift_jis' => {foo => $yatta},
  {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->content_type_like(qr/Shift_JIS/)
  ->content_like(qr/$yatta/);

# Unicode renderer
$t->get_ok('/unicode')->status_is(200)->content_type_is('text/plain')
  ->content_is(b($yatta)->encode('UTF-8')->to_string);

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
  ->json_content_is({test => $yatta});

# IRI
$t->get_ok('/привет/мир')->status_is(200)
  ->content_type_is('application/json')->json_content_is({foo => $yatta});

__DATA__
@@ index.html.ep
<p>やった</p>
