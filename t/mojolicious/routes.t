use Mojo::Base -strict;

use Test::More;
use Mojolicious::Controller;
use Mojolicious::Routes;
use Mojolicious::Routes::Match;

# /clean
my $r = Mojolicious::Routes->new;
$r->any('/clean')->to(clean => 1)->name('very_clean');

# /clean/too
$r->any('/clean/too')->to(something => 1)->name('very_clean');

# /0
$r->any('0')->to(null => 1);

# /alternatives
# /alternatives/0
# /alternatives/test
# /alternatives/23
$r->any('/alternatives/:foo', [foo => [qw(0 test 23)]])->to(foo => 11);

# /alternatives2/0
# /alternatives2/test
# /alternatives2/23
$r->any('/alternatives2/:foo/', [foo => [qw(0 test 23)]]);

# /alternatives3/foo
# /alternatives3/foobar
$r->any('/alternatives3/:foo', [foo => [qw(foo foobar)]]);

# /alternatives4/foo
# /alternatives4/foo.bar
$r->any('/alternatives4/:foo', [foo => [qw(foo foo.bar)]]);

# /optional/*
# /optional/*/*
$r->any('/optional/:foo/:bar', [format => 1])->to(bar => 'test');

# /optional2
# /optional2/*
# /optional2/*/*
$r->any('/optional2/:foo', [format => 1])->to(foo => 'one')->any('/:bar')->to(bar => 'two');

# /*/test
my $test = $r->any('/:testcase/test')->to(action => 'test');

# /*/test/edit
$test->any('/edit')->to(action => 'edit')->name('test_edit');

# /*/testedit
$r->any('/:testcase/testedit')->to(action => 'testedit');

# /*/test/delete/*
$test->any('/delete/<id>', [id => qr/\d+/])->to(action => 'delete', id => 23);

# /test2
my $test2 = $r->any('/test2/')->inline(1)->to(testcase => 'test2');

# /test2 (inline)
my $test4 = $test2->any('/')->inline(1)->to(testcase => 'index');

# /test2/foo
$test4->any('/foo')->to(testcase => 'baz');

# /test2/bar
$test4->any('/bar')->to(testcase => 'lalala');

# /test2/baz
$test2->any('/baz')->to('just#works');

# /
$r->any('/')->to(testcase => 'hello', action => 'world');

# /wildcards/1/*
$r->any('/wildcards/1/<*wildcard>', [wildcard => qr/(?:.*)/])->to(testcase => 'wild', action => 'card');

# /wildcards/2/*
$r->any('/wildcards/2/*wildcard')->to(testcase => 'card', action => 'wild');

# /wildcards/3/*/foo
$r->any('/wildcards/3/<*wildcard>/foo')->to(testcase => 'very', action => 'dangerous');

# /wildcards/4/*/foo
$r->any('/wildcards/4/*wildcard/foo')->to(testcase => 'somewhat', action => 'dangerous');

# /format
# /format.*
$r->any('/format', [format => 1])->to(testcase => 'hello')->to(action => 'you', format => 'html');

# /format2.txt
$r->any('/format2', [format => qr/txt/])->to(testcase => 'we', action => 'howdy');

# /format3.txt
# /format3.text
$r->any('/format3', [format => [qw(txt text)]])->to(testcase => 'we', action => 'cheers');

# /format4
# /format4.html
$r->any('/format4', [format => ['html']])->to(testcase => 'us', action => 'yay', format => 'html');

# /format5
$r->any('/format5', [format => 0])->to(testcase => 'us', action => 'wow');

# /format6
$r->any('/format6', [format => 0])->to(testcase => 'us', action => 'doh', format => 'xml');

# /format7.foo
# /format7.foobar
$r->any('/format7', [format => [qw(foo foobar)]])->to('perl#rocks');

# /type/23
# /type/24
$r->add_type(my_num => [23, 24]);
$r->any('/type/<id:my_num>')->to('foo#bar');

# /articles/1/edit
# /articles/1/delete
# /articles/1/delete.json
my $inline = $r->any('/articles/:id')->inline(1)->to(testcase => 'articles', action => 'load', format => 'html');
$inline->any('/edit')->to(testcase => 'articles', action => 'edit');
$inline->any('/delete', [format => ['json']])->to(testcase => 'articles', action => 'delete', format => undef)
  ->name('articles_delete');

