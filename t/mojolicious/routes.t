use Mojo::Base -strict;

use Test::More tests => 435;

# "They're not very heavy, but you don't hear me not complaining."
use Mojolicious::Routes;
use Mojolicious::Routes::Match;

# /clean
my $r = Mojolicious::Routes->new;
$r->route('/clean')->to(clean => 1)->name('very_clean');

# /clean/too
$r->route('/clean/too')->to(something => 1);

# /0
$r->route('/0')->to(null => 1);

# /alternatives
# /alternatives/0
# /alternatives/test
# /alternatives/23
$r->route('/alternatives/:foo', foo => [qw/0 test 23/])->to(foo => 11);

# /alternatives2/0
# /alternatives2/test
# /alternatives2/23
$r->route('/alternatives2/:foo', foo => [qw/0 test 23/]);

# /alternatives3/foo
# /alternatives3/foobar
$r->route('/alternatives3/:foo', foo => [qw/foo foobar/]);

# /alternatives4/foo
# /alternatives4/foo.bar
$r->route('/alternatives4/:foo', foo => [qw/foo foo.bar/]);

# /*/test
my $test = $r->route('/:controller/test')->to(action => 'test');

# /*/test/edit
$test->route('/edit')->to(action => 'edit')->name('test_edit');

# /*/testedit
$r->route('/:controller/testedit')->to(action => 'testedit');

# /*/test/delete/*
$test->route('/delete/(id)', id => qr/\d+/)->to(action => 'delete', id => 23);

# /test2
my $test2 = $r->bridge('/test2')->to(controller => 'test2');

# /test2 (inline)
my $test4 = $test2->bridge('/')->to(controller => 'index');

# /test2/foo
$test4->route('/foo')->to(controller => 'baz');

# /test2/bar
$test4->route('/bar')->to(controller => 'lalala');

# /test2/baz
$test2->route('/baz')->to('just#works');

# /test3
my $test3 = $r->waypoint('/test3')->to(controller => 's', action => 'l');

# /test3/edit
$test3->route('/edit')->to(action => 'edit');

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

# /format2.html
$r->route('/format2.html')->to(controller => 'you', action => 'hello');

# /format2.json
$r->route('/format2.json')->to(controller => 'you', action => 'hello_json');

# /format3/*.html
$r->route('/format3/:foo.html')->to(controller => 'me', action => 'bye');

# /format3/*.json
$r->route('/format3/:foo.json')->to(controller => 'me', action => 'bye_json');

# /format4.txt
$r->route('/format4', format => qr/txt/)
  ->to(controller => 'we', action => 'howdy');

# /format5.txt
# /format5.text
$r->route('/format5', format => [qw/txt text/])
  ->to(controller => 'we', action => 'cheers');

# /format6
# /format6.html
$r->route('/format6', format => ['html'])
  ->to(controller => 'us', action => 'yay', format => 'html');

# /format7
$r->route('/format7', format => 0)->to(controller => 'us', action => 'wow');

# /format8
$r->route('/format8', format => 0)
  ->to(controller => 'us', action => 'doh', format => 'xml');

# /format9.foo
# /fomrat9.foobar
$r->route('/format9', format => [qw/foo foobar/])->to('perl#rocks');

# /articles
# /articles.html
# /articles/1
# /articles/1.html
# /articles/1/edit
# /articles/1/delete
my $articles = $r->waypoint('/articles')->to(
  controller => 'articles',
  action     => 'index',
  format     => 'html'
);
my $wp = $articles->waypoint('/:id')->to(
  controller => 'articles',
  action     => 'load',
  format     => 'html'
);
my $bridge = $wp->bridge->to(
  controller => 'articles',
  action     => 'load',
  format     => 'html'
);
$bridge->route('/edit')->to(controller => 'articles', action => 'edit');
$bridge->route('/delete')->to(
  controller => 'articles',
  action     => 'delete',
  format     => undef
)->name('articles_delete');

# GET /method/get
$r->route('/method/get')->via('GET')
  ->to(controller => 'method', action => 'get');

# POST /method/post
$r->route('/method/post')->via('post')
  ->to(controller => 'method', action => 'post');

# POST|GET /method/post_get
$r->route('/method/post_get')->via(qw/POST get/)
  ->to(controller => 'method', action => 'post_get');

# /simple/form
$r->route('/simple/form')->to('test-test#test');

