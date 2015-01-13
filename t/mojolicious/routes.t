use Mojo::Base -strict;

use Test::More;
use Mojolicious::Controller;
use Mojolicious::Routes;
use Mojolicious::Routes::Match;

# /clean
my $r = Mojolicious::Routes->new;
$r->route('/clean')->to(clean => 1)->name('very_clean');

# /clean/too
$r->route('/clean/too')->to(something => 1);

# /0
$r->route('0')->to(null => 1);

# /alternatives
# /alternatives/0
# /alternatives/test
# /alternatives/23
$r->route('/alternatives/:foo', foo => [qw(0 test 23)])->to(foo => 11);

# /alternatives2/0
# /alternatives2/test
# /alternatives2/23
$r->route('/alternatives2/:foo/', foo => [qw(0 test 23)]);

# /alternatives3/foo
# /alternatives3/foobar
$r->route('/alternatives3/:foo', foo => [qw(foo foobar)]);

# /alternatives4/foo
# /alternatives4/foo.bar
$r->route('/alternatives4/:foo', foo => [qw(foo foo.bar)]);

# /optional/*
# /optional/*/*
$r->route('/optional/:foo/:bar')->to(bar => 'test');

# /optional2
# /optional2/*
# /optional2/*/*
$r->route('/optional2/:foo')->to(foo => 'one')->route('/:bar')
  ->to(bar => 'two');

# /*/test
my $test = $r->route('/:controller/test')->to(action => 'test');

# /*/test/edit
$test->route('/edit')->to(action => 'edit')->name('test_edit');

# /*/testedit
$r->route('/:controller/testedit')->to(action => 'testedit');

# /*/test/delete/*
$test->route('/delete/(id)', id => qr/\d+/)->to(action => 'delete', id => 23);

# /test2
my $test2 = $r->route('/test2/')->inline(1)->to(controller => 'test2');

# /test2 (inline)
my $test4 = $test2->route('/')->inline(1)->to(controller => 'index');

# /test2/foo
$test4->route('/foo')->to(controller => 'baz');

# /test2/bar
$test4->route('/bar')->to(controller => 'lalala');

# /test2/baz
$test2->route('/baz')->to('just#works');

# /
$r->route('/')->to(controller => 'hello', action => 'world');

# /wildcards/1/*
$r->route('/wildcards/1/(*wildcard)', wildcard => qr/(.*)/)
  ->to(controller => 'wild', action => 'card');

# /wildcards/2/*
$r->route('/wildcards/2/(*wildcard)')
  ->to(controller => 'card', action => 'wild');

# /wildcards/3/*/foo
$r->route('/wildcards/3/(*wildcard)/foo')
  ->to(controller => 'very', action => 'dangerous');

# /wildcards/4/*/foo
$r->route('/wildcards/4/*wildcard/foo')
  ->to(controller => 'somewhat', action => 'dangerous');

# /format
# /format.html
$r->route('/format')->to(controller => 'hello')
  ->to(action => 'you', format => 'html');

# /format2.txt
$r->route('/format2', format => qr/txt/)
  ->to(controller => 'we', action => 'howdy');

# /format3.txt
# /format3.text
$r->route('/format3', format => [qw(txt text)])
  ->to(controller => 'we', action => 'cheers');

# /format4
# /format4.html
$r->route('/format4', format => ['html'])
  ->to(controller => 'us', action => 'yay', format => 'html');

# /format5
$r->route('/format5', format => 0)->to(controller => 'us', action => 'wow');

# /format6
$r->route('/format6', format => 0)
  ->to(controller => 'us', action => 'doh', format => 'xml');

# /format7.foo
# /format7.foobar
$r->route('/format7', format => [qw(foo foobar)])->to('perl#rocks');

# /articles/1/edit
# /articles/1/delete
my $inline = $r->route('/articles/:id')->inline(1)
  ->to(controller => 'articles', action => 'load', format => 'html');
$inline->route('/edit')->to(controller => 'articles', action => 'edit');
$inline->route('/delete')
  ->to(controller => 'articles', action => 'delete', format => undef)
  ->name('articles_delete');

# GET /method/get
$r->route('/method/get')->via('GET')
  ->to(controller => 'method', action => 'get');

# POST /method/post
$r->route('/method/post')->via('post')
  ->to(controller => 'method', action => 'post');