# GET /method/get
$r->any('/method/get', [format => ['html']])->methods('GET')
  ->to(testcase => 'method', action => 'get', format => undef);

# POST /method/post
$r->any('/method/post')->methods('post')->to(testcase => 'method', action => 'post');

# POST|GET /method/post_get
$r->any('/method/post_get')->methods(qw(POST get))->to(testcase => 'method', action => 'post_get');

# /simple/form
$r->any('/simple/form')->to('test-test#test');

# /regex/alternatives/*
$r->any('/regex/alternatives/:alternatives', [alternatives => qr/foo|bar|baz/])
  ->to(testcase => 'regex', action => 'alternatives');

# /versioned/1.0/test
# /versioned/1.0/test.xml
# /versioned/2.4/test
# /versioned/2.4/test.xml
my $versioned = $r->any('/versioned');
$versioned->any('/1.0')->to(testcase => 'bar')->any('/test', [format => ['xml']])->to(action => 'baz', format => undef);
$versioned->any('/2.4')->to(testcase => 'foo')->any('/test', [format => ['xml']])->to(action => 'bar', format => undef);

# /versioned/too/1.0
my $too = $r->any('/versioned/too')->to('too#');
$too->any('/1.0')->to('#foo');
$too->any('/2.0', [format => 0])->to('#bar');

# /multi/foo.bar
my $multi = $r->any('/multi');
$multi->any('/foo.bar', [format => 0])->to('just#works');
$multi->any('/bar.baz')->to('works#too', format => 'xml');

# /nodetect
# /nodetect2.txt
# /nodetect2.html
my $inactive = $r->any('/');
$inactive->any('/nodetect')->to('foo#none');
$inactive->any('/nodetect2', [format => ['txt', 'html']])->to('bar#hyper');

# /target/first
# /target/second
# /target/second.xml
# /source/third
# /source/third.xml
my $source = $r->any('/source')->to('source#');
my $first  = $source->any('/', [format => 0])->any('/first')->to('#first');
$source->any('/second', [format => ['xml']])->to('#second', format => undef);
my $third  = $source->any('/third', [format => ['xml']])->to('#third', format => undef);
my $target = $r->remove->any('/target')->to('target#');
my $second = $r->find('second');
is $second->render({}), '/source/second', 'right result';
$second->remove;
is $second->render({}), '/second', 'right result';
$target->add_child($first)->add_child($second);
is $second->render({}), '/target/second', 'right result';

# /websocket
$r->websocket('/websocket' => {testcase => 'ws'})->any('/')->to(action => 'just')->any->to(works => 1);

# /slash
# /slash.txt
$r->any('/slash')->to(testcase => 'just')->any('/', [format => ['txt']])->to(action => 'slash', format => undef);

# /missing/*/name
# /missing/too
# /missing/too/test
$r->any('/missing/:/name')->to('missing#placeholder');
$r->any('/missing/*/name')->to('missing#wildcard');
$r->any('/missing/too/*', ['' => ['test']])->to('missing#too', '' => 'missing');

# /partial/*
$r->any('/partial')->partial(1)->to('foo#bar');

# GET   /similar/*
# PATCH /similar/too
my $similar = $r->any('/similar')->methods(qw(DELETE GET PATCH))->inline(1);
$similar->any('/:something')->methods('GET')->to('similar#get');
$similar->any('/too')->methods('PATCH')->to('similar#post');

# /custom_pattern/test_*_test
my $custom = $r->get->to(four => 4);
$custom->pattern->quote_start('{')->quote_end('}')->placeholder_start('.')->relaxed_start('$')->wildcard_start('@');
$custom->parse('/custom_pattern/a_{.one}_b/{$two}/{@three}');

# /inherit/first.html
# /inherit/first.json
# /inherit/second
# /inherit/second.html
# /inherit/second.json
my $inherit_format = $r->any('/inherit' => [format => ['json', 'html']]);
$inherit_format->get('/first')->to('inherit#first');
$inherit_format->get('/second')->to('inherit#second', format => undef);

# /inherit2/first
# /inherit2/first.xml
# /inherit2/second
# /inherit2/second.html
# /inherit2/third
my $inherit_format2 = $r->any('/inherit2' => [format => ['xml']])->to('inherit#', format => undef);
$inherit_format2->get('/first')->to('#first', format => 'html');
$inherit_format2->post('/second' => [format => ['html']])->to('#second');
$inherit_format2->get('/third' => [format => 0])->to('#third');