# /edge/gift
my $edge = $r->route('/edge');
my $auth = $edge->bridge('/auth')->to('auth#check');
$auth->route('/about/')->to('pref#about');
$auth->bridge->to('album#allow')->route('/album/create/')->to('album#create');
$auth->route('/gift/')->to('gift#index')->name('gift');

# /regex/alternatives/*
$r->route('/regex/alternatives/:alternatives',
  alternatives => qr/foo|bar|baz/)
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
$multi->route('/foo.bar')->to('just#works');
$multi->route('/bar.baz')->to('works#too', format => 'xml');

# /nodetect
# /nodetect2.txt
# /nodetect2.html
# /nodetect3.xml
# /nodetect3/rly
# /nodetect4
# /nodetect4.txt
# /nodetect4/ya
# /nodetect4.txt/ya
my $inactive = $r->route(format => 0);
$inactive->route('/nodetect')->to('foo#none');
$inactive->route('/nodetect2', format => ['txt', 'html'])->to('bar#hyper');
my $some = $inactive->waypoint('/nodetect3', format => 'xml')->to('baz#some');
$some->route('/rly')->to('#rly');
my $more =
  $inactive->waypoint('/nodetect4', format => 'txt')
  ->to('baz#more', format => 'json');
$more->route('/ya')->to('#ya');

# Make sure stash stays clean
my $m = Mojolicious::Routes::Match->new(GET => '/clean')->match($r);
is $m->stack->[0]{clean},     1,     'right value';
is $m->stack->[0]{something}, undef, 'no value';
is $m->path_for, '/clean', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/clean/too')->match($r);
is $m->stack->[0]{clean},     undef, 'no value';
is $m->stack->[0]{something}, 1,     'right value';
is $m->path_for, '/clean/too', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Introspect
is $r->find('very_clean')->to_string, '/clean', 'right pattern';
is $r->find('0')->to_string,          '/0',     'right pattern';
is $r->find('test_edit')->to_string, '/:controller/test/edit',
  'right pattern';
is $r->find('articles_delete')->to_string, '/articles/:id/delete',
  'right pattern';
is $r->find('rly')->pattern->reqs->{format}, 0, 'right value';

# Null route
$m = Mojolicious::Routes::Match->new(GET => '/0')->match($r);
is $m->stack->[0]{null}, 1, 'right value';
is $m->path_for, '/0', 'right path';

# Alternatives with default
$m = Mojolicious::Routes::Match->new(GET => '/alternatives')->match($r);
is $m->stack->[0]{foo}, 11, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/0')->match($r);
is $m->stack->[0]{foo}, 0, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives/0', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/test')->match($r);
is $m->stack->[0]{foo}, 'test', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/23')->match($r);
is $m->stack->[0]{foo}, 23, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives/23', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/24')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/tset')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/00')->match($r);
is @{$m->stack}, 0, 'right number of elements';
is $m->path_for('alternativesfoo'), '/alternatives', 'right path';

# Alternatives without default
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/0')->match($r);
is $m->stack->[0]{foo}, 0, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives2/0', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/test')->match($r);
is $m->stack->[0]{foo}, 'test', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives2/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/23')->match($r);
is $m->stack->[0]{foo}, 23, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives2/23', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/24')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/tset')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/00')->match($r);
is @{$m->stack}, 0, 'right number of elements';
is $m->path_for('alternatives2foo'), '/alternatives2/', 'right path';
is $m->path_for('alternatives2foo', foo => 0), '/alternatives2/0',
  'right path';

# Alternatives with similar start
$m = Mojolicious::Routes::Match->new(GET => '/alternatives3/foo')->match($r);
is $m->stack->[0]{foo}, 'foo', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives3/foo', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/alternatives3/foobar')->match($r);
is $m->stack->[0]{foo}, 'foobar', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives3/foobar', 'right path';

# Alternatives with special characters
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/foo')->match($r);
is $m->stack->[0]{foo}, 'foo', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives4/foo', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/alternatives4/foo.bar')->match($r);
is $m->stack->[0]{foo}, 'foo.bar', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives4/foo.bar', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/alternatives4/fooobar')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/bar')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m =
  Mojolicious::Routes::Match->new(GET => '/alternatives4/bar.foo')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Real world example using most features at once