# POST|GET /method/post_get
$r->route('/method/post_get')->via(qw(POST get))
  ->to(controller => 'method', action => 'post_get');

# /simple/form
$r->route('/simple/form')->to('test-test#test');

# /regex/alternatives/*
$r->route('/regex/alternatives/:alternatives', alternatives => qr/foo|bar|baz/)
  ->to(controller => 'regex', action => 'alternatives');

# /versioned/1.0/test
# /versioned/1.0/test.xml
# /versioned/2.4/test
# /versioned/2.4/test.xml
my $versioned = $r->route('/versioned');
$versioned->route('/1.0')->to(controller => 'bar')->route('/test')
  ->to(action => 'baz');
$versioned->route('/2.4')->to(controller => 'foo')->route('/test')
  ->to(action => 'bar');

# /versioned/too/1.0
my $too = $r->route('/versioned/too')->to('too#');
$too->route('/1.0')->to('#foo');
$too->route('/2.0', format => 0)->to('#bar');

# /multi/foo.bar
my $multi = $r->route('/multi');
$multi->route('/foo.bar', format => 0)->to('just#works');
$multi->route('/bar.baz')->to('works#too', format => 'xml');

# /nodetect
# /nodetect2.txt
# /nodetect2.html
my $inactive = $r->route(format => 0);
$inactive->route('/nodetect')->to('foo#none');
$inactive->route('/nodetect2', format => ['txt', 'html'])->to('bar#hyper');

# /target/first
# /target/second
# /target/second.xml
# /source/third
# /source/third.xml
my $source = $r->route('/source')->to('source#');
my $first = $source->route(format => 0)->route('/first')->to('#first');
$source->route('/second')->to('#second');
my $third  = $source->route('/third')->to('#third');
my $target = $r->remove->route('/target')->to('target#');
my $second = $r->find('second');
is $second->render({}), '/source/second', 'right result';
$second->remove;
is $second->render({}), '/second', 'right result';
$target->add_child($first)->add_child($second);
is $second->render({}), '/target/second', 'right result';

# /websocket
$r->websocket('/websocket' => {controller => 'ws'})->route('/')
  ->to(action => 'just')->route->to(works => 1);

# /slash
$r->route('/slash')->to(controller => 'just')->route('/')
  ->to(action => 'slash');

# /missing/*/name
# /missing/too
# /missing/too/test
$r->route('/missing/:/name')->to('missing#placeholder');
$r->route('/missing/*/name')->to('missing#wildcard');
$r->route('/missing/too/*', '' => ['test'])
  ->to('missing#too', '' => 'missing');

# /partial/*
$r->route('/partial')->detour('foo#bar');

# GET  /similar/*
# POST /similar/too
my $similar = $r->route('/similar')->inline(1);
$similar->route('/:something')->via('GET')->to('similar#get');
$similar->route('/too')->via('POST')->to('similar#post');

# Cached lookup
my $fast = $r->route('/fast');
is $r->find('fast'),   $fast, 'fast route found';
is $r->lookup('fast'), $fast, 'fast route found';
my $faster = $r->route('/faster')->name('fast');
is $r->find('fast'),   $faster, 'faster route found';
is $r->lookup('fast'), $fast,   'fast route found';
is $r->find('fastest'),   undef, 'fastest route not found';
is $r->lookup('fastest'), undef, 'fastest route not found';
my $fastest = $r->route('/fastest');
is $r->find('fastest'),   $fastest, 'fastest route found';
is $r->lookup('fastest'), $fastest, 'fastest route found';

# Make sure stash stays clean
my $c = Mojolicious::Controller->new;
my $m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/clean'});
is $m->root, $r, 'right root';
is $m->endpoint->name, 'very_clean', 'right name';
is_deeply $m->stack, [{clean => 1}], 'right strucutre';
is $m->path_for->{path}, '/clean', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/clean/too'});
is_deeply $m->stack, [{something => 1}], 'right strucutre';
is $m->path_for->{path}, '/clean/too', 'right path';

# No match
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/does_not_exist'});
is $m->root, $r, 'right root';
is $m->endpoint, undef, 'no endpoint';
is_deeply $m->stack, [], 'empty stack';

# Introspect
is $r->find('very_clean')->to_string, '/clean', 'right pattern';
is $r->find('0')->to_string,          '/0',     'right pattern';
is $r->find('test_edit')->to_string, '/:controller/test/edit', 'right pattern';
is $r->find('articles_delete')->to_string, '/articles/:id/delete',
  'right pattern';