subtest 'Cached lookup' => sub {
  my $fast = $r->any('/fast');
  is $r->find('fast'),   $fast, 'fast route found';
  is $r->lookup('fast'), $fast, 'fast route found';
  my $faster = $r->any('/faster')->name('fast');
  is $r->find('fast'),   $faster, 'faster route found';
  is $r->lookup('fast'), $fast,   'fast route found';
};

subtest 'Make sure stash stays clean' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/clean'});
  is $m->root,           $r,           'right root';
  is $m->endpoint->name, 'very_clean', 'right name';
  is_deeply $m->stack, [{clean => 1}], 'right strucutre';
  is $m->path_for->{path},           '/clean', 'right path';
  is $m->endpoint->suggested_method, 'GET',    'right method';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/clean/too'});
  is_deeply $m->stack, [{something => 1}], 'right strucutre';
  is $m->path_for->{path}, '/clean/too', 'right path';
};

subtest 'No match' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/does_not_exist'});
  is $m->root,     $r,    'right root';
  is $m->endpoint, undef, 'no endpoint';
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Introspect' => sub {
  is $r->find('very_clean')->to_string,      '/clean',               'right pattern';
  is $r->find('0')->to_string,               '/0',                   'right pattern';
  is $r->find('test_edit')->to_string,       '/:testcase/test/edit', 'right pattern';
  is $r->find('articles_delete')->to_string, '/articles/:id/delete', 'right pattern';
  ok !$r->find('nodetect')->pattern->constraints->{format}, 'no value';
  is $r->find('nodetect')->to->{controller}, 'foo', 'right testcase';
};

subtest 'Null route' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/0'});
  is_deeply $m->stack, [{null => 1}], 'right strucutre';
  is $m->path_for->{path}, '/0', 'right path';
};

subtest 'Alternatives with default' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives'});
  is_deeply $m->stack, [{foo => 11}], 'right strucutre';
  is $m->path_for->{path}, '/alternatives', 'right path';
  is $m->path_for(format => 'txt')->{path},               '/alternatives/11.txt', 'right path';
  is $m->path_for(foo    => 12, format => 'txt')->{path}, '/alternatives/12.txt', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/0'});
  is_deeply $m->stack, [{foo => 0}], 'right strucutre';
  is $m->path_for->{path}, '/alternatives/0', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/test'});
  is_deeply $m->stack, [{foo => 'test'}], 'right strucutre';
  is $m->path_for->{path}, '/alternatives/test', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/23'});
  is_deeply $m->stack, [{foo => 23}], 'right strucutre';
  is $m->path_for->{path}, '/alternatives/23', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/24'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/tset'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/00'});
  is_deeply $m->stack, [], 'empty stack';
  is $m->path_for('alternativesfoo')->{path},                             '/alternatives',        'right path';
  is $m->path_for('alternativesfoo', format => 'txt')->{path},            '/alternatives/11.txt', 'right path';
  is $m->path_for('alternativesfoo', foo => 12, format => 'txt')->{path}, '/alternatives/12.txt', 'right path';
};

subtest 'Alternatives without default' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/2'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives2/0'});
  is_deeply $m->stack, [{foo => 0}], 'right structure';
  is $m->path_for->{path}, '/alternatives2/0', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives2/test'});
  is_deeply $m->stack, [{foo => 'test'}], 'right structure';
  is $m->path_for->{path}, '/alternatives2/test', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives2/23'});
  is_deeply $m->stack, [{foo => 23}], 'right structure';
  is $m->path_for->{path}, '/alternatives2/23', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives2/24'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives2/tset'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives2/00'});
  is_deeply $m->stack, [], 'empty stack';
  is $m->path_for('alternatives2foo')->{path},           '/alternatives2/',  'right path';
  is $m->path_for('alternatives2foo', foo => 0)->{path}, '/alternatives2/0', 'right path';
};

subtest 'Alternatives with similar start' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives3/foo'});
  is_deeply $m->stack, [{foo => 'foo'}], 'right structure';
  is $m->path_for->{path}, '/alternatives3/foo', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives3/foobar'});
  is_deeply $m->stack, [{foo => 'foobar'}], 'right structure';
  is $m->path_for->{path}, '/alternatives3/foobar', 'right path';
};