$m = Mojolicious::Routes::Match->new(GET => '/articles.html')->match($r);
is $m->stack->[0]{controller}, 'articles', 'right value';
is $m->stack->[0]{action},     'index',    'right value';
is $m->stack->[0]{format},     'html',     'right value';
is $m->path_for, '/articles', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/articles/1.html')->match($r);
is $m->stack->[0]{controller}, 'articles', 'right value';
is $m->stack->[0]{action},     'load',     'right value';
is $m->stack->[0]{id},         '1',        'right value';
is $m->stack->[0]{format},     'html',     'right value';
is $m->path_for(format => 'html'), '/articles/1.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/articles/1/edit')->match($r);
is $m->stack->[1]{controller}, 'articles', 'right value';
is $m->stack->[1]{action},     'edit',     'right value';
is $m->stack->[1]{format},     'html',     'right value';
is $m->path_for, '/articles/1/edit', 'right path';
is $m->path_for(format => 'html'), '/articles/1/edit.html', 'right path';
is $m->path_for('articles_delete', format => undef), '/articles/1/delete',
  'right path';
is $m->path_for('articles_delete'), '/articles/1/delete', 'right path';
is $m->path_for('articles_delete', id => 12), '/articles/12/delete',
  'right path';
is @{$m->stack}, 2, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/articles/1/delete')->match($r);
is $m->stack->[1]{controller}, 'articles', 'right value';
is $m->stack->[1]{action},     'delete',   'right value';
is $m->stack->[1]{format},     undef,      'no value';
is $m->path_for, '/articles/1/delete', 'right path';
is @{$m->stack}, 2, 'right number of elements';

# Root
$m = Mojolicious::Routes::Match->new(GET => '/')->match($r);
is $m->captures->{controller}, 'hello', 'right value';
is $m->captures->{action},     'world', 'right value';
is $m->stack->[0]{controller}, 'hello', 'right value';
is $m->stack->[0]{action},     'world', 'right value';
is $m->path_for, '/', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Path and captures
$m = Mojolicious::Routes::Match->new(GET => '/foo/test/edit')->match($r);
is $m->captures->{controller}, 'foo',  'right value';
is $m->captures->{action},     'edit', 'right value';
is $m->stack->[0]{controller}, 'foo',  'right value';
is $m->stack->[0]{action},     'edit', 'right value';
is $m->path_for, '/foo/test/edit', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/foo/testedit')->match($r);
is $m->captures->{controller}, 'foo',      'right value';
is $m->captures->{action},     'testedit', 'right value';
is $m->stack->[0]{controller}, 'foo',      'right value';
is $m->stack->[0]{action},     'testedit', 'right value';
is $m->path_for, '/foo/testedit', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Optional captures in sub route with requirement
$m = Mojolicious::Routes::Match->new(GET => '/bar/test/delete/22')->match($r);
is $m->captures->{controller}, 'bar',    'right value';
is $m->captures->{action},     'delete', 'right value';
is $m->captures->{id},         22,       'right value';
is $m->stack->[0]{controller}, 'bar',    'right value';
is $m->stack->[0]{action},     'delete', 'right value';
is $m->stack->[0]{id},         22,       'right value';
is $m->path_for, '/bar/test/delete/22', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Defaults in sub route
$m = Mojolicious::Routes::Match->new(GET => '/bar/test/delete')->match($r);
is $m->captures->{controller}, 'bar',    'right value';
is $m->captures->{action},     'delete', 'right value';
is $m->captures->{id},         23,       'right value';
is $m->stack->[0]{controller}, 'bar',    'right value';
is $m->stack->[0]{action},     'delete', 'right value';
is $m->stack->[0]{id},         23,       'right value';
is $m->path_for, '/bar/test/delete', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Chained routes
$m = Mojolicious::Routes::Match->new(GET => '/test2/foo')->match($r);
is $m->stack->[0]{controller}, 'test2', 'right value';
is $m->stack->[1]{controller}, 'index', 'right value';
is $m->stack->[2]{controller}, 'baz',   'right value';
is $m->captures->{controller}, 'baz', 'right value';
is $m->path_for, '/test2/foo', 'right path';
is @{$m->stack}, 3, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/test2/bar')->match($r);
is $m->stack->[0]{controller}, 'test2',  'right value';
is $m->stack->[1]{controller}, 'index',  'right value';
is $m->stack->[2]{controller}, 'lalala', 'right value';
is $m->captures->{controller}, 'lalala', 'right value';
is $m->path_for, '/test2/bar', 'right path';
is @{$m->stack}, 3, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/test2/baz')->match($r);
is $m->stack->[0]{controller}, 'test2', 'right value';
is $m->stack->[1]{controller}, 'just',  'right value';
is $m->stack->[1]{action},     'works', 'right value';
is $m->stack->[2], undef, 'no value';
is $m->captures->{controller}, 'just', 'right value';
is $m->path_for, '/test2/baz', 'right path';
is @{$m->stack}, 2, 'right number of elements';

