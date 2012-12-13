use Mojo::Base -strict;

use Test::More;
use Mojo::ByteStream 'b';
use Mojolicious::Routes::Pattern;

# Normal pattern with text, placeholders and a default value
my $pattern = Mojolicious::Routes::Pattern->new('/test/(controller)/:action');
$pattern->defaults({action => 'index'});
my $result = $pattern->match('/test/foo/bar', 1);
is $result->{controller}, 'foo', 'right value';
is $result->{action},     'bar', 'right value';
$result = $pattern->match('/test/foo');
is $result->{controller}, 'foo',   'right value';
is $result->{action},     'index', 'right value';
$result = $pattern->match('/test/foo/');
is $result->{controller}, 'foo',   'right value';
is $result->{action},     'index', 'right value';
$result = $pattern->match('/test/');
is $result, undef, 'no result';
is $pattern->render({controller => 'foo'}), '/test/foo', 'right result';

# Root
$pattern = Mojolicious::Routes::Pattern->new('/');
$pattern->defaults({action => 'index'});
$result = $pattern->match('/test/foo/bar');
is $result, undef, 'no result';
$result = $pattern->match('/');
is $result->{action}, 'index', 'right value';
is $pattern->render, '/', 'right result';

# Regex in pattern
$pattern = Mojolicious::Routes::Pattern->new('/test/(controller)/:action/(id)',
  id => '\d+');
$pattern->defaults({action => 'index', id => 1});
$result = $pattern->match('/test/foo/bar/203');
is $result->{controller}, 'foo', 'right value';
is $result->{action},     'bar', 'right value';
is $result->{id},         203,   'right value';
$result = $pattern->match('/test/foo/bar/baz');
is_deeply $result, undef, 'no result';
is $pattern->render({controller => 'zzz', action => 'index', id => 13}),
  '/test/zzz/index/13', 'right result';
is $pattern->render({controller => 'zzz'}), '/test/zzz', 'right result';

# Quoted placeholders
$pattern = Mojolicious::Routes::Pattern->new('/(:controller)test/(action)');
$pattern->defaults({action => 'index'});
$result = $pattern->match('/footest/bar');
is $result->{controller}, 'foo', 'right value';
is $result->{action},     'bar', 'right value';
is $pattern->render({controller => 'zzz', action => 'lala'}), '/zzztest/lala',
  'right result';
$result = $pattern->match('/test/lala');
is $result, undef, 'no result';