subtest 'Alternatives with special characters' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives4/foo'});
  is_deeply $m->stack, [{foo => 'foo'}], 'right structure';
  is $m->path_for->{path}, '/alternatives4/foo', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives4/foo.bar'});
  is_deeply $m->stack, [{foo => 'foo.bar'}], 'right structure';
  is $m->path_for->{path}, '/alternatives4/foo.bar', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives4/foobar'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives4/bar'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives4/bar.foo'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Optional placeholder' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional/23'});
  is_deeply $m->stack, [{foo => 23, bar => 'test'}], 'right structure';
  is $m->path_for->{path},                                    '/optional/23',          'right path';
  is $m->path_for(format => 'txt')->{path},                   '/optional/23/test.txt', 'right path';
  is $m->path_for(foo => 12, format => 'txt')->{path},        '/optional/12/test.txt', 'right path';
  is $m->path_for('optionalfoobar', format => 'txt')->{path}, '/optional/23/test.txt', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional/23/24'});
  is_deeply $m->stack, [{foo => 23, bar => 24}], 'right structure';
  is $m->path_for->{path},                             '/optional/23/24',     'right path';
  is $m->path_for(format => 'txt')->{path},            '/optional/23/24.txt', 'right path';
  is $m->path_for('optionalfoobar')->{path},           '/optional/23/24',     'right path';
  is $m->path_for('optionalfoobar', foo => 0)->{path}, '/optional/0/24',      'right path';
};

subtest 'Optional placeholders in nested routes' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional2'});
  is_deeply $m->stack, [{foo => 'one', bar => 'two'}], 'right structure';
  is $m->path_for->{path}, '/optional2', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional2.txt'});
  is_deeply $m->stack, [{foo => 'one', bar => 'two', format => 'txt'}], 'right structure';
  is $m->path_for->{path}, '/optional2', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional2/three'});
  is_deeply $m->stack, [{foo => 'three', bar => 'two'}], 'right structure';
  is $m->path_for->{path}, '/optional2/three', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional2/three/four'});
  is_deeply $m->stack, [{foo => 'three', bar => 'four'}], 'right structure';
  is $m->path_for->{path}, '/optional2/three/four', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/optional2/three/four.txt'});
  is_deeply $m->stack, [{foo => 'three', bar => 'four', format => 'txt'}], 'right structure';
  is $m->path_for->{path}, '/optional2/three/four', 'right path';
};

subtest 'Real world example using most features at once' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/articles/1/edit'});
  my @stack = (
    {testcase => 'articles', action => 'load', id => 1, format => 'html'},
    {testcase => 'articles', action => 'edit', id => 1, format => 'html'}
  );
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path},                                     '/articles/1/edit',      'right path';
  is $m->path_for(format => 'html')->{path},                   '/articles/1/edit.html', 'right path';
  is $m->path_for('articles_delete', format => undef)->{path}, '/articles/1/delete',    'right path';
  is $m->path_for('articles_delete')->{path},                  '/articles/1/delete',    'right path';
  is $m->path_for('articles_delete', id => 12)->{path},        '/articles/12/delete',   'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/articles/1/delete'});
  @stack = (
    {testcase => 'articles', action => 'load',   id => 1, format => 'html'},
    {testcase => 'articles', action => 'delete', id => 1, format => undef}
  );
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path}, '/articles/1/delete', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/articles/1/delete.json'});
  @stack = (
    {testcase => 'articles', action => 'load',   id => 1, format => 'json'},
    {testcase => 'articles', action => 'delete', id => 1, format => 'json'}
  );
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path}, '/articles/1/delete.json', 'right path';
};

subtest 'Root' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/'});
  is_deeply $m->stack, [{testcase => 'hello', action => 'world'}], 'right structure';
  is $m->path_for->{path}, '/', 'right path';
};

subtest 'Path and captures' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/foo/test/edit'});
  is_deeply $m->stack, [{testcase => 'foo', action => 'edit'}], 'right structure';
  is $m->path_for->{path}, '/foo/test/edit', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/foo/testedit'});
  is_deeply $m->stack, [{testcase => 'foo', action => 'testedit'}], 'right structure';
  is $m->path_for->{path},           '/foo/testedit', 'right path';
  is $m->endpoint->suggested_method, 'GET',           'right method';
};

subtest 'Optional captures in sub route with requirement' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/bar/test/delete/22'});
  is_deeply $m->stack, [{testcase => 'bar', action => 'delete', id => 22}], 'right structure';
  is $m->path_for->{path}, '/bar/test/delete/22', 'right path';
};