# Waypoints
$m = Mojolicious::Routes::Match->new(GET => '/test3')->match($r);
is $m->stack->[0]{controller}, 's', 'right value';
is $m->stack->[0]{action},     'l', 'right value';
is $m->path_for, '/test3', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/test3/')->match($r);
is $m->stack->[0]{controller}, 's', 'right value';
is $m->stack->[0]{action},     'l', 'right value';
is $m->path_for, '/test3', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/test3/edit')->match($r);
is $m->stack->[0]{controller}, 's',    'right value';
is $m->stack->[0]{action},     'edit', 'right value';
is $m->path_for, '/test3/edit', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Named path_for
$m = Mojolicious::Routes::Match->new(GET => '/test3')->match($r);
is $m->path_for, '/test3', 'right path';
is $m->path_for('test_edit', controller => 'foo'), '/foo/test/edit',
  'right path';
is $m->path_for('test_edit', {controller => 'foo'}), '/foo/test/edit',
  'right path';
is @{$m->stack}, 1, 'right number of elements';

# Wildcards
$m =
  Mojolicious::Routes::Match->new(GET => '/wildcards/1/hello/there')
  ->match($r);
is $m->stack->[0]{controller}, 'wild',        'right value';
is $m->stack->[0]{action},     'card',        'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/1/hello/there', 'right path';
is $m->path_for(wildcard => ''), '/wildcards/1/', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m =
  Mojolicious::Routes::Match->new(GET => '/wildcards/2/hello/there')
  ->match($r);
is $m->stack->[0]{controller}, 'card',        'right value';
is $m->stack->[0]{action},     'wild',        'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/2/hello/there', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m =
  Mojolicious::Routes::Match->new(GET => '/wildcards/3/hello/there/foo')
  ->match($r);
is $m->stack->[0]{controller}, 'very',        'right value';
is $m->stack->[0]{action},     'dangerous',   'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/3/hello/there/foo', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m =
  Mojolicious::Routes::Match->new(GET => '/wildcards/4/hello/there/foo')
  ->match($r);
is $m->stack->[0]{controller}, 'somewhat',    'right value';
is $m->stack->[0]{action},     'dangerous',   'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/4/hello/there/foo', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Escaped
$m =
  Mojolicious::Routes::Match->new(GET => '/wildcards/1/http://www.google.com')
  ->match($r);
is $m->stack->[0]{controller}, 'wild',                  'right value';
is $m->stack->[0]{action},     'card',                  'right value';
is $m->stack->[0]{wildcard},   'http://www.google.com', 'right value';
is $m->path_for, '/wildcards/1/http://www.google.com', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m =
  Mojolicious::Routes::Match->new(
  GET => '/wildcards/1/http%3A%2F%2Fwww.google.com')->match($r);
is $m->stack->[0]{controller}, 'wild',                  'right value';
is $m->stack->[0]{action},     'card',                  'right value';
is $m->stack->[0]{wildcard},   'http://www.google.com', 'right value';
is $m->path_for, '/wildcards/1/http://www.google.com', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Format
$m = Mojolicious::Routes::Match->new(GET => '/format')->match($r);
is $m->stack->[0]{controller}, 'hello', 'right value';
is $m->stack->[0]{action},     'you',   'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->path_for, '/format', 'right path';
is $m->path_for(format => undef),  '/format',      'right path';
is $m->path_for(format => 'html'), '/format.html', 'right path';
is $m->path_for(format => 'txt'),  '/format.txt',  'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format.html')->match($r);
is $m->stack->[0]{controller}, 'hello', 'right value';
is $m->stack->[0]{action},     'you',   'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->path_for, '/format', 'right path';
is $m->path_for(format => undef),  '/format',      'right path';
is $m->path_for(format => 'html'), '/format.html', 'right path';
is $m->path_for(format => 'txt'),  '/format.txt',  'right path';
is @{$m->stack}, 1, 'right number of elements';