is $r->find('nodetect')->pattern->constraints->{format}, 0, 'right value';
is $r->find('nodetect')->to->{controller}, 'foo', 'right controller';

# Null route
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/0'});
is_deeply $m->stack, [{null => 1}], 'right strucutre';
is $m->path_for->{path}, '/0', 'right path';

# Alternatives with default
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives'});
is_deeply $m->stack, [{foo => 11}], 'right strucutre';
is $m->path_for->{path}, '/alternatives', 'right path';
is $m->path_for(format => 'txt')->{path}, '/alternatives/11.txt', 'right path';
is $m->path_for(foo => 12, format => 'txt')->{path}, '/alternatives/12.txt',
  'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/0'});
is_deeply $m->stack, [{foo => 0}], 'right strucutre';
is $m->path_for->{path}, '/alternatives/0', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/test'});
is_deeply $m->stack, [{foo => 'test'}], 'right strucutre';
is $m->path_for->{path}, '/alternatives/test', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/23'});
is_deeply $m->stack, [{foo => 23}], 'right strucutre';
is $m->path_for->{path}, '/alternatives/23', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/24'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/tset'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/00'});
is_deeply $m->stack, [], 'empty stack';
is $m->path_for('alternativesfoo')->{path}, '/alternatives', 'right path';
is $m->path_for('alternativesfoo', format => 'txt')->{path},
  '/alternatives/11.txt', 'right path';
is $m->path_for('alternativesfoo', foo => 12, format => 'txt')->{path},
  '/alternatives/12.txt', 'right path';

# Alternatives without default
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/2'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives2/0'});
is_deeply $m->stack, [{foo => 0}], 'right structure';
is $m->path_for->{path}, '/alternatives2/0', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives2/test'});
is_deeply $m->stack, [{foo => 'test'}], 'right structure';
is $m->path_for->{path}, '/alternatives2/test', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives2/23'});
is_deeply $m->stack, [{foo => 23}], 'right structure';
is $m->path_for->{path}, '/alternatives2/23', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives2/24'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives2/tset'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives2/00'});
is_deeply $m->stack, [], 'empty stack';
is $m->path_for('alternatives2foo')->{path}, '/alternatives2/', 'right path';
is $m->path_for('alternatives2foo', foo => 0)->{path}, '/alternatives2/0',
  'right path';

# Alternatives with similar start
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives3/foo'});
is_deeply $m->stack, [{foo => 'foo'}], 'right structure';
is $m->path_for->{path}, '/alternatives3/foo', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives3/foobar'});
is_deeply $m->stack, [{foo => 'foobar'}], 'right structure';
is $m->path_for->{path}, '/alternatives3/foobar', 'right path';

# Alternatives with special characters
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives4/foo'});
is_deeply $m->stack, [{foo => 'foo'}], 'right structure';
is $m->path_for->{path}, '/alternatives4/foo', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives4/foo.bar'});
is_deeply $m->stack, [{foo => 'foo.bar'}], 'right structure';
is $m->path_for->{path}, '/alternatives4/foo.bar', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives4/foobar'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives4/bar'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives4/bar.foo'});
is_deeply $m->stack, [], 'empty stack';

# Optional placeholder
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional/23'});
is_deeply $m->stack, [{foo => 23, bar => 'test'}], 'right structure';
is $m->path_for->{path}, '/optional/23', 'right path';
is $m->path_for(format => 'txt')->{path}, '/optional/23/test.txt',
  'right path';
is $m->path_for(foo => 12, format => 'txt')->{path}, '/optional/12/test.txt',
  'right path';
is $m->path_for('optionalfoobar', format => 'txt')->{path},
  '/optional/23/test.txt', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional/23/24'});
is_deeply $m->stack, [{foo => 23, bar => 24}], 'right structure';
is $m->path_for->{path}, '/optional/23/24', 'right path';
is $m->path_for(format => 'txt')->{path}, '/optional/23/24.txt', 'right path';
is $m->path_for('optionalfoobar')->{path}, '/optional/23/24', 'right path';
is $m->path_for('optionalfoobar', foo => 0)->{path}, '/optional/0/24',
  'right path';