subtest 'Defaults in sub route' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/bar/test/delete'});
  is_deeply $m->stack, [{testcase => 'bar', action => 'delete', id => 23}], 'right structure';
  is $m->path_for->{path}, '/bar/test/delete', 'right path';
};

subtest 'Chained routes' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/test2/foo'});
  my @stack = ({testcase => 'test2'}, {testcase => 'index'}, {testcase => 'baz'});
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path}, '/test2/foo', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/test2/bar'});
  @stack = ({testcase => 'test2'}, {testcase => 'index'}, {testcase => 'lalala'});
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path}, '/test2/bar', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/test2/baz'});
  @stack = ({testcase => 'test2'}, {testcase => 'test2', controller => 'just', action => 'works'});
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path}, '/test2/baz', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/test2baz'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Named path_for' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/alternatives/test'});
  is $m->path_for->{path}, '/alternatives/test', 'right path';
  is $m->path_for('test_edit', testcase => 'foo')->{path},   '/foo/test/edit', 'right path';
  is $m->path_for('test_edit', {testcase => 'foo'})->{path}, '/foo/test/edit', 'right path';
};

subtest 'Wildcards' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/1/hello/there'});
  is_deeply $m->stack, [{testcase => 'wild', action => 'card', wildcard => 'hello/there'}], 'right structure';
  is $m->path_for->{path},                 '/wildcards/1/hello/there', 'right path';
  is $m->path_for(wildcard => '')->{path}, '/wildcards/1/',            'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/2/hello/there'});
  is_deeply $m->stack, [{testcase => 'card', action => 'wild', wildcard => 'hello/there'}], 'right structure';
  is $m->path_for->{path}, '/wildcards/2/hello/there', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/3/hello/there/foo'});
  is_deeply $m->stack, [{testcase => 'very', action => 'dangerous', wildcard => 'hello/there'}], 'right structure';
  is $m->path_for->{path}, '/wildcards/3/hello/there/foo', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/4/hello/there/foo'});
  is_deeply $m->stack, [{testcase => 'somewhat', action => 'dangerous', wildcard => 'hello/there'}], 'right structure';
  is $m->path_for->{path}, '/wildcards/4/hello/there/foo', 'right path';
};

subtest 'Special characters' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/1/♥'});
  is_deeply $m->stack, [{testcase => 'wild', action => 'card', wildcard => '♥'}], 'right structure';
  is $m->path_for->{path}, '/wildcards/1/♥', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/1/http://www.google.com'});
  my @stack = ({testcase => 'wild', action => 'card', wildcard => 'http://www.google.com'});
  is_deeply $m->stack, \@stack, 'right structure';
  is $m->path_for->{path}, '/wildcards/1/http://www.google.com', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/wildcards/1/%foo%bar%'});
  is_deeply $m->stack, [{testcase => 'wild', action => 'card', wildcard => '%foo%bar%'}], 'right structure';
  is $m->path_for->{path}, '/wildcards/1/%foo%bar%', 'right path';
};

subtest 'Format' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format'});
  is_deeply $m->stack, [{testcase => 'hello', action => 'you', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/format', 'right path';
  is $m->path_for(format => undef)->{path},  '/format',      'right path';
  is $m->path_for(format => 'html')->{path}, '/format.html', 'right path';
  is $m->path_for(format => 'txt')->{path},  '/format.txt',  'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format.html'});
  is_deeply $m->stack, [{testcase => 'hello', action => 'you', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/format', 'right path';
  is $m->path_for(format => undef)->{path},  '/format',      'right path';
  is $m->path_for(format => 'html')->{path}, '/format.html', 'right path';
  is $m->path_for(format => 'txt')->{path},  '/format.txt',  'right path';
};

subtest 'Format with regex constraint' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format2'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format2.txt'});
  is_deeply $m->stack, [{testcase => 'we', action => 'howdy', format => 'txt'}], 'right structure';
  is $m->path_for->{path}, '/format2.txt', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format2.html'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format2.txt.txt'});
  is_deeply $m->stack, [], 'empty stack';
  is $m->path_for('format2', format => 'txt')->{path}, '/format2.txt', 'right path';
};

