use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojo::JSON qw(false true);
use Mojolicious::Lite;

any [qw(POST PUT)] => '/json/echo' => [format => ['json']] => {format => undef} => sub {
  my $c = shift;
  $c->respond_to(json => {json => $c->req->json});
};

get '/accepts' => [format => ['html', 'json', 'txt', 'xml']] => {format => undef} => sub {
  my $c = shift;
  $c->render(json => {best => $c->accepts('html', 'json', 'txt')});
};

get '/wants_json' => [format => ['json', 'xml']] => {format => undef} => sub {
  my $c = shift;
  $c->render(json => {wants_json => $c->accepts('', 'json') ? \1 : \0});
};

under '/rest';

get [format => ['json', 'html', 'xml']] => {format => undef} => sub {
  my $c = shift;
  $c->respond_to(
    json => sub { $c->render(json => {just => 'works'}) },
    html => sub { $c->render(data => '<html><body>works') },
    xml  => sub { $c->render(data => '<just>works</just>') }
  );
};

post [format => ['json', 'html', 'xml', 'png']] => {format => undef} => sub {
  my $c = shift;
  $c->respond_to(
    json => {json => {just => 'works too'}},
    html => {text => '<html><body>works too'},
    xml  => {data => '<just>works too</just>'},
    any  => {text => 'works too', status => 201}
  );
};

my $t = Test::Mojo->new;

subtest 'Hash without format' => sub {
  $t->post_ok('/json/echo' => json => {hello => 'world'})->status_is(204)->content_is('');
};