# Optional placeholders in nested routes
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional2'});
is_deeply $m->stack, [{foo => 'one', bar => 'two'}], 'right structure';
is $m->path_for->{path}, '/optional2', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional2.txt'});
is_deeply $m->stack, [{foo => 'one', bar => 'two', format => 'txt'}],
  'right structure';
is $m->path_for->{path}, '/optional2', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional2/three'});
is_deeply $m->stack, [{foo => 'three', bar => 'two'}], 'right structure';
is $m->path_for->{path}, '/optional2/three', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional2/three/four'});
is_deeply $m->stack, [{foo => 'three', bar => 'four'}], 'right structure';
is $m->path_for->{path}, '/optional2/three/four', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/optional2/three/four.txt'});
is_deeply $m->stack, [{foo => 'three', bar => 'four', format => 'txt'}],
  'right structure';
is $m->path_for->{path}, '/optional2/three/four', 'right path';

# Real world example using most features at once
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/articles/1/edit'});
my @stack = (
  {controller => 'articles', action => 'load', id => 1, format => 'html'},
  {controller => 'articles', action => 'edit', id => 1, format => 'html'}
);
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/articles/1/edit', 'right path';
is $m->path_for(format => 'html')->{path}, '/articles/1/edit.html',
  'right path';
is $m->path_for('articles_delete', format => undef)->{path},
  '/articles/1/delete', 'right path';
is $m->path_for('articles_delete')->{path}, '/articles/1/delete', 'right path';
is $m->path_for('articles_delete', id => 12)->{path}, '/articles/12/delete',
  'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/articles/1/delete'});
@stack = (
  {controller => 'articles', action => 'load',   id => 1, format => 'html'},
  {controller => 'articles', action => 'delete', id => 1, format => undef}
);
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/articles/1/delete', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/articles/1/delete.json'});
@stack = (
  {controller => 'articles', action => 'load',   id => 1, format => 'json'},
  {controller => 'articles', action => 'delete', id => 1, format => 'json'}
);
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/articles/1/delete', 'right path';

# Root
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/'});
is_deeply $m->stack, [{controller => 'hello', action => 'world'}],
  'right structure';
is $m->path_for->{path}, '/', 'right path';

# Path and captures
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/foo/test/edit'});
is_deeply $m->stack, [{controller => 'foo', action => 'edit'}],
  'right structure';
is $m->path_for->{path}, '/foo/test/edit', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/foo/testedit'});
is_deeply $m->stack, [{controller => 'foo', action => 'testedit'}],
  'right structure';
is $m->path_for->{path}, '/foo/testedit', 'right path';

# Optional captures in sub route with requirement
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/bar/test/delete/22'});
is_deeply $m->stack, [{controller => 'bar', action => 'delete', id => 22}],
  'right structure';
is $m->path_for->{path}, '/bar/test/delete/22', 'right path';

# Defaults in sub route
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/bar/test/delete'});
is_deeply $m->stack, [{controller => 'bar', action => 'delete', id => 23}],
  'right structure';
is $m->path_for->{path}, '/bar/test/delete', 'right path';

# Chained routes
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/test2/foo'});
@stack
  = ({controller => 'test2'}, {controller => 'index'}, {controller => 'baz'});
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/test2/foo', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/test2/bar'});
@stack = ({controller => 'test2'}, {controller => 'index'},
  {controller => 'lalala'});
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/test2/bar', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/test2/baz'});
@stack = ({controller => 'test2'}, {controller => 'just', action => 'works'});
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/test2/baz', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/test2baz'});
is_deeply $m->stack, [], 'empty stack';

# Named path_for
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/alternatives/test'});
is $m->path_for->{path}, '/alternatives/test', 'right path';
is $m->path_for('test_edit', controller => 'foo')->{path}, '/foo/test/edit',
  'right path';
is $m->path_for('test_edit', {controller => 'foo'})->{path}, '/foo/test/edit',
  'right path';

# Wildcards
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/wildcards/1/hello/there'});
is_deeply $m->stack,
  [{controller => 'wild', action => 'card', wildcard => 'hello/there'}],
  'right structure';
is $m->path_for->{path}, '/wildcards/1/hello/there', 'right path';
is $m->path_for(wildcard => '')->{path}, '/wildcards/1/', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/wildcards/2/hello/there'});
is_deeply $m->stack,
  [{controller => 'card', action => 'wild', wildcard => 'hello/there'}],
  'right structure';
