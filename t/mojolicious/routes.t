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
$r->route('/0')->to(null => 1);

# /alternatives
# /alternatives/0
# /alternatives/test
# /alternatives/23
$r->route('/alternatives/:foo', foo => [qw(0 test 23)])->to(foo => 11);

# /alternatives2/0
# /alternatives2/test
# /alternatives2/23
$r->route('/alternatives2/:foo', foo => [qw(0 test 23)]);

# /alternatives3/foo
# /alternatives3/foobar
$r->route('/alternatives3/:foo', foo => [qw(foo foobar)]);

# /alternatives4/foo
# /alternatives4/foo.bar
$r->route('/alternatives4/:foo', foo => [qw(foo foo.bar)]);

# /optional/*
# /optional/*/*
$r->route('/optional/:foo/:bar')->to(bar => 'test');

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
my $bridge = $r->bridge('/articles/:id')
  ->to(controller => 'articles', action => 'load', format => 'html');
$bridge->route('/edit')->to(controller => 'articles', action => 'edit');
$bridge->route('/delete')
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

# /edge/gift
my $edge = $r->route('/edge');
my $auth = $edge->bridge('/auth')->to('auth#check');
$auth->route('/about/')->to('pref#about');
$auth->bridge->to('album#allow')->route('/album/create/')->to('album#create');
$auth->route('/gift/')->to('gift#index')->name('gift');

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
is $second->render('', {}), '/source/second', 'right result';
$second->remove;
is $second->render('', {}), '/second', 'right result';
$target->add_child($first)->add_child($second);
is $second->render('', {}), '/target/second', 'right result';

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
my $m = Mojolicious::Routes::Match->new(GET => '/clean');
$m->match($r, $c);
is $m->root, $r, 'right root';
is $m->endpoint->name, 'very_clean', 'right name';
is $m->stack->[0]{clean},     1,     'right value';
is $m->stack->[0]{something}, undef, 'no value';
is $m->path_for, '/clean', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/clean/too');
$m->match($r, $c);
is $m->stack->[0]{clean},     undef, 'no value';
is $m->stack->[0]{something}, 1,     'right value';
is $m->path_for, '/clean/too', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# No match
$m = Mojolicious::Routes::Match->new(GET => '/does_not_exist');
$m->match($r, $c);
is $m->root, $r, 'right root';
is $m->endpoint, undef, 'no endpoint';
is_deeply $m->stack, [], 'empty stack';
is_deeply $m->captures, {}, 'empty captures';

# Introspect
is $r->find('very_clean')->to_string, '/clean', 'right pattern';
is $r->find('0')->to_string,          '/0',     'right pattern';
is $r->find('test_edit')->to_string, '/:controller/test/edit', 'right pattern';
is $r->find('articles_delete')->to_string, '/articles/:id/delete',
  'right pattern';
is $r->find('nodetect')->pattern->constraints->{format}, 0, 'right value';
is $r->find('nodetect')->to->{controller}, 'foo', 'right controller';

# Null route
$m = Mojolicious::Routes::Match->new(GET => '/0');
$m->match($r, $c);
is $m->stack->[0]{null}, 1, 'right value';
is $m->path_for, '/0', 'right path';

# Alternatives with default
$m = Mojolicious::Routes::Match->new(GET => '/alternatives');
$m->match($r, $c);
is $m->stack->[0]{foo}, 11, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives', 'right path';
is $m->path_for(format => 'txt'), '/alternatives/11.txt', 'right path';
is $m->path_for(foo => 12, format => 'txt'), '/alternatives/12.txt',
  'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/0');
$m->match($r, $c);
is $m->stack->[0]{foo}, 0, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives/0', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/test');
$m->match($r, $c);
is $m->stack->[0]{foo}, 'test', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/23');
$m->match($r, $c);
is $m->stack->[0]{foo}, 23, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives/23', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/24');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/tset');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/00');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
is $m->path_for('alternativesfoo'), '/alternatives', 'right path';
is $m->path_for('alternativesfoo', format => 'txt'), '/alternatives/11.txt',
  'right path';
is $m->path_for('alternativesfoo', foo => 12, format => 'txt'),
  '/alternatives/12.txt', 'right path';

# Alternatives without default
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/0');
$m->match($r, $c);
is $m->stack->[0]{foo}, 0, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives2/0', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/test');
$m->match($r, $c);
is $m->stack->[0]{foo}, 'test', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives2/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/23');
$m->match($r, $c);
is $m->stack->[0]{foo}, 23, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives2/23', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/24');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/tset');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives2/00');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
is $m->path_for('alternatives2foo'), '/alternatives2/', 'right path';
is $m->path_for('alternatives2foo', foo => 0), '/alternatives2/0',
  'right path';