subtest 'Hash with "json" format' => sub {
  $t->post_ok('/json/echo' => {Accept => 'application/json'} => json => {hello => 'world'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({hello => 'world'});
  my $tx = $t->ua->build_tx(PUT => '/json/echo' => {Accept => 'application/json'} => json => {hello => 'world'});
  $t->request_ok($tx)->status_is(200)->content_type_is('application/json;charset=UTF-8')->json_is({hello => 'world'});
};

subtest 'Array with "json" format' => sub {
  my $tx = $t->ua->build_tx(PUT => '/json/echo' => {Accept => 'application/json'} => json => [1, 2, 3]);
  $t->request_ok($tx)->status_is(200)->content_type_is('application/json;charset=UTF-8')->json_is([1, 2, 3]);
};

subtest 'Nothing' => sub {
  $t->get_ok('/accepts')->status_is(200)->json_is({best => 'html'});
};

subtest 'Unsupported' => sub {
  $t->get_ok('/accepts.xml')->status_is(200)->json_is({best => undef});
};

subtest '"json" format' => sub {
  $t->get_ok('/accepts.json')->status_is(200)->json_is({best => 'json'});
};

subtest '"txt" query' => sub {
  $t->get_ok('/accepts?_format=txt')->status_is(200)->json_is({best => 'txt'});
};

subtest 'Accept "txt"' => sub {
  $t->get_ok('/accepts' => {Accept => 'text/plain'})->status_is(200)->json_is({best => 'txt'});
};

subtest 'Accept "txt" with everything' => sub {
  $t->get_ok('/accepts.json?_format=txt' => {Accept => 'text/html'})->status_is(200)->json_is({best => 'txt'});
};

subtest 'Nothing' => sub {
  $t->get_ok('/wants_json')->status_is(200)->json_is({wants_json => false});
};

subtest 'Unsupported' => sub {
  $t->get_ok('/wants_json.xml')->status_is(200)->json_is({wants_json => false});
};

subtest 'Accept "json"' => sub {
  $t->get_ok('/wants_json' => {Accept => 'application/json'})->status_is(200)->json_is({wants_json => true});
};

subtest 'Ajax' => sub {
  my $ajax = 'text/html;q=0.1,application/json';
  $t->get_ok('/accepts' => {Accept => $ajax, 'X-Requested-With' => 'XMLHttpRequest'})
    ->status_is(200)
    ->json_is({best => 'json'});
};

subtest 'Nothing' => sub {
  $t->get_ok('/rest')->status_is(200)->content_type_is('text/html;charset=UTF-8')->text_is('html > body', 'works');
};

subtest '"html" format' => sub {
  $t->get_ok('/rest.html')->status_is(200)->content_type_is('text/html;charset=UTF-8')->text_is('html > body', 'works');
};

subtest 'Accept "html"' => sub {
  $t->get_ok('/rest' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'Accept "html" again' => sub {
  $t->get_ok('/rest' => {Accept => 'Text/Html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'Accept "html" with format' => sub {
  $t->get_ok('/rest.html' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'Accept "html" with quality' => sub {
  $t->get_ok('/rest' => {Accept => 'text/html;q=9'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest '"html" query' => sub {
  $t->get_ok('/rest?_format=html')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest '"html" format with query' => sub {
  $t->get_ok('/rest.html?_format=html')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'Accept "html" with query' => sub {
  $t->get_ok('/rest?_format=html' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'Accept "html" with everything' => sub {
  $t->get_ok('/rest.html?_format=html' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest '"json" format' => sub {
  $t->get_ok('/rest.json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest 'Accept "json"' => sub {
  $t->get_ok('/rest' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest 'Accept "json" again' => sub {
  $t->get_ok('/rest' => {Accept => 'APPLICATION/JSON'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest 'Accept "json" with format' => sub {
  $t->get_ok('/rest.json' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest 'Accept "json" with quality' => sub {
  $t->get_ok('/rest' => {Accept => 'application/json;q=9'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest '"json" query' => sub {
  $t->get_ok('/rest?_format=json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest '"json" format with query' => sub {
  $t->get_ok('/rest.json?_format=json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest 'Accept "json" with query' => sub {
  $t->get_ok('/rest?_format=json' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest 'Accept "json" with everything' => sub {
  $t->get_ok('/rest.json?_format=json' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

subtest '"xml" format' => sub {
  $t->get_ok('/rest.xml')->status_is(200)->content_type_is('application/xml')->text_is(just => 'works');
};

subtest 'Accept "xml"' => sub {
  $t->get_ok('/rest' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest 'Accept "xml" again' => sub {
  $t->get_ok('/rest' => {Accept => 'APPLICATION/XML'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest 'Accept "xml" with format' => sub {
  $t->get_ok('/rest.xml' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest 'Accept "xml" with quality' => sub {
  $t->get_ok('/rest' => {Accept => 'application/xml;q=9'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest '"xml" query' => sub {
  $t->get_ok('/rest?_format=xml')->status_is(200)->content_type_is('application/xml')->text_is(just => 'works');
};

subtest '"xml" format with query' => sub {
  $t->get_ok('/rest.xml?_format=xml')->status_is(200)->content_type_is('application/xml')->text_is(just => 'works');
};

subtest 'Accept "json" with query' => sub {
  $t->get_ok('/rest?_format=xml' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest 'Accept "json" with everything' => sub {
  $t->get_ok('/rest.xml?_format=xml' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest 'Unsupported accept' => sub {
  $t->get_ok('/rest' => {Accept => 'image/png'})->status_is(204)->content_is('');
};

subtest 'Nothing' => sub {
  $t->post_ok('/rest')->status_is(200)->content_type_is('text/html;charset=UTF-8')->text_is('html > body', 'works too');
};

subtest '"html" format' => sub {
  $t->post_ok('/rest.html')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html"' => sub {
  $t->post_ok('/rest' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html" again' => sub {
  $t->post_ok('/rest' => {Accept => 'Text/Html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html" with format' => sub {
  $t->post_ok('/rest.html' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html" with quality' => sub {
  $t->post_ok('/rest' => {Accept => 'text/html;q=9'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest '"html" query' => sub {
  $t->post_ok('/rest?_format=html')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest '"html" format with query' => sub {
  $t->post_ok('/rest.html?_format=html')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept html with query' => sub {
  $t->post_ok('/rest?_format=html' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html" with everything' => sub {
  $t->post_ok('/rest.html?_format=html' => {Accept => 'text/html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest '"html" form' => sub {
  $t->post_ok('/rest' => form => {_format => 'html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest '"html" format with form' => sub {
  $t->post_ok('/rest.html' => form => {_format => 'html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html" with form' => sub {
  $t->post_ok('/rest' => {Accept => 'text/html'} => form => {_format => 'html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest 'Accept "html" with everything, form alternative' => sub {
  $t->post_ok('/rest.html' => {Accept => 'text/html'} => form => {_format => 'html'})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works too');
};

subtest '"json" format' => sub {
  $t->post_ok('/rest.json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json"' => sub {
  $t->post_ok('/rest' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" again' => sub {
  $t->post_ok('/rest' => {Accept => 'APPLICATION/JSON'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" with format' => sub {
  $t->post_ok('/rest.json' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" with quality' => sub {
  $t->post_ok('/rest' => {Accept => 'application/json;q=9'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest '"json" query' => sub {
  $t->post_ok('/rest?_format=json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest '"json" format with query' => sub {
  $t->post_ok('/rest.json?_format=json')
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" with query' => sub {
  $t->post_ok('/rest?_format=json' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" with everything' => sub {
  $t->post_ok('/rest.json?_format=json' => {Accept => 'application/json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest '"json" form' => sub {
  $t->post_ok('/rest' => form => {_format => 'json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest '"json" format with form' => sub {
  $t->post_ok('/rest.json' => form => {_format => 'json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" with form' => sub {
  $t->post_ok('/rest' => {Accept => 'application/json'} => form => {_format => 'json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest 'Accept "json" with everything, form alternative' => sub {
  $t->post_ok('/rest.json' => {Accept => 'application/json'} => form => {_format => 'json'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works too'});
};

subtest '"xml" format' => sub {
  $t->post_ok('/rest.xml')->status_is(200)->content_type_is('application/xml')->text_is(just => 'works too');
};

subtest 'Accept "xml"' => sub {
  $t->post_ok('/rest' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "xml" again' => sub {
  $t->post_ok('/rest' => {Accept => 'APPLICATION/XML'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "xml" with format' => sub {
  $t->post_ok('/rest.xml' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "xml" with quality' => sub {
  $t->post_ok('/rest' => {Accept => 'application/xml;q=9'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest '"xml" query' => sub {
  $t->post_ok('/rest?_format=xml')->status_is(200)->content_type_is('application/xml')->text_is(just => 'works too');
};

subtest '"xml" format with query' => sub {
  $t->post_ok('/rest.xml?_format=xml')
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "json" with query' => sub {
  $t->post_ok('/rest?_format=xml' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "json" with everything' => sub {
  $t->post_ok('/rest.xml?_format=xml' => {Accept => 'application/xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest '"xml" form' => sub {
  $t->post_ok('/rest' => form => {_format => 'xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest '"xml" format with form' => sub {
  $t->post_ok('/rest.xml' => form => {_format => 'xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "json" with form' => sub {
  $t->post_ok('/rest' => {Accept => 'application/xml'} => form => {_format => 'xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Accept "json" with everything, form alternative' => sub {
  $t->post_ok('/rest.xml' => {Accept => 'application/xml'} => form => {_format => 'xml'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works too');
};

subtest 'Unsupported accept' => sub {
  $t->post_ok('/rest' => {Accept => 'image/png'})
    ->status_is(201)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is('works too');
};

subtest 'Unsupported everything' => sub {
  $t->post_ok('/rest.png?_format=jpg' => {Accept => 'image/whatever'})
    ->status_is(201)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is('works too');
};

subtest 'Unsupported format' => sub {
  $t->post_ok('/rest.png')->status_is(201)->content_type_is('text/html;charset=UTF-8')->content_is('works too');
};

subtest 'Unsupported format and query' => sub {
  $t->post_ok('/rest.png?_format=png')
    ->status_is(201)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is('works too');
};

subtest 'Does not exist' => sub {
  $t->get_ok('/nothing' => {Accept => 'image/png'})->status_is(404);
};

subtest 'Ajax' => sub {
  my $ajax = 'text/html;q=0.1,application/xml';
  $t->get_ok('/rest' => {Accept => $ajax, 'X-Requested-With' => 'XMLHttpRequest'})
    ->status_is(200)
    ->content_type_is('application/xml')
    ->text_is(just => 'works');
};

subtest 'Chrome 64' => sub {
  my $chrome = 'text/html,application/xhtml+xml,application/xml;q=0.9' . ',image/webp,image/apng,*/*;q=0.8';
  $t->get_ok('/rest.html' => {Accept => $chrome})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'Chrome 11 with query' => sub {
  my $chrome = 'text/html,application/xhtml+xml,application/xml;q=0.9' . ',image/webp,image/apng,*/*;q=0.8';
  $t->get_ok('/rest?_format=html' => {Accept => $chrome})
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->text_is('html > body', 'works');
};

subtest 'jQuery 1.8' => sub {
  my $jquery = 'application/json, text/javascript, */*; q=0.01';
  $t->get_ok('/rest' => {Accept => $jquery, 'X-Requested-With' => 'XMLHttpRequest'})
    ->status_is(200)
    ->content_type_is('application/json;charset=UTF-8')
    ->json_is({just => 'works'});
};

done_testing();