subtest 'Format with constraint alternatives' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format3'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format3.txt'});
  is_deeply $m->stack, [{testcase => 'we', action => 'cheers', format => 'txt'}], 'right structure';
  is $m->path_for->{path}, '/format3.txt', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format3.text'});
  is_deeply $m->stack, [{testcase => 'we', action => 'cheers', format => 'text'}], 'right structure';
  is $m->path_for->{path}, '/format3.text', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format3.html'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format3.txt.txt'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Format with constraint and default' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format4'});
  is_deeply $m->stack, [{testcase => 'us', action => 'yay', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/format4.html', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format4.html'});
  is_deeply $m->stack, [{testcase => 'us', action => 'yay', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/format4.html', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format4.txt'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format4.txt.html'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Forbidden format' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format5'});
  is_deeply $m->stack, [{testcase => 'us', action => 'wow'}], 'right structure';
  is $m->path_for->{path}, '/format5', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format5.html'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Forbidden format and default' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format6'});
  is_deeply $m->stack, [{testcase => 'us', action => 'doh', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/format6', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format6.xml'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Formats with similar start' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format7.foo'});
  is_deeply $m->stack, [{controller => 'perl', action => 'rocks', format => 'foo'}], 'right structure';
  is $m->path_for->{path}, '/format7.foo', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format7.foobar'});
  is_deeply $m->stack, [{controller => 'perl', action => 'rocks', format => 'foobar'}], 'right structure';
  is $m->path_for->{path}, '/format7.foobar', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/format7.foobarbaz'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Placeholder types' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/type/23'});
  is_deeply $m->stack, [{controller => 'foo', action => 'bar', id => 23}], 'right structure';
  is $m->path_for->{path}, '/type/23', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/type/24'});
  is_deeply $m->stack, [{controller => 'foo', action => 'bar', id => 24}], 'right structure';
  is $m->path_for->{path}, '/type/24', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/type/25'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Format inheritance' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/first.html'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'first', format => 'html'}], 'right structure';
  is $m->path_for->{path},                  '/inherit/first.html', 'right path';
  is $m->path_for(format => undef)->{path}, '/inherit/first',      'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/first.json'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'first', format => 'json'}], 'right structure';
  is $m->path_for->{path}, '/inherit/first.json', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/first'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/first.xml'});
  is_deeply $m->stack, [], 'empty stack';

  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/second.html'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'second', format => 'html'}], 'right structure';
  is $m->path_for->{path},                  '/inherit/second.html', 'right path';
  is $m->path_for(format => undef)->{path}, '/inherit/second',      'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/second.json'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'second', format => 'json'}], 'right structure';
  is $m->path_for->{path}, '/inherit/second.json', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit/second'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'second', format => undef}], 'right structure';
  is $m->path_for->{path}, '/inherit/second', 'right path';

  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit2/first'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'first', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/inherit2/first.html', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit2/first.xml'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'first', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/inherit2/first.xml', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit2/first.html'});
  is_deeply $m->stack, [], 'empty stack';

  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'POST', path => '/inherit2/second'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'second', format => undef}], 'right structure';
  is $m->path_for->{path}, '/inherit2/second', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'POST', path => '/inherit2/second.html'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'second', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/inherit2/second.html', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'POST', path => '/inherit2/second.xml'});
  is_deeply $m->stack, [], 'empty stack';

  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit2/third'});
  is_deeply $m->stack, [{controller => 'inherit', action => 'third', format => undef}], 'right structure';
  is $m->path_for->{path}, '/inherit2/third', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/inherit2/third.xml'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Request methods' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/method/get.html'});
  is_deeply $m->stack, [{testcase => 'method', action => 'get', format => 'html'}], 'right structure';
  is $m->path_for->{path},           '/method/get.html', 'right path';
  is $m->endpoint->suggested_method, 'GET',              'right method';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'POST', path => '/method/post'});
  is_deeply $m->stack, [{testcase => 'method', action => 'post'}], 'right structure';
  is $m->path_for->{path},           '/method/post', 'right path';
  is $m->endpoint->suggested_method, 'POST',         'right method';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/method/post_get'});
  is_deeply $m->stack, [{testcase => 'method', action => 'post_get'}], 'right structure';
  is $m->path_for->{path}, '/method/post_get', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'POST', path => '/method/post_get'});
  is_deeply $m->stack, [{testcase => 'method', action => 'post_get'}], 'right structure';
  is $m->path_for->{path},           '/method/post_get', 'right path';
  is $m->endpoint->suggested_method, 'GET',              'right method';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'DELETE', path => '/method/post_get'});
  is_deeply $m->stack, [], 'empty stack';
  is $m->path_for->{path}, undef, 'no path';
};