# Alternatives with similar start
$m = Mojolicious::Routes::Match->new(GET => '/alternatives3/foo');
$m->match($r, $c);
is $m->stack->[0]{foo}, 'foo', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives3/foo', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives3/foobar');
$m->match($r, $c);
is $m->stack->[0]{foo}, 'foobar', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives3/foobar', 'right path';

# Alternatives with special characters
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/foo');
$m->match($r, $c);
is $m->stack->[0]{foo}, 'foo', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives4/foo', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/foo.bar');
$m->match($r, $c);
is $m->stack->[0]{foo}, 'foo.bar', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/alternatives4/foo.bar', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/fooobar');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/bar');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/alternatives4/bar.foo');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Optional placeholder
$m = Mojolicious::Routes::Match->new(GET => '/optional/23');
$m->match($r, $c);
is $m->stack->[0]{foo}, 23,     'right value';
is $m->stack->[0]{bar}, 'test', 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/optional/23', 'right path';
is $m->path_for(format => 'txt'), '/optional/23/test.txt', 'right path';
is $m->path_for(foo => 12, format => 'txt'), '/optional/12/test.txt',
  'right path';
is $m->path_for('optionalfoobar', format => 'txt'), '/optional/23/test.txt',
  'right path';
$m = Mojolicious::Routes::Match->new(GET => '/optional/23/24');
$m->match($r, $c);
is $m->stack->[0]{foo}, 23, 'right value';
is $m->stack->[0]{bar}, 24, 'right value';
is @{$m->stack}, 1, 'right number of elements';
is $m->path_for, '/optional/23/24', 'right path';
is $m->path_for(format => 'txt'), '/optional/23/24.txt', 'right path';
is $m->path_for('optionalfoobar'), '/optional/23/24', 'right path';
is $m->path_for('optionalfoobar', foo => 0), '/optional/0/24', 'right path';

# Real world example using most features at once
$m = Mojolicious::Routes::Match->new(GET => '/articles/1/edit');
$m->match($r, $c);
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
$m = Mojolicious::Routes::Match->new(GET => '/articles/1/delete');
$m->match($r, $c);
is $m->stack->[1]{controller}, 'articles', 'right value';
is $m->stack->[1]{action},     'delete',   'right value';
is $m->stack->[1]{format},     undef,      'no value';
is $m->path_for, '/articles/1/delete', 'right path';
is @{$m->stack}, 2, 'right number of elements';

# Root
$m = Mojolicious::Routes::Match->new(GET => '/');
$m->match($r, $c);
is $m->captures->{controller}, 'hello', 'right value';
is $m->captures->{action},     'world', 'right value';
is $m->stack->[0]{controller}, 'hello', 'right value';
is $m->stack->[0]{action},     'world', 'right value';
is $m->path_for, '/', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Path and captures
$m = Mojolicious::Routes::Match->new(GET => '/foo/test/edit');
$m->match($r, $c);
is $m->captures->{controller}, 'foo',  'right value';
is $m->captures->{action},     'edit', 'right value';
is $m->stack->[0]{controller}, 'foo',  'right value';
is $m->stack->[0]{action},     'edit', 'right value';
is $m->path_for, '/foo/test/edit', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/foo/testedit');
$m->match($r, $c);
is $m->captures->{controller}, 'foo',      'right value';
is $m->captures->{action},     'testedit', 'right value';
is $m->stack->[0]{controller}, 'foo',      'right value';
is $m->stack->[0]{action},     'testedit', 'right value';
is $m->path_for, '/foo/testedit', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Optional captures in sub route with requirement
$m = Mojolicious::Routes::Match->new(GET => '/bar/test/delete/22');
$m->match($r, $c);
is $m->captures->{controller}, 'bar',    'right value';
is $m->captures->{action},     'delete', 'right value';
is $m->captures->{id},         22,       'right value';
is $m->stack->[0]{controller}, 'bar',    'right value';
is $m->stack->[0]{action},     'delete', 'right value';
is $m->stack->[0]{id},         22,       'right value';
is $m->path_for, '/bar/test/delete/22', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Defaults in sub route
$m = Mojolicious::Routes::Match->new(GET => '/bar/test/delete');
$m->match($r, $c);
is $m->captures->{controller}, 'bar',    'right value';
is $m->captures->{action},     'delete', 'right value';
is $m->captures->{id},         23,       'right value';
is $m->stack->[0]{controller}, 'bar',    'right value';
is $m->stack->[0]{action},     'delete', 'right value';
is $m->stack->[0]{id},         23,       'right value';
is $m->path_for, '/bar/test/delete', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Chained routes
$m = Mojolicious::Routes::Match->new(GET => '/test2/foo');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'test2', 'right value';
is $m->stack->[1]{controller}, 'index', 'right value';
is $m->stack->[2]{controller}, 'baz',   'right value';
is $m->captures->{controller}, 'baz', 'right value';
is $m->path_for, '/test2/foo', 'right path';
is @{$m->stack}, 3, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/test2/bar');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'test2',  'right value';
is $m->stack->[1]{controller}, 'index',  'right value';
is $m->stack->[2]{controller}, 'lalala', 'right value';
is $m->captures->{controller}, 'lalala', 'right value';
is $m->path_for, '/test2/bar', 'right path';
is @{$m->stack}, 3, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/test2/baz');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'test2', 'right value';
is $m->stack->[1]{controller}, 'just',  'right value';
is $m->stack->[1]{action},     'works', 'right value';
is $m->stack->[2], undef, 'no value';
is $m->captures->{controller}, 'just', 'right value';
is $m->path_for, '/test2/baz', 'right path';
is @{$m->stack}, 2, 'right number of elements';