is $m->path_for->{path}, '/wildcards/2/hello/there', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/wildcards/3/hello/there/foo'});
is_deeply $m->stack,
  [{controller => 'very', action => 'dangerous', wildcard => 'hello/there'}],
  'right structure';
is $m->path_for->{path}, '/wildcards/3/hello/there/foo', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/wildcards/4/hello/there/foo'});
is_deeply $m->stack,
  [{controller => 'somewhat', action => 'dangerous', wildcard => 'hello/there'}
  ], 'right structure';
is $m->path_for->{path}, '/wildcards/4/hello/there/foo', 'right path';

# Special characters
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/wildcards/1/♥'});
is_deeply $m->stack,
  [{controller => 'wild', action => 'card', wildcard => '♥'}],
  'right structure';
is $m->path_for->{path}, '/wildcards/1/♥', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match(
  $c => {method => 'GET', path => '/wildcards/1/http://www.google.com'});
@stack = (
  {
    controller => 'wild',
    action     => 'card',
    wildcard   => 'http://www.google.com'
  }
);
is_deeply $m->stack, \@stack, 'right structure';
is $m->path_for->{path}, '/wildcards/1/http://www.google.com', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/wildcards/1/%foo%bar%'});
is_deeply $m->stack,
  [{controller => 'wild', action => 'card', wildcard => '%foo%bar%'}],
  'right structure';
is $m->path_for->{path}, '/wildcards/1/%foo%bar%', 'right path';

# Format
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format'});
is_deeply $m->stack,
  [{controller => 'hello', action => 'you', format => 'html'}],
  'right structure';
is $m->path_for->{path}, '/format', 'right path';
is $m->path_for(format => undef)->{path},  '/format',      'right path';
is $m->path_for(format => 'html')->{path}, '/format.html', 'right path';
is $m->path_for(format => 'txt')->{path},  '/format.txt',  'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format.html'});
is_deeply $m->stack,
  [{controller => 'hello', action => 'you', format => 'html'}],
  'right structure';
is $m->path_for->{path}, '/format', 'right path';
is $m->path_for(format => undef)->{path},  '/format',      'right path';
is $m->path_for(format => 'html')->{path}, '/format.html', 'right path';
is $m->path_for(format => 'txt')->{path},  '/format.txt',  'right path';

# Format with regex constraint
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format2'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format2.txt'});
is_deeply $m->stack,
  [{controller => 'we', action => 'howdy', format => 'txt'}],
  'right structure';
is $m->path_for->{path}, '/format2.txt', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format2.html'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format2.txt.txt'});
is_deeply $m->stack, [], 'empty stack';
is $m->path_for('format2', format => 'txt')->{path}, '/format2.txt',
  'right path';

# Format with constraint alternatives
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format3'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format3.txt'});
is_deeply $m->stack,
  [{controller => 'we', action => 'cheers', format => 'txt'}],
  'right structure';
is $m->path_for->{path}, '/format3.txt', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format3.text'});
is_deeply $m->stack,
  [{controller => 'we', action => 'cheers', format => 'text'}],
  'right structure';
is $m->path_for->{path}, '/format3.text', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format3.html'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format3.txt.txt'});
is_deeply $m->stack, [], 'empty stack';

# Format with constraint and default
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format4'});
is_deeply $m->stack, [{controller => 'us', action => 'yay', format => 'html'}],
  'right structure';
is $m->path_for->{path}, '/format4.html', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format4.html'});
is_deeply $m->stack, [{controller => 'us', action => 'yay', format => 'html'}],
  'right structure';
is $m->path_for->{path}, '/format4.html', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format4.txt'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format4.txt.html'});
is_deeply $m->stack, [], 'empty stack';

# Forbidden format
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format5'});
is_deeply $m->stack, [{controller => 'us', action => 'wow'}],
  'right structure';
is $m->path_for->{path}, '/format5', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format5.html'});
is_deeply $m->stack, [], 'empty stack';

# Forbidden format and default
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format6'});
is_deeply $m->stack, [{controller => 'us', action => 'doh', format => 'xml'}],
  'right structure';
is $m->path_for->{path}, '/format6', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format6.xml'});
is_deeply $m->stack, [], 'empty stack';

# Formats with similar start
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format7.foo'});
is_deeply $m->stack,
  [{controller => 'perl', action => 'rocks', format => 'foo'}],
  'right structure';