# Hardcoded format
$m = Mojolicious::Routes::Match->new(GET => '/format2.html')->match($r);
is $m->stack->[0]{controller}, 'you',   'right value';
is $m->stack->[0]{action},     'hello', 'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->path_for, '/format2.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format2.json')->match($r);
is $m->stack->[0]{controller}, 'you',        'right value';
is $m->stack->[0]{action},     'hello_json', 'right value';
is $m->stack->[0]{format},     'json',       'right value';
is $m->path_for, '/format2.json', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Hardcoded format after placeholder
$m = Mojolicious::Routes::Match->new(GET => '/format3/baz.html')->match($r);
is $m->stack->[0]{controller}, 'me',   'right value';
is $m->stack->[0]{action},     'bye',  'right value';
is $m->stack->[0]{format},     'html', 'right value';
is $m->stack->[0]{foo},        'baz',  'right value';
is $m->path_for, '/format3/baz.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format3/baz.json')->match($r);
is $m->stack->[0]{controller}, 'me',       'right value';
is $m->stack->[0]{action},     'bye_json', 'right value';
is $m->stack->[0]{format},     'json',     'right value';
is $m->stack->[0]{foo},        'baz',      'right value';
is $m->path_for, '/format3/baz.json', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Format with regex constraint
$m = Mojolicious::Routes::Match->new(GET => '/format4')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format4.txt')->match($r);
is $m->stack->[0]{controller}, 'we',    'right value';
is $m->stack->[0]{action},     'howdy', 'right value';
is $m->stack->[0]{format},     'txt',   'right value';
is $m->path_for, '/format4.txt', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format4.html')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format4.txt.txt')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Format with constraint alternatives
$m = Mojolicious::Routes::Match->new(GET => '/format5')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format5.txt')->match($r);
is $m->stack->[0]{controller}, 'we',     'right value';
is $m->stack->[0]{action},     'cheers', 'right value';
is $m->stack->[0]{format},     'txt',    'right value';
is $m->path_for, '/format5.txt', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format5.text')->match($r);
is $m->stack->[0]{controller}, 'we',     'right value';
is $m->stack->[0]{action},     'cheers', 'right value';
is $m->stack->[0]{format},     'text',   'right value';
is $m->path_for, '/format5.text', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format5.html')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format5.txt.txt')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Format with constraint and default
$m = Mojolicious::Routes::Match->new(GET => '/format6')->match($r);
is $m->stack->[0]{controller}, 'us',   'right value';
is $m->stack->[0]{action},     'yay',  'right value';
is $m->stack->[0]{format},     'html', 'right value';
is $m->path_for, '/format6.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format6.html')->match($r);
is $m->stack->[0]{controller}, 'us',   'right value';
is $m->stack->[0]{action},     'yay',  'right value';
is $m->stack->[0]{format},     'html', 'right value';
is $m->path_for, '/format6.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format6.txt')->match($r);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format6.txt.html')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Forbidden format
$m = Mojolicious::Routes::Match->new(GET => '/format7')->match($r);
is $m->stack->[0]{controller}, 'us',  'right value';
is $m->stack->[0]{action},     'wow', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->path_for, '/format7', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format7.html')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Forbidden format and default
$m = Mojolicious::Routes::Match->new(GET => '/format8')->match($r);
is $m->stack->[0]{controller}, 'us',  'right value';
is $m->stack->[0]{action},     'doh', 'right value';
is $m->stack->[0]{format},     'xml', 'right value';
is $m->path_for, '/format8', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format8.xml')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Formats with similar start
$m = Mojolicious::Routes::Match->new(GET => '/format9.foo')->match($r);
is $m->stack->[0]{controller}, 'perl',  'right value';
is $m->stack->[0]{action},     'rocks', 'right value';
is $m->stack->[0]{format},     'foo',   'right value';
is $m->path_for, '/format9.foo', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format9.foobar')->match($r);
is $m->stack->[0]{controller}, 'perl',   'right value';
is $m->stack->[0]{action},     'rocks',  'right value';
is $m->stack->[0]{format},     'foobar', 'right value';
is $m->path_for, '/format9.foobar', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format9.foobarbaz')->match($r);
is @{$m->stack}, 0, 'right number of elements';