# Named path_for
$m = Mojolicious::Routes::Match->new(GET => '/alternatives/test');
$m->match($r, $c);
is $m->path_for, '/alternatives/test', 'right path';
is $m->path_for('test_edit', controller => 'foo'), '/foo/test/edit',
  'right path';
is $m->path_for('test_edit', {controller => 'foo'}), '/foo/test/edit',
  'right path';
is @{$m->stack}, 1, 'right number of elements';

# Wildcards
$m = Mojolicious::Routes::Match->new(GET => '/wildcards/1/hello/there');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'wild',        'right value';
is $m->stack->[0]{action},     'card',        'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/1/hello/there', 'right path';
is $m->path_for(wildcard => ''), '/wildcards/1/', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/wildcards/2/hello/there');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'card',        'right value';
is $m->stack->[0]{action},     'wild',        'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/2/hello/there', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/wildcards/3/hello/there/foo');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'very',        'right value';
is $m->stack->[0]{action},     'dangerous',   'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/3/hello/there/foo', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/wildcards/4/hello/there/foo');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'somewhat',    'right value';
is $m->stack->[0]{action},     'dangerous',   'right value';
is $m->stack->[0]{wildcard},   'hello/there', 'right value';
is $m->path_for, '/wildcards/4/hello/there/foo', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Special characters
$m = Mojolicious::Routes::Match->new(GET => '/wildcards/1/♥');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'wild', 'right value';
is $m->stack->[0]{action},     'card', 'right value';
is $m->stack->[0]{wildcard},   '♥',  'right value';
is $m->path_for, '/wildcards/1/♥', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(
  GET => '/wildcards/1/http://www.google.com');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'wild',                  'right value';
is $m->stack->[0]{action},     'card',                  'right value';
is $m->stack->[0]{wildcard},   'http://www.google.com', 'right value';
is $m->path_for, '/wildcards/1/http://www.google.com', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/wildcards/1/%foo%bar%');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'wild',      'right value';
is $m->stack->[0]{action},     'card',      'right value';
is $m->stack->[0]{wildcard},   '%foo%bar%', 'right value';
is $m->path_for, '/wildcards/1/%foo%bar%', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Format
$m = Mojolicious::Routes::Match->new(GET => '/format');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'hello', 'right value';
is $m->stack->[0]{action},     'you',   'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->path_for, '/format', 'right path';
is $m->path_for(format => undef),  '/format',      'right path';
is $m->path_for(format => 'html'), '/format.html', 'right path';
is $m->path_for(format => 'txt'),  '/format.txt',  'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format.html');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'hello', 'right value';
is $m->stack->[0]{action},     'you',   'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->path_for, '/format', 'right path';
is $m->path_for(format => undef),  '/format',      'right path';
is $m->path_for(format => 'html'), '/format.html', 'right path';
is $m->path_for(format => 'txt'),  '/format.txt',  'right path';
is @{$m->stack}, 1, 'right number of elements';