is $m->path_for->{path}, '/format7.foo', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format7.foobar'});
is_deeply $m->stack,
  [{controller => 'perl', action => 'rocks', format => 'foobar'}],
  'right structure';
is $m->path_for->{path}, '/format7.foobar', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/format7.foobarbaz'});
is_deeply $m->stack, [], 'empty stack';

# Request methods
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/method/get.html'});
is_deeply $m->stack,
  [{controller => 'method', action => 'get', format => 'html'}],
  'right structure';
is $m->path_for->{path}, '/method/get', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'POST', path => '/method/post'});
is_deeply $m->stack, [{controller => 'method', action => 'post'}],
  'right structure';
is $m->path_for->{path}, '/method/post', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/method/post_get'});
is_deeply $m->stack, [{controller => 'method', action => 'post_get'}],
  'right structure';
is $m->path_for->{path}, '/method/post_get', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'POST', path => '/method/post_get'});
is_deeply $m->stack, [{controller => 'method', action => 'post_get'}],
  'right structure';
is $m->path_for->{path}, '/method/post_get', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'DELETE', path => '/method/post_get'});
is_deeply $m->stack, [], 'empty stack';
is $m->path_for->{path}, undef, 'no path';

# Not found
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/not_found'});
is $m->path_for('test_edit', controller => 'foo')->{path}, '/foo/test/edit',
  'right path';
is_deeply $m->stack, [], 'empty stack';

# Simplified form
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/simple/form'});
is_deeply $m->stack, [{controller => 'test-test', action => 'test'}],
  'right structure';
is $m->path_for->{path}, '/simple/form', 'right path';
is $m->path_for('current')->{path}, '/simple/form', 'right path';

# Special edge case with intermediate destinations (regex)
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/regex/alternatives/foo'});
is_deeply $m->stack,
  [{controller => 'regex', action => 'alternatives', alternatives => 'foo'}],
  'right structure';
is $m->path_for->{path}, '/regex/alternatives/foo', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/regex/alternatives/bar'});
is_deeply $m->stack,
  [{controller => 'regex', action => 'alternatives', alternatives => 'bar'}],
  'right structure';
is $m->path_for->{path}, '/regex/alternatives/bar', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/regex/alternatives/baz'});
is_deeply $m->stack,
  [{controller => 'regex', action => 'alternatives', alternatives => 'baz'}],
  'right structure';
is $m->path_for->{path}, '/regex/alternatives/baz', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/regex/alternatives/yada'});
is_deeply $m->stack, [], 'empty stack';

# Route with version
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/1.0/test'});
is_deeply $m->stack, [{controller => 'bar', action => 'baz'}],
  'right structure';
is $m->path_for->{path}, '/versioned/1.0/test', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/1.0/test.xml'});
is_deeply $m->stack, [{controller => 'bar', action => 'baz', format => 'xml'}],
  'right structure';
is $m->path_for->{path}, '/versioned/1.0/test', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/2.4/test'});
is_deeply $m->stack, [{controller => 'foo', action => 'bar'}],
  'right structure';
is $m->path_for->{path}, '/versioned/2.4/test', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/2.4/test.xml'});
is_deeply $m->stack, [{controller => 'foo', action => 'bar', format => 'xml'}],
  'right structure';
is $m->path_for->{path}, '/versioned/2.4/test', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/3.0/test'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/3.4/test'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/0.3/test'});
is_deeply $m->stack, [], 'empty stack';

# Route with version at the end
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/too/1.0'});
is_deeply $m->stack, [{controller => 'too', action => 'foo'}],
  'right structure';
is $m->path_for->{path}, '/versioned/too/1.0', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/versioned/too/2.0'});
is_deeply $m->stack, [{controller => 'too', action => 'bar'}],
  'right structure';
is $m->path_for->{path}, '/versioned/too/2.0', 'right path';

# Multiple extensions
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/multi/foo.bar'});
is_deeply $m->stack, [{controller => 'just', action => 'works'}],
  'right structure';
is $m->path_for->{path}, '/multi/foo.bar', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/multi/foo.bar.baz'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/multi/bar.baz'});
is_deeply $m->stack,
  [{controller => 'works', action => 'too', format => 'xml'}],
  'right structure';
is $m->path_for->{path}, '/multi/bar.baz', 'right path';

# Disabled format detection inheritance
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/nodetect'});
is_deeply $m->stack, [{controller => 'foo', action => 'none'}],
  'right structure';