# Request methods
$m = Mojolicious::Routes::Match->new(GET => '/method/get.html')->match($r);
is $m->stack->[0]{controller}, 'method', 'right value';
is $m->stack->[0]{action},     'get',    'right value';
is $m->stack->[0]{format},     'html',   'right value';
is $m->path_for, '/method/get', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(POST => '/method/post')->match($r);
is $m->stack->[0]{controller}, 'method', 'right value';
is $m->stack->[0]{action},     'post',   'right value';
is $m->stack->[0]{format},     undef,    'no value';
is $m->path_for, '/method/post', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/method/post_get')->match($r);
is $m->stack->[0]{controller}, 'method',   'right value';
is $m->stack->[0]{action},     'post_get', 'right value';
is $m->stack->[0]{format},     undef,      'no value';
is $m->path_for, '/method/post_get', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(post => '/method/post_get')->match($r);
is $m->stack->[0]{controller}, 'method',   'right value';
is $m->stack->[0]{action},     'post_get', 'right value';
is $m->stack->[0]{format},     undef,      'no value';
is $m->path_for, '/method/post_get', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(delete => '/method/post_get')->match($r);
is $m->stack->[0]{controller}, undef, 'no value';
is $m->stack->[0]{action},     undef, 'no value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->path_for, undef, 'no path';
is @{$m->stack}, 1, 'right number of elements';

# Not found
$m = Mojolicious::Routes::Match->new(GET => '/not_found')->match($r);
is $m->path_for('test_edit', controller => 'foo'), '/foo/test/edit',
  'right path';
is @{$m->stack}, 0, 'no elements';

# Simplified form
$m = Mojolicious::Routes::Match->new(GET => '/simple/form')->match($r);
is $m->stack->[0]{controller}, 'test-test', 'right value';
is $m->stack->[0]{action},     'test',      'right value';
is $m->stack->[0]{format},     undef,       'no value';
is $m->path_for, '/simple/form', 'right path';
is $m->path_for('current'), '/simple/form', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Special edge case with nested bridges
$m = Mojolicious::Routes::Match->new(GET => '/edge/auth/gift')->match($r);
is $m->stack->[0]{controller}, 'auth',  'right value';
is $m->stack->[0]{action},     'check', 'right value';
is $m->stack->[0]{format},     undef,   'no value';
is $m->stack->[1]{controller}, 'gift',  'right value';
is $m->stack->[1]{action},     'index', 'right value';
is $m->stack->[1]{format},     undef,   'no value';
is $m->stack->[2], undef, 'no value';
is $m->path_for, '/edge/auth/gift', 'right path';
is $m->path_for('gift'),    '/edge/auth/gift', 'right path';
is $m->path_for('current'), '/edge/auth/gift', 'right path';
is @{$m->stack}, 2, 'right number of elements';

# Special edge case with nested bridges (regex)
$m =
  Mojolicious::Routes::Match->new(GET => '/regex/alternatives/foo')
  ->match($r);
is $m->stack->[0]{controller},   'regex',        'right value';
is $m->stack->[0]{action},       'alternatives', 'right value';
is $m->stack->[0]{alternatives}, 'foo',          'right value';
is $m->stack->[0]{format},       undef,          'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/regex/alternatives/foo', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/regex/alternatives/bar')
  ->match($r);
is $m->stack->[0]{controller},   'regex',        'right value';
is $m->stack->[0]{action},       'alternatives', 'right value';
is $m->stack->[0]{alternatives}, 'bar',          'right value';
is $m->stack->[0]{format},       undef,          'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/regex/alternatives/bar', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/regex/alternatives/baz')
  ->match($r);
is $m->stack->[0]{controller},   'regex',        'right value';
is $m->stack->[0]{action},       'alternatives', 'right value';
is $m->stack->[0]{alternatives}, 'baz',          'right value';
is $m->stack->[0]{format},       undef,          'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/regex/alternatives/baz', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/regex/alternatives/yada')
  ->match($r);
is $m->stack->[0], undef, 'no value';

# Route with version
$m = Mojolicious::Routes::Match->new(GET => '/versioned/1.0/test')->match($r);
is $m->stack->[0]{controller}, 'bar', 'right value';
is $m->stack->[0]{action},     'baz', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/1.0/test', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/versioned/1.0/test.xml')
  ->match($r);
is $m->stack->[0]{controller}, 'bar', 'right value';
is $m->stack->[0]{action},     'baz', 'right value';
is $m->stack->[0]{format},     'xml', 'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/1.0/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/2.4/test')->match($r);
is $m->stack->[0]{controller}, 'foo', 'right value';
is $m->stack->[0]{action},     'bar', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/2.4/test', 'right path';
$m =
  Mojolicious::Routes::Match->new(GET => '/versioned/2.4/test.xml')
  ->match($r);