# Format with regex constraint
$m = Mojolicious::Routes::Match->new(GET => '/format2');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format2.txt');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'we',    'right value';
is $m->stack->[0]{action},     'howdy', 'right value';
is $m->stack->[0]{format},     'txt',   'right value';
is $m->path_for, '/format2.txt', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format2.html');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format2.txt.txt');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Format with constraint alternatives
$m = Mojolicious::Routes::Match->new(GET => '/format3');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format3.txt');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'we',     'right value';
is $m->stack->[0]{action},     'cheers', 'right value';
is $m->stack->[0]{format},     'txt',    'right value';
is $m->path_for, '/format3.txt', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format3.text');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'we',     'right value';
is $m->stack->[0]{action},     'cheers', 'right value';
is $m->stack->[0]{format},     'text',   'right value';
is $m->path_for, '/format3.text', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format3.html');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format3.txt.txt');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Format with constraint and default
$m = Mojolicious::Routes::Match->new(GET => '/format4');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'us',   'right value';
is $m->stack->[0]{action},     'yay',  'right value';
is $m->stack->[0]{format},     'html', 'right value';
is $m->path_for, '/format4.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format4.html');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'us',   'right value';
is $m->stack->[0]{action},     'yay',  'right value';
is $m->stack->[0]{format},     'html', 'right value';
is $m->path_for, '/format4.html', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format4.txt');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format4.txt.html');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Forbidden format
$m = Mojolicious::Routes::Match->new(GET => '/format5');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'us',  'right value';
is $m->stack->[0]{action},     'wow', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->path_for, '/format5', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format5.html');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Forbidden format and default
$m = Mojolicious::Routes::Match->new(GET => '/format6');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'us',  'right value';
is $m->stack->[0]{action},     'doh', 'right value';
is $m->stack->[0]{format},     'xml', 'right value';
is $m->path_for, '/format6', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format6.xml');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Formats with similar start
$m = Mojolicious::Routes::Match->new(GET => '/format7.foo');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'perl',  'right value';
is $m->stack->[0]{action},     'rocks', 'right value';
is $m->stack->[0]{format},     'foo',   'right value';
is $m->path_for, '/format7.foo', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format7.foobar');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'perl',   'right value';
is $m->stack->[0]{action},     'rocks',  'right value';
is $m->stack->[0]{format},     'foobar', 'right value';
is $m->path_for, '/format7.foobar', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/format7.foobarbaz');
$m->match($r, $c);
is @{$m->stack}, 0, 'right number of elements';

# Request methods
$m = Mojolicious::Routes::Match->new(GET => '/method/get.html');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'method', 'right value';
is $m->stack->[0]{action},     'get',    'right value';
is $m->stack->[0]{format},     'html',   'right value';
is $m->path_for, '/method/get', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(POST => '/method/post');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'method', 'right value';
is $m->stack->[0]{action},     'post',   'right value';
is $m->stack->[0]{format},     undef,    'no value';
is $m->path_for, '/method/post', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(GET => '/method/post_get');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'method',   'right value';
is $m->stack->[0]{action},     'post_get', 'right value';
is $m->stack->[0]{format},     undef,      'no value';
is $m->path_for, '/method/post_get', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(post => '/method/post_get');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'method',   'right value';
is $m->stack->[0]{action},     'post_get', 'right value';
is $m->stack->[0]{format},     undef,      'no value';
is $m->path_for, '/method/post_get', 'right path';
is @{$m->stack}, 1, 'right number of elements';
$m = Mojolicious::Routes::Match->new(delete => '/method/post_get');
$m->match($r, $c);
is $m->stack->[0]{controller}, undef, 'no value';
is $m->stack->[0]{action},     undef, 'no value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->path_for, undef, 'no path';
is @{$m->stack}, 1, 'right number of elements';

# Not found
$m = Mojolicious::Routes::Match->new(GET => '/not_found');
$m->match($r, $c);
is $m->path_for('test_edit', controller => 'foo'), '/foo/test/edit',
  'right path';
is @{$m->stack}, 0, 'no elements';

# Simplified form
$m = Mojolicious::Routes::Match->new(GET => '/simple/form');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'test-test', 'right value';
is $m->stack->[0]{action},     'test',      'right value';
is $m->stack->[0]{format},     undef,       'no value';
is $m->path_for, '/simple/form', 'right path';
is $m->path_for('current'), '/simple/form', 'right path';
is @{$m->stack}, 1, 'right number of elements';