is $m->path_for->{path}, '/nodetect', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/nodetect.txt'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/nodetect2.txt'});
is_deeply $m->stack,
  [{controller => 'bar', action => 'hyper', format => 'txt'}],
  'right structure';
is $m->path_for->{path}, '/nodetect2.txt', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/nodetect2.html'});
is_deeply $m->stack,
  [{controller => 'bar', action => 'hyper', format => 'html'}],
  'right structure';
is $m->path_for->{path}, '/nodetect2.html', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/nodetect2'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/nodetect2.xml'});
is_deeply $m->stack, [], 'empty stack';

# Removed routes
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/target/first'});
is_deeply $m->stack, [{controller => 'target', action => 'first'}],
  'right structure';
is $m->path_for->{path}, '/target/first', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/target/first.xml'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/source/first'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/target/second'});
is_deeply $m->stack, [{controller => 'target', action => 'second'}],
  'right structure';
is $m->path_for->{path}, '/target/second', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/target/second.xml'});
is_deeply $m->stack,
  [{controller => 'target', action => 'second', format => 'xml'}],
  'right structure';
is $m->path_for->{path}, '/target/second', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/source/second'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/source/third'});
is_deeply $m->stack, [{controller => 'source', action => 'third'}],
  'right structure';
is $m->path_for->{path}, '/source/third', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/source/third.xml'});
is_deeply $m->stack,
  [{controller => 'source', action => 'third', format => 'xml'}],
  'right structure';
is $m->path_for->{path}, '/source/third', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/target/third'});
is_deeply $m->stack, [], 'empty stack';

# WebSocket
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/websocket'});
is_deeply $m->stack, [], 'empty stack';
$m->match($c => {method => 'GET', path => '/websocket', websocket => 1});
is_deeply $m->stack, [{controller => 'ws', action => 'just', works => 1}],
  'right structure';
is $m->path_for->{path}, '/websocket', 'right path';
ok $m->path_for->{websocket}, 'is a websocket';

# Just a slash with a format after a path
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/slash.txt'});
is_deeply $m->stack,
  [{controller => 'just', action => 'slash', format => 'txt'}],
  'right structure';
is $m->path_for->{path}, '/slash', 'right path';
ok !$m->path_for->{websocket}, 'not a websocket';
is $m->path_for(format => 'html')->{path}, '/slash.html', 'right path';

# Nameless placeholder
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/missing/foo/name'});
is_deeply $m->stack,
  [{controller => 'missing', action => 'placeholder', '' => 'foo'}],
  'right structure';
is $m->path_for->{path}, '/missing/foo/name', 'right path';
is $m->path_for('' => 'bar')->{path}, '/missing/bar/name', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/missing/foo/bar/name'});
is_deeply $m->stack,
  [{controller => 'missing', action => 'wildcard', '' => 'foo/bar'}],
  'right structure';
is $m->path_for->{path}, '/missing/foo/bar/name', 'right path';
is $m->path_for('' => 'bar/baz')->{path}, '/missing/bar/baz/name',
  'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/missing/too/test'});
is_deeply $m->stack,
  [{controller => 'missing', action => 'too', '' => 'test'}],
  'right structure';
is $m->path_for->{path}, '/missing/too/test', 'right path';
is $m->path_for('' => 'bar/baz')->{path}, '/missing/too/bar/baz', 'right path';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/missing/too/tset'});
is_deeply $m->stack, [], 'empty stack';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/missing/too'});
is_deeply $m->stack,
  [{controller => 'missing', action => 'too', '' => 'missing'}],
  'right structure';
is $m->path_for->{path}, '/missing/too', 'right path';

# Partial route
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/partial/test'});
is_deeply $m->stack,
  [{controller => 'foo', action => 'bar', 'path' => '/test'}],
  'right structure';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/partial.test'});
is_deeply $m->stack,
  [{controller => 'foo', action => 'bar', 'path' => '.test'}],
  'right structure';

# Similar routes with placeholders
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'GET', path => '/similar/too'});
is_deeply $m->stack,
  [{}, {controller => 'similar', action => 'get', 'something' => 'too'}],
  'right structure';
$m = Mojolicious::Routes::Match->new(root => $r);
$m->match($c => {method => 'POST', path => '/similar/too'});
is_deeply $m->stack, [{}, {controller => 'similar', action => 'post'}],
  'right structure';

done_testing();