# Relaxed
$pattern = Mojolicious::Routes::Pattern->new('/test/#controller/:action');
$result  = $pattern->match('/test/foo.bar/baz');
is $result->{controller}, 'foo.bar', 'right value';
is $result->{action},     'baz',     'right value';
is $pattern->render({controller => 'foo.bar', action => 'baz'}),
  '/test/foo.bar/baz', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/test/(#groovy)');
$result  = $pattern->match('/test/foo.bar');
is $pattern->defaults->{format}, undef, 'no value';
is $result->{groovy}, 'foo.bar', 'right value';
is $result->{format}, undef,     'no value';
is $pattern->render({groovy => 'foo.bar'}), '/test/foo.bar', 'right result';

# Wildcard
$pattern = Mojolicious::Routes::Pattern->new('/test/(:controller)/(*action)');
$result  = $pattern->match('/test/foo/bar.baz/yada');
is $result->{controller}, 'foo',          'right value';
is $result->{action},     'bar.baz/yada', 'right value';
is $pattern->render({controller => 'foo', action => 'bar.baz/yada'}),
  '/test/foo/bar.baz/yada', 'right result';
$pattern = Mojolicious::Routes::Pattern->new('/tset/:controller/*action');
$result  = $pattern->match('/tset/foo/bar.baz/yada');
is $result->{controller}, 'foo',          'right value';
is $result->{action},     'bar.baz/yada', 'right value';
is $pattern->render({controller => 'foo', action => 'bar.baz/yada'}),
  '/tset/foo/bar.baz/yada', 'right result';

# Render false value
$pattern = Mojolicious::Routes::Pattern->new('/:id');
is $pattern->render({id => 0}), '/0', 'right result';

# Regex in path
$pattern = Mojolicious::Routes::Pattern->new('/:test');
$result  = $pattern->match('/test(test)(\Qtest\E)(');
is $result->{test}, 'test(test)(\Qtest\E)(', 'right value';
is $pattern->render({test => '23'}), '/23', 'right result';

# Regex in pattern
$pattern = Mojolicious::Routes::Pattern->new('/.+(:test)');
$result  = $pattern->match('/.+test');
is $result->{test}, 'test', 'right value';
is $pattern->render({test => '23'}), '/.+23', 'right result';

# Unusual values
$pattern = Mojolicious::Routes::Pattern->new('/:test');
my $value = b('abc%E4cba')->url_unescape->to_string;
$result = $pattern->match("/$value");
is $result->{test}, $value, 'right value';
is $pattern->render({test => $value}), "/$value", 'right result';
$value  = b('abc%FCcba')->url_unescape->to_string;
$result = $pattern->match("/$value");
is $result->{test}, $value, 'right value';
is $pattern->render({test => $value}), "/$value", 'right result';
$value  = b('abc%DFcba')->url_unescape->to_string;
$result = $pattern->match("/$value");
is $result->{test}, $value, 'right value';
is $pattern->render({test => $value}), "/$value", 'right result';
$value  = b('abc%24cba')->url_unescape->to_string;
$result = $pattern->match("/$value");
is $result->{test}, $value, 'right value';
is $pattern->render({test => $value}), "/$value", 'right result';
$value  = b('abc%20cba')->url_unescape->to_string;
$result = $pattern->match("/$value");
is $result->{test}, $value, 'right value';
is $pattern->render({test => $value}), "/$value", 'right result';

# Format detection
$pattern = Mojolicious::Routes::Pattern->new('/test');
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
$result = $pattern->match('/test.xml', 1);
ok $pattern->regex,        'regex has been compiled on demand';
ok $pattern->format_regex, 'format regex has been compiled on demand';
is $result->{action}, 'index', 'right value';
is $result->{format}, 'xml',   'right value';
$pattern = Mojolicious::Routes::Pattern->new('/test.json');
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
$result = $pattern->match('/test.json');
ok $pattern->regex, 'regex has been compiled on demand';
ok !$pattern->format_regex, 'no format regex';
is $result->{action}, 'index', 'right value';
is $result->{format}, undef,   'no value';
$result = $pattern->match('/test.json', 1);
is $result->{action}, 'index', 'right value';
is $result->{format}, undef,   'no value';
$result = $pattern->match('/test.xml');
is $result, undef, 'no result';
$result = $pattern->match('/test');
is $result, undef, 'no result';

# Formats without detection
$pattern = Mojolicious::Routes::Pattern->new('/test');
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
$result = $pattern->match('/test.xml');
ok $pattern->regex, 'regex has been compiled on demand';
ok !$pattern->format_regex, 'no format regex';
is $result, undef, 'no result';
$result = $pattern->match('/test');
is $result->{action}, 'index', 'right value';

# Format detection disabled
$pattern = Mojolicious::Routes::Pattern->new('/test', format => 0);
$pattern->defaults({action => 'index'});
ok !$pattern->regex,        'no regex';
ok !$pattern->format_regex, 'no format regex';
$result = $pattern->match('/test', 1);
ok $pattern->regex, 'regex has been compiled on demand';
ok !$pattern->format_regex, 'no format regex';
is $result->{action}, 'index', 'right value';
is $result->{format}, undef,   'no value';
$result = $pattern->match('/test.xml', 1);
is $result, undef, 'no result';

# Special pattern for disabling format detection
$pattern = Mojolicious::Routes::Pattern->new(format => 0);
is $pattern->constraints->{format}, 0, 'right value';
$pattern->defaults({action => 'index'});
$result = $pattern->match('/', 1);
is $result->{action}, 'index', 'right value';
is $result->{format}, undef,   'no value';
$result = $pattern->match('/.xml', 1);
is $result, undef, 'no result';

# Versioned pattern
$pattern = Mojolicious::Routes::Pattern->new('/:test/v1.0');
$pattern->defaults({action => 'index', format => 'html'});
$result = $pattern->match('/foo/v1.0', 1);
is $result->{test},   'foo',   'right value';
is $result->{action}, 'index', 'right value';
is $result->{format}, 'html',  'right value';
is $pattern->render($result), '/foo/v1.0', 'right result';
is $pattern->render($result, 1), '/foo/v1.0.html', 'right result';
is $pattern->render({%$result, format => undef}, 1), '/foo/v1.0',
  'right result';
$result = $pattern->match('/foo/v1.0.txt', 1);
is $result->{test},   'foo',   'right value';
is $result->{action}, 'index', 'right value';
is $result->{format}, 'txt',   'right value';
is $pattern->render($result), '/foo/v1.0', 'right result';
is $pattern->render($result, 1), '/foo/v1.0.txt', 'right result';
$result = $pattern->match('/foo/v2.0', 1);
is $result, undef, 'no result';

done_testing();