subtest 'Not found' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/not_found'});
  is $m->path_for('test_edit', testcase => 'foo')->{path}, '/foo/test/edit', 'right path';
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Simplified form' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/simple/form'});
  is_deeply $m->stack, [{controller => 'test-test', action => 'test'}], 'right structure';
  is $m->path_for->{path},            '/simple/form', 'right path';
  is $m->path_for('current')->{path}, '/simple/form', 'right path';
};

subtest 'Special edge case with intermediate destinations (regex)' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/regex/alternatives/foo'});
  is_deeply $m->stack, [{testcase => 'regex', action => 'alternatives', alternatives => 'foo'}], 'right structure';
  is $m->path_for->{path}, '/regex/alternatives/foo', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/regex/alternatives/bar'});
  is_deeply $m->stack, [{testcase => 'regex', action => 'alternatives', alternatives => 'bar'}], 'right structure';
  is $m->path_for->{path}, '/regex/alternatives/bar', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/regex/alternatives/baz'});
  is_deeply $m->stack, [{testcase => 'regex', action => 'alternatives', alternatives => 'baz'}], 'right structure';
  is $m->path_for->{path}, '/regex/alternatives/baz', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/regex/alternatives/yada'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Route with version' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/1.0/test'});
  is_deeply $m->stack, [{testcase => 'bar', action => 'baz', format => undef}], 'right structure';
  is $m->path_for->{path}, '/versioned/1.0/test', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/1.0/test.xml'});
  is_deeply $m->stack, [{testcase => 'bar', action => 'baz', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/versioned/1.0/test.xml', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/2.4/test'});
  is_deeply $m->stack, [{testcase => 'foo', action => 'bar', format => undef}], 'right structure';
  is $m->path_for->{path}, '/versioned/2.4/test', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/2.4/test.xml'});
  is_deeply $m->stack, [{testcase => 'foo', action => 'bar', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/versioned/2.4/test.xml', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/3.0/test'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/3.4/test'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/0.3/test'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Route with version at the end' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/too/1.0'});
  is_deeply $m->stack, [{controller => 'too', action => 'foo'}], 'right structure';
  is $m->path_for->{path}, '/versioned/too/1.0', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/versioned/too/2.0'});
  is_deeply $m->stack, [{controller => 'too', action => 'bar'}], 'right structure';
  is $m->path_for->{path}, '/versioned/too/2.0', 'right path';
};

subtest 'Multiple extensions' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/multi/foo.bar'});
  is_deeply $m->stack, [{controller => 'just', action => 'works'}], 'right structure';
  is $m->path_for->{path}, '/multi/foo.bar', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/multi/foo.bar.baz'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/multi/bar.baz'});
  is_deeply $m->stack, [{controller => 'works', action => 'too', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/multi/bar.baz', 'right path';
};

subtest 'Disabled format detection inheritance' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/nodetect'});
  is_deeply $m->stack, [{controller => 'foo', action => 'none'}], 'right structure';
  is $m->path_for->{path}, '/nodetect', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/nodetect.txt'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/nodetect2.txt'});
  is_deeply $m->stack, [{controller => 'bar', action => 'hyper', format => 'txt'}], 'right structure';
  is $m->path_for->{path}, '/nodetect2.txt', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/nodetect2.html'});
  is_deeply $m->stack, [{controller => 'bar', action => 'hyper', format => 'html'}], 'right structure';
  is $m->path_for->{path}, '/nodetect2.html', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/nodetect2'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/nodetect2.xml'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Removed routes' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/target/first'});
  is_deeply $m->stack, [{controller => 'target', action => 'first'}], 'right structure';
  is $m->path_for->{path}, '/target/first', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/target/first.xml'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/source/first'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/target/second'});
  is_deeply $m->stack, [{controller => 'target', action => 'second', format => undef}], 'right structure';
  is $m->path_for->{path}, '/target/second', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/target/second.xml'});
  is_deeply $m->stack, [{controller => 'target', action => 'second', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/target/second.xml', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/source/second'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/source/third'});
  is_deeply $m->stack, [{controller => 'source', action => 'third', format => undef}], 'right structure';
  is $m->path_for->{path}, '/source/third', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/source/third.xml'});
  is_deeply $m->stack, [{controller => 'source', action => 'third', format => 'xml'}], 'right structure';
  is $m->path_for->{path}, '/source/third.xml', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/target/third'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'WebSocket' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/websocket'});
  is_deeply $m->stack, [], 'empty stack';
  $m->find($c => {method => 'GET', path => '/websocket', websocket => 1});
  is_deeply $m->stack, [{testcase => 'ws', action => 'just', works => 1}], 'right structure';
  is $m->path_for->{path}, '/websocket', 'right path';
  ok $m->path_for->{websocket}, 'is a websocket';
};

