use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

any [qw(POST PUT)] => '/json/echo' => sub {
  my $c = shift;
  $c->respond_to(json => {json => $c->req->json});
};

get '/accepts' => sub {
  my $c = shift;
  $c->render(json => {best => $c->accepts('html', 'json', 'txt')});
};

get '/wants_json' => sub {
  my $c = shift;
  $c->render(json => {wants_json => \$c->accepts('', 'json')});
};

under '/rest';

get sub {
  my $c = shift;
  $c->respond_to(
    json => sub { $c->render(json => {just => 'works'}) },
    html => sub { $c->render(data => '<html><body>works') },
    xml  => sub { $c->render(data => '<just>works</just>') }
  );
};

post sub {
  my $c = shift;
  $c->respond_to(
    json => {json => {just => 'works too'}},
    html => {text => '<html><body>works too'},
    xml  => {data => '<just>works too</just>'},
    any => {text => 'works too', status => 201}
  );
};

my $t = Test::Mojo->new;

# Hash without format
$t->post_ok('/json/echo' => json => {hello => 'world'})->status_is(204)
  ->content_is('');

# Hash with "json" format
$t->post_ok(
  '/json/echo' => {Accept => 'application/json'} => json => {hello => 'world'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({hello => 'world'});
my $tx
  = $t->ua->build_tx(
  PUT => '/json/echo' => {Accept => 'application/json'} => json =>
    {hello => 'world'});
$t->request_ok($tx)->status_is(200)->content_type_is('application/json')
  ->json_is({hello => 'world'});

# Array with "json" format
$tx = $t->ua->build_tx(
  PUT => '/json/echo' => {Accept => 'application/json'} => json => [1, 2, 3]);
$t->request_ok($tx)->status_is(200)->content_type_is('application/json')
  ->json_is([1, 2, 3]);

# Nothing
$t->get_ok('/accepts')->status_is(200)->json_is({best => 'html'});

# Unsupported
$t->get_ok('/accepts.xml')->status_is(200)->json_is({best => undef});

# "json" format
$t->get_ok('/accepts.json')->status_is(200)->json_is({best => 'json'});

# "txt" query
$t->get_ok('/accepts?format=txt')->status_is(200)->json_is({best => 'txt'});

# Accept "txt"
$t->get_ok('/accepts' => {Accept => 'text/plain'})->status_is(200)
  ->json_is({best => 'txt'});

# Accept "txt" with everything
$t->get_ok('/accepts.html?format=json' => {Accept => 'text/plain'})
  ->status_is(200)->json_is({best => 'txt'});

# Nothing
$t->get_ok('/wants_json')->status_is(200)->json_is({wants_json => 0});

# Unsupported
$t->get_ok('/wants_json.xml')->status_is(200)->json_is({wants_json => 0});

# Accept "json"
$t->get_ok('/wants_json' => {Accept => 'application/json'})->status_is(200)
  ->json_is({wants_json => 1});

# Ajax
my $ajax = 'text/html;q=0.1,application/json';
$t->get_ok(
  '/accepts' => {Accept => $ajax, 'X-Requested-With' => 'XMLHttpRequest'})
  ->status_is(200)->json_is({best => 'json'});

# Nothing
$t->get_ok('/rest')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# "html" format
$t->get_ok('/rest.html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html"
$t->get_ok('/rest' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html" again
$t->get_ok('/rest' => {Accept => 'Text/Html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html" with format
$t->get_ok('/rest.html' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html" with wrong format
$t->get_ok('/rest.json' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html" with quality
$t->get_ok('/rest' => {Accept => 'text/html;q=9'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# "html" query
$t->get_ok('/rest?format=html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# "html" format with query
$t->get_ok('/rest.html?format=html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html" with query
$t->get_ok('/rest?format=html' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Accept "html" with everything
$t->get_ok('/rest.html?format=html' => {Accept => 'text/html'})
  ->status_is(200)->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# "json" format
$t->get_ok('/rest.json')->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works'});

# Accept "json"
$t->get_ok('/rest' => {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# Accept "json" again
$t->get_ok('/rest' => {Accept => 'APPLICATION/JSON'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# Accept "json" with format
$t->get_ok('/rest.json' => {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# Accept "json" with wrong format
$t->get_ok('/rest.png' => {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# Accept "json" with quality
$t->get_ok('/rest' => {Accept => 'application/json;q=9'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# "json" query
$t->get_ok('/rest?format=json')->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# "json" format with query
$t->get_ok('/rest.json?format=json')->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works'});

# Accept "json" with query
$t->get_ok('/rest?format=json' => {Accept => 'application/json'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works'});

# Accept "json" with everything
$t->get_ok('/rest.json?format=json' => {Accept => 'application/json'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works'});

# "xml" format
$t->get_ok('/rest.xml')->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works');

# Accept "xml"
$t->get_ok('/rest' => {Accept => 'application/xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# Accept "xml" again
$t->get_ok('/rest' => {Accept => 'APPLICATION/XML'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# Accept "xml" with format
$t->get_ok('/rest.xml' => {Accept => 'application/xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# Accept "xml" with wrong format
$t->get_ok('/rest.txt' => {Accept => 'application/xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# Accept "xml" with quality
$t->get_ok('/rest' => {Accept => 'application/xml;q=9'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# "xml" query
$t->get_ok('/rest?format=xml')->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# "xml" format with query
$t->get_ok('/rest.xml?format=xml')->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works');

# Accept "json" with query
$t->get_ok('/rest?format=xml' => {Accept => 'application/xml'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works');

# Accept "json" with everything
$t->get_ok('/rest.xml?format=xml' => {Accept => 'application/xml'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works');

# Unsupported accept
$t->get_ok('/rest' => {Accept => 'image/png'})->status_is(204)->content_is('');

# Nothing
$t->post_ok('/rest')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# "html" format
$t->post_ok('/rest.html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html"
$t->post_ok('/rest' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" again
$t->post_ok('/rest' => {Accept => 'Text/Html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" with format
$t->post_ok('/rest.html' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" with wrong format
$t->post_ok('/rest.json' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" with quality
$t->post_ok('/rest' => {Accept => 'text/html;q=9'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# "html" query
$t->post_ok('/rest?format=html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# "html" format with query
$t->post_ok('/rest.html?format=html')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept html with query
$t->post_ok('/rest?format=html' => {Accept => 'text/html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" with everything
$t->post_ok('/rest.html?format=html' => {Accept => 'text/html'})
  ->status_is(200)->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# "html" form
$t->post_ok('/rest' => form => {format => 'html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# "html" format with form
$t->post_ok('/rest.html' => form => {format => 'html'})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" with form
$t->post_ok('/rest' => {Accept => 'text/html'} => form => {format => 'html'})
  ->status_is(200)->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# Accept "html" with everything, form alternative
$t->post_ok(
  '/rest.html' => {Accept => 'text/html'} => form => {format => 'html'})
  ->status_is(200)->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works too');

# "json" format
$t->post_ok('/rest.json')->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works too'});

# Accept "json"
$t->post_ok('/rest' => {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# Accept "json" again
$t->post_ok('/rest' => {Accept => 'APPLICATION/JSON'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# Accept "json" with format
$t->post_ok('/rest.json' => {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# Accept "json" with wrong format
$t->post_ok('/rest.png' => {Accept => 'application/json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# Accept "json" with quality
$t->post_ok('/rest' => {Accept => 'application/json;q=9'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# "json" query
$t->post_ok('/rest?format=json')->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# "json" format with query
$t->post_ok('/rest.json?format=json')->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# Accept "json" with query
$t->post_ok('/rest?format=json' => {Accept => 'application/json'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works too'});

# Accept "json" with everything
$t->post_ok('/rest.json?format=json' => {Accept => 'application/json'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works too'});

# "json" form
$t->post_ok('/rest' => form => {format => 'json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# "json" format with form
$t->post_ok('/rest.json' => form => {format => 'json'})->status_is(200)
  ->content_type_is('application/json')->json_is({just => 'works too'});

# Accept "json" with form
$t->post_ok(
  '/rest' => {Accept => 'application/json'} => form => {format => 'json'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works too'});

# Accept "json" with everything, form alternative
$t->post_ok(
  '/rest.json' => {Accept => 'application/json'} => form => {format => 'json'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works too'});

# "xml" format
$t->post_ok('/rest.xml')->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works too');

# Accept "xml"
$t->post_ok('/rest' => {Accept => 'application/xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# Accept "xml" again
$t->post_ok('/rest' => {Accept => 'APPLICATION/XML'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# Accept "xml" with format
$t->post_ok('/rest.xml' => {Accept => 'application/xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# Accept "xml" with wrong format
$t->post_ok('/rest.txt' => {Accept => 'application/xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# Accept "xml" with quality
$t->post_ok('/rest' => {Accept => 'application/xml;q=9'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# "xml" query
$t->post_ok('/rest?format=xml')->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# "xml" format with query
$t->post_ok('/rest.xml?format=xml')->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# Accept "json" with query
$t->post_ok('/rest?format=xml' => {Accept => 'application/xml'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works too');

# Accept "json" with everything
$t->post_ok('/rest.xml?format=xml' => {Accept => 'application/xml'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works too');

# "xml" form
$t->post_ok('/rest' => form => {format => 'xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# "xml" format with form
$t->post_ok('/rest.xml' => form => {format => 'xml'})->status_is(200)
  ->content_type_is('application/xml')->text_is(just => 'works too');

# Accept "json" with form
$t->post_ok(
  '/rest' => {Accept => 'application/xml'} => form => {format => 'xml'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works too');

# Accept "json" with everything, form alternative
$t->post_ok(
  '/rest.xml' => {Accept => 'application/xml'} => form => {format => 'xml'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works too');

# Unsupported accept
$t->post_ok('/rest' => {Accept => 'image/png'})->status_is(201)
  ->content_type_is('text/html;charset=UTF-8')->content_is('works too');

# Unsupported accept with supported query
$t->post_ok('/rest?format=json' => {Accept => 'image/png'})->status_is(201)
  ->content_type_is('text/html;charset=UTF-8')->content_is('works too');

# Unsupported format
$t->post_ok('/rest.png')->status_is(201)
  ->content_type_is('text/html;charset=UTF-8')->content_is('works too');

# Unsupported format with supported query
$t->post_ok('/rest.png?format=json')->status_is(201)
  ->content_type_is('text/html;charset=UTF-8')->content_is('works too');

# Does not exist
$t->get_ok('/nothing' => {Accept => 'image/png'})->status_is(404);

# Ajax
$ajax = 'text/html;q=0.1,application/xml';
$t->get_ok(
  '/rest' => {Accept => $ajax, 'X-Requested-With' => 'XMLHttpRequest'})
  ->status_is(200)->content_type_is('application/xml')
  ->text_is(just => 'works');

# Internet Explorer 8
my $ie
  = 'image/jpeg, application/x-ms-application, image/gif, application/xaml+xml'
  . ', image/pjpeg, application/x-ms-xbap, application/x-shockwave-flash'
  . ', application/msword, */*';
$t->get_ok('/rest.html' => {Accept => $ie})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Internet Explorer 8 with query
$t->get_ok('/rest?format=html' => {Accept => $ie})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Chrome 11
my $chrome = 'application/xml,application/xhtml+xml,text/html;q=0.9'
  . ',text/plain;q=0.8,image/png,*/*;q=0.5';
$t->get_ok('/rest.html' => {Accept => $chrome})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# Chrome 11 with query
$t->get_ok('/rest?format=html' => {Accept => $chrome})->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->text_is('html > body', 'works');

# jQuery 1.8
my $jquery = 'application/json, text/javascript, */*; q=0.01';
$t->get_ok(
  '/rest' => {Accept => $jquery, 'X-Requested-With' => 'XMLHttpRequest'})
  ->status_is(200)->content_type_is('application/json')
  ->json_is({just => 'works'});

done_testing();