# Special edge case with nested bridges
$m = Mojolicious::Routes::Match->new(GET => '/edge/auth/gift');
$m->match($r, $c);
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
$m = Mojolicious::Routes::Match->new(GET => '/regex/alternatives/foo');
$m->match($r, $c);
is $m->stack->[0]{controller},   'regex',        'right value';
is $m->stack->[0]{action},       'alternatives', 'right value';
is $m->stack->[0]{alternatives}, 'foo',          'right value';
is $m->stack->[0]{format},       undef,          'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/regex/alternatives/foo', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/regex/alternatives/bar');
$m->match($r, $c);
is $m->stack->[0]{controller},   'regex',        'right value';
is $m->stack->[0]{action},       'alternatives', 'right value';
is $m->stack->[0]{alternatives}, 'bar',          'right value';
is $m->stack->[0]{format},       undef,          'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/regex/alternatives/bar', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/regex/alternatives/baz');
$m->match($r, $c);
is $m->stack->[0]{controller},   'regex',        'right value';
is $m->stack->[0]{action},       'alternatives', 'right value';
is $m->stack->[0]{alternatives}, 'baz',          'right value';
is $m->stack->[0]{format},       undef,          'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/regex/alternatives/baz', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/regex/alternatives/yada');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';

# Route with version
$m = Mojolicious::Routes::Match->new(GET => '/versioned/1.0/test');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'bar', 'right value';
is $m->stack->[0]{action},     'baz', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/1.0/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/1.0/test.xml');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'bar', 'right value';
is $m->stack->[0]{action},     'baz', 'right value';
is $m->stack->[0]{format},     'xml', 'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/1.0/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/2.4/test');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'foo', 'right value';
is $m->stack->[0]{action},     'bar', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/2.4/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/2.4/test.xml');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'foo', 'right value';
is $m->stack->[0]{action},     'bar', 'right value';
is $m->stack->[0]{format},     'xml', 'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/2.4/test', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/3.0/test');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/3.4/test');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/0.3/test');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';

# Route with version at the end
$m = Mojolicious::Routes::Match->new(GET => '/versioned/too/1.0');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'too', 'right value';
is $m->stack->[0]{action},     'foo', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/too/1.0', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/versioned/too/2.0');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'too', 'right value';
is $m->stack->[0]{action},     'bar', 'right value';
is $m->stack->[0]{format},     undef, 'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/versioned/too/2.0', 'right path';

# Multiple extensions
$m = Mojolicious::Routes::Match->new(GET => '/multi/foo.bar');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'just',  'right value';
is $m->stack->[0]{action},     'works', 'right value';
is $m->stack->[0]{format},     undef,   'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/multi/foo.bar', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/multi/foo.bar.baz');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/multi/bar.baz');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'works', 'right value';
is $m->stack->[0]{action},     'too',   'right value';
is $m->stack->[0]{format},     'xml',   'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/multi/bar.baz', 'right path';

# Disabled format detection inheritance
$m = Mojolicious::Routes::Match->new(GET => '/nodetect');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'foo',  'right value';
is $m->stack->[0]{action},     'none', 'right value';
is $m->stack->[0]{format},     undef,  'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/nodetect', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect.txt');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2.txt');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'bar',   'right value';
is $m->stack->[0]{action},     'hyper', 'right value';
is $m->stack->[0]{format},     'txt',   'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/nodetect2.txt', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2.html');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'bar',   'right value';
is $m->stack->[0]{action},     'hyper', 'right value';
is $m->stack->[0]{format},     'html',  'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/nodetect2.html', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/nodetect2.xml');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';

# Removed routes
$m = Mojolicious::Routes::Match->new(GET => '/target/first');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'target', 'right value';
is $m->stack->[0]{action},     'first',  'right value';
is $m->stack->[0]{format},     undef,    'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/target/first', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/target/first.xml');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/source/first');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/target/second');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'target', 'right value';
is $m->stack->[0]{action},     'second', 'right value';
is $m->stack->[0]{format},     undef,    'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/target/second', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/target/second.xml');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'target', 'right value';
is $m->stack->[0]{action},     'second', 'right value';
is $m->stack->[0]{format},     'xml',    'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/target/second', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/source/second');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';
$m = Mojolicious::Routes::Match->new(GET => '/source/third');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'source', 'right value';
is $m->stack->[0]{action},     'third',  'right value';
is $m->stack->[0]{format},     undef,    'no value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/source/third', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/source/third.xml');
$m->match($r, $c);
is $m->stack->[0]{controller}, 'source', 'right value';
is $m->stack->[0]{action},     'third',  'right value';
is $m->stack->[0]{format},     'xml',    'right value';
is $m->stack->[1], undef, 'no value';
is $m->path_for, '/source/third', 'right path';
$m = Mojolicious::Routes::Match->new(GET => '/target/third');
$m->match($r, $c);
is $m->stack->[0], undef, 'no value';

done_testing();