subtest 'Just a slash with a format after a path' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/slash.txt'});
  is_deeply $m->stack, [{testcase => 'just', action => 'slash', format => 'txt'}], 'right structure';
  is $m->path_for->{path}, '/slash.txt', 'right path';
  ok !$m->path_for->{websocket}, 'not a websocket';
  is $m->path_for(format => 'html')->{path}, '/slash.html', 'right path';
};

subtest 'Nameless placeholder' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/missing/foo/name'});
  is_deeply $m->stack, [{controller => 'missing', action => 'placeholder', '' => 'foo'}], 'right structure';
  is $m->path_for->{path},              '/missing/foo/name', 'right path';
  is $m->path_for('' => 'bar')->{path}, '/missing/bar/name', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/missing/foo/bar/name'});
  is_deeply $m->stack, [{controller => 'missing', action => 'wildcard', '' => 'foo/bar'}], 'right structure';
  is $m->path_for->{path},                  '/missing/foo/bar/name', 'right path';
  is $m->path_for('' => 'bar/baz')->{path}, '/missing/bar/baz/name', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/missing/too/test'});
  is_deeply $m->stack, [{controller => 'missing', action => 'too', '' => 'test'}], 'right structure';
  is $m->path_for->{path},                  '/missing/too/test',    'right path';
  is $m->path_for('' => 'bar/baz')->{path}, '/missing/too/bar/baz', 'right path';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/missing/too/tset'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/missing/too'});
  is_deeply $m->stack, [{controller => 'missing', action => 'too', '' => 'missing'}], 'right structure';
  is $m->path_for->{path}, '/missing/too', 'right path';
};

subtest 'Partial route' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/partial/test'});
  is_deeply $m->stack, [{controller => 'foo', action => 'bar', 'path' => '/test'}], 'right structure';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/partial.test'});
  is_deeply $m->stack, [{controller => 'foo', action => 'bar', 'path' => '.test'}], 'right structure';
};

subtest 'Similar routes with placeholders' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/similar/too'});
  is_deeply $m->stack, [{}, {controller => 'similar', action => 'get', 'something' => 'too'}], 'right structure';
  is $m->endpoint->suggested_method, 'GET', 'right method';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'PATCH', path => '/similar/too'});
  is_deeply $m->stack, [{}, {controller => 'similar', action => 'post'}], 'right structure';
  is $m->endpoint->suggested_method, 'PATCH', 'right method';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'DELETE', path => '/similar/too'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Custom pattern' => sub {
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/custom_pattern/a_123_b/c.123/d/123'});
  is_deeply $m->stack, [{one => 123, two => 'c.123', three => 'd/123', four => 4}], 'right structure';
  is $m->path_for->{path}, '/custom_pattern/a_123_b/c.123/d/123', 'right path';
};

subtest 'Unknown placeholder type (matches nothing)' => sub {
  $r = Mojolicious::Routes->new;
  $r->get('/<foo:does_not_exist>');
  my $c = Mojolicious::Controller->new;
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/test'});
  is_deeply $m->stack, [], 'empty stack';
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/23'});
  is_deeply $m->stack, [], 'empty stack';
};

subtest 'Intuitive controller (when it is not app)' => sub {
  my $c = Mojolicious::Controller->new;
  
  $r = Mojolicious::Routes->new;
  my $panel = $r->any('/panel')->to('panel'); # not added # at the end
  $panel->get('/users')->to('#users'); 
  my $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/panel/users'});
  is_deeply $m->stack, [{app => 'panel', action => 'users'}], 'right structure';
  
  $r = Mojolicious::Routes->new;
  my $admin = $r->any('/admin')->to('admin'); # not added # at the end
  $admin->get('/articles')->to('#articles'); 
  $m = Mojolicious::Routes::Match->new(root => $r);
  $m->find($c => {method => 'GET', path => '/admin/articles'});
  is_deeply $m->stack, [{app => 'admin', action => 'articles'}], 'right structure';
};

done_testing();