is $m->stack->[0]{controller}, 'foo', 'right value';
is $m->stack->[0]{action},     'bar', 'right value';
is $m->stack->[0]{format},     'xml', 'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/2.4/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/3.0/test')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/3.4/test')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/0.3/test')->match($r);
is $m->stack->[0], undef, 'no value';

# Route with version at the end
$m = Mojolicious::Routes::Match->new(GET => '/versioned/too/1.0')->match($r);
is $m->stack->[0]{controller}, 'too', 'right value';
is $m->stack->[0]{action},     'foo', 'right value';
is $m->stack->[0]{format},     '0',   'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/too/1.0', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/too/2.0')->match($r);
is $m->stack->[0]{controller}, 'too', 'right value';
is $m->stack->[0]{action},     'bar', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/too/2.0', 'right path';

# Multiple extensions
$m = Mojolicious::Routes::Match->new(GET => '/multi/foo.bar')->match($r);
is $m->stack->[0]{controller}, 'just',  'right value';
is $m->stack->[0]{action},     'works', 'right value';
is $m->stack->[0]{format},     'bar',   'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/multi/foo.bar', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/multi/foo.bar.baz')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/multi/bar.baz')->match($r);
is $m->stack->[0]{controller}, 'works', 'right value';
is $m->stack->[0]{action},     'too',   'right value';
is $m->stack->[0]{format},     'xml',   'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/multi/bar.baz', 'right path';

# Disabled format detection inheritance
$m = Mojolicious::Routes::Match->new(GET => '/nodetect')->match($r);
is $m->stack->[0]{controller}, 'foo',  'right value';
is $m->stack->[0]{action},     'none', 'right value';
is $m->stack->[0]{format},     undef,  'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/nodetect', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect.txt')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2.txt')->match($r);
is $m->stack->[0]{controller}, 'bar',   'right value';
is $m->stack->[0]{action},     'hyper', 'right value';
is $m->stack->[0]{format},     'txt',   'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/nodetect2.txt', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2.html')->match($r);
is $m->stack->[0]{controller}, 'bar',   'right value';
is $m->stack->[0]{action},     'hyper', 'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/nodetect2.html', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2.xml')->match($r);
is $m->stack->[0], undef, 'no value';

# Disabled format detection inheritance with waypoint
$m = Mojolicious::Routes::Match->new(GET => '/nodetect3.xml')->match($r);
is $m->stack->[0]{controller}, 'baz',  'right value';
is $m->stack->[0]{action},     'some', 'right value';
is $m->stack->[0]{format},     'xml',  'right value';
is $m->stack->[1], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect3')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect3.txt')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect3.xml/rly')->match($r);
is $m->stack->[0]{controller}, 'baz', 'right value';
is $m->stack->[0]{action},     'rly', 'right value';
is $m->stack->[0]{format},     'xml', 'no value';
is $m->stack->[1], undef, 'no value';
$m =
  Mojolicious::Routes::Match->new(GET => '/nodetect3.xml/rly.txt')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect4')->match($r);
is $m->stack->[0]{controller}, 'baz',  'right value';
is $m->stack->[0]{action},     'more', 'right value';
is $m->stack->[0]{format},     'json', 'right value';
is $m->stack->[1], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect4.txt')->match($r);
is $m->stack->[0]{controller}, 'baz',  'right value';
is $m->stack->[0]{action},     'more', 'right value';
is $m->stack->[0]{format},     'txt',  'right value';
is $m->stack->[1], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect4.xml')->match($r);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect4/ya')->match($r);
is $m->stack->[0]{controller}, 'baz',  'right value';
is $m->stack->[0]{action},     'ya',   'right value';
is $m->stack->[0]{format},     'json', 'right value';
is $m->stack->[1], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect4.txt/ya')->match($r);
is $m->stack->[0]{controller}, 'baz', 'right value';
is $m->stack->[0]{action},     'ya',  'right value';
is $m->stack->[0]{format},     'txt', 'right value';
is $m->stack->[1], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect4/ya.xml')->match($r);
is $m->stack->[0], undef, 'no value';
$m =
  Mojolicious::Routes::Match->new(GET => '/nodetect4.txt/ya.xml')->match($r);
is $m->stack->[0], undef, 'no value';
