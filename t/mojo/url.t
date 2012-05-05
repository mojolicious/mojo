use Mojo::Base -strict;

use utf8;

use Test::More tests => 398;

# "I don't want you driving around in a car you built yourself.
#  You can sit there complaining, or you can knit me some seat belts."
use Mojo::URL;

# Simple
my $url = Mojo::URL->new('HtTp://Kraih.Com');
is $url->scheme, 'HtTp',      'right scheme';
is $url->host,   'Kraih.Com', 'right host';
is "$url", 'http://kraih.com', 'right format';

# Advanced
$url = Mojo::URL->new(
  'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#/!%?@3');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, 'sri:foobar', 'right userinfo';
is $url->host,     'kraih.com', 'right host';
is $url->port,     '8080', 'right port';
is $url->path,     '/test/index.html', 'right path';
is $url->query,    'monkey=biz&foo=1', 'right query';
is $url->fragment, '/!%?@3', 'right fragment';
is "$url",
  'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#/!%?@3',
  'right format';
$url->path('/index.xml');
is "$url",
  'http://sri:foobar@kraih.com:8080/index.xml?monkey=biz&foo=1#/!%?@3',
  'right format';

# Advanced fragment roundtrip
$url = Mojo::URL->new('http://localhost#AZaz09-._~!$&\'()*+,;=%:@/?');
is $url->scheme,   'http',                        'right scheme';
is $url->host,     'localhost',                   'right host';
is $url->fragment, 'AZaz09-._~!$&\'()*+,;=%:@/?', 'right fragment';
is "$url", 'http://localhost#AZaz09-._~!$&\'()*+,;=%:@/?', 'right format';

# Parameters
$url = Mojo::URL->new(
  'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, 'sri:foobar', 'right userinfo';
is $url->host,     'kraih.com', 'right host';
is $url->port,     '8080', 'right port';
is $url->path,     '', 'no path';
is $url->query,    '_monkey=biz%3B&_monkey=23', 'right query';
is_deeply $url->query->to_hash, {_monkey => ['biz;', 23]}, 'right structure';
is $url->fragment, '23', 'right fragment';
is "$url", 'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23',
  'right format';
$url->query(monkey => 'foo');
is "$url", 'http://sri:foobar@kraih.com:8080?monkey=foo#23', 'right format';
$url->query([monkey => 'bar']);
is "$url", 'http://sri:foobar@kraih.com:8080?monkey=bar#23', 'right format';
$url->query({foo => 'bar'});
is "$url", 'http://sri:foobar@kraih.com:8080?monkey=bar&foo=bar#23',
  'right format';
$url->query('foo');
is "$url", 'http://sri:foobar@kraih.com:8080?foo#23', 'right format';
$url->query('foo=bar');
is "$url", 'http://sri:foobar@kraih.com:8080?foo=bar#23', 'right format';
$url->query([foo => undef]);
is "$url", 'http://sri:foobar@kraih.com:8080#23', 'right format';
$url->query([foo => 23, bar => 24, baz => 25]);
is "$url", 'http://sri:foobar@kraih.com:8080?foo=23&bar=24&baz=25#23',
  'right format';
$url->query([foo => 26, bar => undef, baz => undef]);
is "$url", 'http://sri:foobar@kraih.com:8080?foo=26#23', 'right format';

# Query string
$url = Mojo::URL->new(
  'http://sri:foobar@kraih.com:8080?_monkeybiz%3B&_monkey;23#23');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, 'sri:foobar', 'right userinfo';
is $url->host,     'kraih.com', 'right host';
is $url->port,     '8080', 'right port';
is $url->path,     '', 'no path';
is $url->query,    '_monkeybiz%3B&_monkey;23', 'right query';
is_deeply $url->query->params, ['_monkeybiz;', '', '_monkey', '', 23, ''],
  'right structure';
is $url->query, '_monkeybiz%3B=&_monkey=&23=', 'right query';
is $url->fragment, '23', 'right fragment';
is "$url", 'http://sri:foobar@kraih.com:8080?_monkeybiz%3B=&_monkey=&23=#23',
  'right format';

# Relative
$url = Mojo::URL->new('foo?foo=bar#23');
ok !$url->is_abs, 'is not absolute';
is "$url", 'foo?foo=bar#23', 'right relative version';
$url = Mojo::URL->new('/foo?foo=bar#23');
ok !$url->is_abs, 'is not absolute';
is "$url", '/foo?foo=bar#23', 'right relative version';
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/');
ok $url->is_abs, 'is absolute';
is $url->to_rel, 'foo?foo=bar#23', 'right relative version';

# Relative without scheme
$url = Mojo::URL->new('//localhost/23/');
ok !$url->is_abs, 'is not absolute';
is $url->host, 'localhost', 'right host';
is $url->path, '/23/',      'right path';
is "$url", '//localhost/23/', 'right relative version';
is $url->to_abs(Mojo::URL->new('http://')), 'http://localhost/23/',
  'right absolute version';
is $url->to_abs(Mojo::URL->new('https://')), 'https://localhost/23/',
  'right absolute version';
is $url->to_abs(Mojo::URL->new('http://mojolicio.us')), 'http://localhost/23/',
  'right absolute version';
is $url->to_abs(Mojo::URL->new('http://mojolicio.us:8080')),
  'http://localhost/23/', 'right absolute version';
$url = Mojo::URL->new('///bar/23/');
ok !$url->is_abs, 'is not absolute';
is $url->host, '',         'no host';
is $url->path, '/bar/23/', 'right path';
is "$url", '/bar/23/', 'right relative version';
$url = Mojo::URL->new('////bar//23/');
ok !$url->is_abs, 'is not absolute';
is $url->host, '',           'no host';
is $url->path, '//bar//23/', 'right path';
is "$url", '//bar//23/', 'right relative version';

# Relative (base without trailing slash)
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/baz/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080');
is $url->to_rel, 'baz/foo?foo=bar#23', 'right relative version';
is $url->to_rel->to_abs, 'http://sri:foobar@kraih.com:8080/baz/foo?foo=bar#23',
  'right absolute version';
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/baz/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/baz');
is $url->to_rel, 'baz/foo?foo=bar#23', 'right relative version';
is $url->to_rel->to_abs, 'http://sri:foobar@kraih.com:8080/baz/foo?foo=bar#23',
  'right absolute version';

# Relative (base without authority)
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/baz/foo?foo=bar#23');
$url->base->parse('http://');
is $url->to_rel, '//sri:foobar@kraih.com:8080/baz/foo?foo=bar#23',
  'right relative version';
is $url->to_rel->to_abs, 'http://sri:foobar@kraih.com:8080/baz/foo?foo=bar#23',
  'right absolute version';

# Relative with path
$url = Mojo::URL->new('http://kraih.com/foo/index.html?foo=bar#23');
$url->base->parse('http://kraih.com/foo/');
my $rel = $url->to_rel;
is $rel, 'index.html?foo=bar#23', 'right format';
ok !$rel->is_abs, 'not absolute';
is $rel->to_abs, 'http://kraih.com/foo/index.html?foo=bar#23',
  'right absolute version';

# Relative (base argument)
$url = Mojo::URL->new('http://kraih.com/');
$rel = $url->to_rel($url->clone);
is $rel, '', 'right relative version';
is $rel->to_abs, 'http://kraih.com/', 'right absolute version';
is $rel->to_abs->to_rel, '', 'right relative version';
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/a/'));
is $rel, '..', 'right relative version';
is $rel->to_abs, 'http://kraih.com/', 'right absolute version';
is $rel->to_abs->to_rel, '..', 'right relative version';
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/a/b/'));
is $rel, '../..', 'right relative version';
is $rel->to_abs, 'http://kraih.com/', 'right absolute version';
is $rel->to_abs->to_rel, '../..', 'right relative version';
$url = Mojo::URL->new('http://kraih.com/index.html');
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/'));
is $rel, 'index.html', 'right relative version';
is $rel->to_abs, 'http://kraih.com/index.html', 'right absolute version';
is $rel->to_abs->to_rel, 'index.html', 'right relative version';
$url = Mojo::URL->new('http://kraih.com/index.html');
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/a/'));
is $rel, '../index.html', 'right relative version';
is $rel->to_abs, 'http://kraih.com/index.html', 'right absolute version';
is $rel->to_abs->to_rel, '../index.html', 'right relative version';
$url = Mojo::URL->new('http://kraih.com/index.html');
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/a/b/'));
is $rel, '../../index.html', 'right relative version';
is $rel->to_abs, 'http://kraih.com/index.html', 'right absolute version';
is $rel->to_abs->to_rel, '../../index.html', 'right relative version';
$url = Mojo::URL->new('http://kraih.com/a/b/c/index.html');
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/a/b/'));
is $rel, 'c/index.html', 'right relative version';
is $rel->to_abs, 'http://kraih.com/a/b/c/index.html', 'right absolute version';
is $rel->to_abs->to_rel, 'c/index.html', 'right relative version';
$url = Mojo::URL->new('http://kraih.com/a/b/c/d/index.html');
$rel = $url->to_rel(Mojo::URL->new('http://kraih.com/a/b/'));
is $rel, 'c/d/index.html', 'right relative version';
is $rel->to_abs, 'http://kraih.com/a/b/c/d/index.html',
  'right absolute version';
is $rel->to_abs->to_rel, 'c/d/index.html', 'right relative version';

# Relative path
$url = Mojo::URL->new('http://kraih.com/foo/?foo=bar#23');
$url->path('bar');
is "$url", 'http://kraih.com/foo/bar?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://kraih.com?foo=bar#23');
$url->path('bar');
is "$url", 'http://kraih.com/bar?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://kraih.com/foo?foo=bar#23');
$url->path('bar');
is "$url", 'http://kraih.com/bar?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://kraih.com/foo/bar?foo=bar#23');
$url->path('yada/baz');
is "$url", 'http://kraih.com/foo/yada/baz?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://kraih.com/foo/bar?foo=bar#23');
$url->path('../baz');
is "$url", 'http://kraih.com/foo/../baz?foo=bar#23', 'right path';
$url->path->canonicalize;
is "$url", 'http://kraih.com/baz?foo=bar#23', 'right absolute path';

# Absolute (base without trailing slash)
$url = Mojo::URL->new('/foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar');
ok !$url->is_abs, 'not absolute';
is $url->to_abs, 'http://kraih.com/foo?foo=bar#23', 'right absolute version';
$url = Mojo::URL->new('../cages/birds.gif');
$url->base->parse('http://www.aviary.com/products/intro.html');
ok !$url->is_abs, 'not absolute';
is $url->to_abs, 'http://www.aviary.com/cages/birds.gif',
  'right absolute version';
$url = Mojo::URL->new('.././cages/./birds.gif');
$url->base->parse('http://www.aviary.com/./products/./intro.html');
ok !$url->is_abs, 'not absolute';
is $url->to_abs, 'http://www.aviary.com/cages/birds.gif',
  'right absolute version';

# Absolute with path
$url = Mojo::URL->new('../foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar/baz/');
ok !$url->is_abs, 'not absolute';
is $url->to_abs, 'http://kraih.com/bar/foo?foo=bar#23',
  'right absolute version';
is $url->to_abs->to_rel, '../foo?foo=bar#23', 'right relative version';
is $url->to_abs->to_rel->to_abs, 'http://kraih.com/bar/foo?foo=bar#23',
  'right absolute version';
is $url->to_abs, 'http://kraih.com/bar/foo?foo=bar#23',
  'right absolute version';
is $url->to_abs->base, 'http://kraih.com/bar/baz/', 'right base';

# Real world tests
$url = Mojo::URL->new('http://acme.s3.amazonaws.com'
    . '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, undef, 'no userinfo';
is $url->host,     'acme.s3.amazonaws.com', 'right host';
is $url->port,     undef, 'no port';
is $url->path,     '/mojo/g++-4.2_4.2.3-2ubuntu7_i386.deb', 'right path';
ok !$url->query->to_string, 'no query';
is_deeply $url->query->to_hash, {}, 'right structure';
is $url->fragment, undef, 'no fragment';
is "$url", 'http://acme.s3.amazonaws.com/mojo/g++-4.2_4.2.3-2ubuntu7_i386.deb',
  'right format';

# Clone (advanced)
$url = Mojo::URL->new(
  'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
my $clone = $url->clone;
ok $clone->is_abs,   'is absolute';
is $clone->scheme,   'http', 'right scheme';
is $clone->userinfo, 'sri:foobar', 'right userinfo';
is $clone->host,     'kraih.com', 'right host';
is $clone->port,     '8080', 'right port';
is $clone->path,     '/test/index.html', 'right path';
is $clone->query,    'monkey=biz&foo=1', 'right query';
is $clone->fragment, '23', 'right fragment';
is "$clone",
  'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23',
  'right format';
$clone->path('/index.xml');
is "$clone", 'http://sri:foobar@kraih.com:8080/index.xml?monkey=biz&foo=1#23',
  'right format';

# Clone (with base)
$url = Mojo::URL->new('/test/index.html');
$url->base->parse('http://127.0.0.1');
is "$url", '/test/index.html', 'right format';
$clone = $url->clone;
is "$url", '/test/index.html', 'right format';
ok !$clone->is_abs, 'not absolute';
is $clone->scheme, undef, 'no scheme';
is $clone->host,   '',    'no host';
is $clone->base->scheme, 'http',      'right base scheme';
is $clone->base->host,   '127.0.0.1', 'right base host';
is $clone->path, '/test/index.html', 'right path';
is $clone->to_abs->to_string, 'http://127.0.0.1/test/index.html',
  'right absolute version';

# Clone (with base path)
$url = Mojo::URL->new('test/index.html');
$url->base->parse('http://127.0.0.1/foo/');
is "$url", 'test/index.html', 'right format';
$clone = $url->clone;
is "$url", 'test/index.html', 'right format';
ok !$clone->is_abs, 'not absolute';
is $clone->scheme, undef, 'no scheme';
is $clone->host,   '',    'no host';
is $clone->base->scheme, 'http',      'right base scheme';
is $clone->base->host,   '127.0.0.1', 'right base host';
is $clone->path, 'test/index.html', 'right path';
is $clone->to_abs->to_string, 'http://127.0.0.1/foo/test/index.html',
  'right absolute version';

# IPv6
$url = Mojo::URL->new('http://[::1]:3000/');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   '[::1]', 'right host';
is $url->port,   3000, 'right port';
is $url->path,   '/', 'right path';
is "$url", 'http://[::1]:3000/', 'right format';

# IDNA
$url = Mojo::URL->new('http://bücher.ch:3000/foo');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   'bücher.ch', 'right host';
is $url->ihost,  'xn--bcher-kva.ch', 'right internationalized host';
is $url->port,   3000, 'right port';
is $url->path,   '/foo', 'right path';
is "$url", 'http://xn--bcher-kva.ch:3000/foo', 'right format';
$url = Mojo::URL->new('http://bücher.bücher.ch:3000/foo');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   'bücher.bücher.ch', 'right host';
is $url->ihost,  'xn--bcher-kva.xn--bcher-kva.ch',
  'right internationalized host';
is $url->port, 3000,   'right port';
is $url->path, '/foo', 'right path';
is "$url", 'http://xn--bcher-kva.xn--bcher-kva.ch:3000/foo', 'right format';
$url = Mojo::URL->new('http://bücher.bücher.bücher.ch:3000/foo');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   'bücher.bücher.bücher.ch', 'right host';
is $url->ihost,  'xn--bcher-kva.xn--bcher-kva.xn--bcher-kva.ch',
  'right internationalized host';
is $url->port, 3000,   'right port';
is $url->path, '/foo', 'right path';
is "$url", 'http://xn--bcher-kva.xn--bcher-kva.xn--bcher-kva.ch:3000/foo',
  'right format';

# IDNA (snowman)
$url = Mojo::URL->new('http://☃.net/');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   '☃.net', 'right host';
is $url->ihost,  'xn--n3h.net', 'right internationalized host';
is $url->path,   '/', 'right path';
is "$url", 'http://xn--n3h.net/', 'right format';

# Already absolute
$url = Mojo::URL->new('http://foo.com/');
is $url->to_abs, 'http://foo.com/', 'right absolute version';

# Already relative
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/');
my $url2 = $url->to_rel;
is $url->to_rel, 'foo?foo=bar#23', 'right relative version';

# IRI
$url
  = Mojo::URL->new('http://sharifulin.ru/привет/?q=шарифулин');
is $url->path->parts->[0], 'привет', 'right path part';
is $url->path, '/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82/', 'right path';
is $url->query, 'q=%D1%88%D0%B0%D1%80%D0%B8%D1%84%D1%83%D0%BB%D0%B8%D0%BD',
  'right query';
is $url->query->param('q'), 'шарифулин', 'right query value';

# IRI/IDNA
$url = Mojo::URL->new(
  'http://☃.net/привет/привет/?привет=шарифулин');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   '☃.net', 'right host';
is $url->ihost,  'xn--n3h.net', 'right internationalized host';
is $url->path,   '/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82'
  . '/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82/', 'right host';
is $url->path->parts->[0], 'привет', 'right path part';
is $url->path->parts->[1], 'привет', 'right path part';
is $url->query->param('привет'), 'шарифулин',
  'right query value';
is "$url",
    'http://xn--n3h.net/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82'
  . '/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82/'
  . '?%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82='
  . '%D1%88%D0%B0%D1%80%D0%B8%D1%84%D1%83%D0%BB%D0%B8%D0%BD', 'right format';

# Empty path elements
$url = Mojo::URL->new('http://kraih.com/foo//bar/23/');
$url->base->parse('http://kraih.com/');
ok $url->is_abs, 'is absolute';
is $url->to_rel, 'foo//bar/23/', 'right relative version';
$url = Mojo::URL->new('http://kraih.com//foo//bar/23/');
$url->base->parse('http://kraih.com/');
ok $url->is_abs, 'is absolute';
is $url->to_rel, '/foo//bar/23/', 'right relative version';
$url = Mojo::URL->new('http://kraih.com/foo///bar/23/');
$url->base->parse('http://kraih.com/');
ok $url->is_abs, 'is absolute';
is $url->to_rel, 'foo///bar/23/', 'right relative version';
is $url->to_abs, 'http://kraih.com/foo///bar/23/', 'right absolute version';
ok $url->is_abs, 'is absolute';
is $url->to_rel, 'foo///bar/23/', 'right relative version';

# Merge relative path
$url = Mojo::URL->new('http://foo.bar/baz?yada');
is $url->base,     '',        'no base';
is $url->scheme,   'http',    'right scheme';
is $url->userinfo, undef,     'no userinfo';
is $url->host,     'foo.bar', 'right host';
is $url->port,     undef,     'no port';
is $url->path,     '/baz',    'right path';
is $url->query,    'yada',    'right query';
is $url->fragment, undef,     'no fragment';
is "$url", 'http://foo.bar/baz?yada', 'right absolute URL';
$url = Mojo::URL->new('zzz?Zzz')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz?yada', 'right base';
is $url->scheme,   'http',                    'right scheme';
is $url->userinfo, undef,                     'no userinfo';
is $url->host,     'foo.bar',                 'right host';
is $url->port,     undef,                     'no port';
is $url->path,     '/zzz',                    'right path';
is $url->query,    'Zzz',                     'right query';
is $url->fragment, undef,                     'no fragment';
is "$url", 'http://foo.bar/zzz?Zzz', 'right absolute URL';

# Merge relative path with directory
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, undef,             'no fragment';
is "$url", 'http://foo.bar/baz/index.html?yada', 'right absolute URL';
$url = Mojo::URL->new('zzz?Zzz')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada', 'right base';
is $url->scheme,   'http',                               'right scheme';
is $url->userinfo, undef,                                'no userinfo';
is $url->host,     'foo.bar',                            'right host';
is $url->port,     undef,                                'no port';
is $url->path,     '/baz/zzz',                           'right path';
is $url->query,    'Zzz',                                'right query';
is $url->fragment, undef,                                'no fragment';
is "$url", 'http://foo.bar/baz/zzz?Zzz', 'right absolute URL';

# Merge absolute path
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, undef,             'no fragment';
is "$url", 'http://foo.bar/baz/index.html?yada', 'right absolute URL';
$url = Mojo::URL->new('/zzz?Zzz')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada', 'right base';
is $url->scheme,   'http',                               'right scheme';
is $url->userinfo, undef,                                'no userinfo';
is $url->host,     'foo.bar',                            'right host';
is $url->port,     undef,                                'no port';
is $url->path,     '/zzz',                               'right path';
is $url->query,    'Zzz',                                'right query';
is $url->fragment, undef,                                'no fragment';
is "$url", 'http://foo.bar/zzz?Zzz', 'right absolute URL';

# Merge absolute path without query
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, undef,             'no fragment';
is "$url", 'http://foo.bar/baz/index.html?yada', 'right absolute URL';
$url = Mojo::URL->new('/zzz')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada', 'right base';
is $url->scheme,   'http',                               'right scheme';
is $url->userinfo, undef,                                'no userinfo';
is $url->host,     'foo.bar',                            'right host';
is $url->port,     undef,                                'no port';
is $url->path,     '/zzz',                               'right path';
is $url->query,    '',                                   'no query';
is $url->fragment, undef,                                'no fragment';
is "$url", 'http://foo.bar/zzz', 'right absolute URL';

# Merge absolute path with fragment
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada#test1');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, 'test1',           'right fragment';
is "$url", 'http://foo.bar/baz/index.html?yada#test1', 'right absolute URL';
$url = Mojo::URL->new('/zzz#test2')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada#test1', 'right base';
is $url->scheme,   'http',                                     'right scheme';
is $url->userinfo, undef,                                      'no userinfo';
is $url->host,     'foo.bar',                                  'right host';
is $url->port,     undef,                                      'no port';
is $url->path,     '/zzz',                                     'right path';
is $url->query,    '',                                         'right query';
is $url->fragment, 'test2', 'right fragment';
is "$url", 'http://foo.bar/zzz#test2', 'right absolute URL';

# Merge relative path with fragment
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada#test1');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, 'test1',           'right fragment';
is "$url", 'http://foo.bar/baz/index.html?yada#test1', 'right absolute URL';
$url = Mojo::URL->new('zzz#test2')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada#test1', 'right base';
is $url->scheme,   'http',                                     'right scheme';
is $url->userinfo, undef,                                      'no userinfo';
is $url->host,     'foo.bar',                                  'right host';
is $url->port,     undef,                                      'no port';
is $url->path,     '/baz/zzz',                                 'right path';
is $url->query,    '',                                         'right query';
is $url->fragment, 'test2', 'right fragment';
is "$url", 'http://foo.bar/baz/zzz#test2', 'right absolute URL';

# Merge absolute path without fragment
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada#test1');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, 'test1',           'right fragment';
is "$url", 'http://foo.bar/baz/index.html?yada#test1', 'right absolute URL';
$url = Mojo::URL->new('/zzz')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada#test1', 'right base';
is $url->scheme,   'http',                                     'right scheme';
is $url->userinfo, undef,                                      'no userinfo';
is $url->host,     'foo.bar',                                  'right host';
is $url->port,     undef,                                      'no port';
is $url->path,     '/zzz',                                     'right path';
is $url->query,    '',                                         'right query';
is $url->fragment, undef,                                      'no fragment';
is "$url", 'http://foo.bar/zzz', 'right absolute URL';

# Merge relative path without fragment
$url = Mojo::URL->new('http://foo.bar/baz/index.html?yada#test1');
is $url->base,     '',                'no base';
is $url->scheme,   'http',            'right scheme';
is $url->userinfo, undef,             'no userinfo';
is $url->host,     'foo.bar',         'right host';
is $url->port,     undef,             'no port';
is $url->path,     '/baz/index.html', 'right path';
is $url->query,    'yada',            'right query';
is $url->fragment, 'test1',           'right fragment';
is "$url", 'http://foo.bar/baz/index.html?yada#test1', 'right absolute URL';
$url = Mojo::URL->new('zzz')->base($url)->to_abs;
is $url->base,     'http://foo.bar/baz/index.html?yada#test1', 'right base';
is $url->scheme,   'http',                                     'right scheme';
is $url->userinfo, undef,                                      'no userinfo';
is $url->host,     'foo.bar',                                  'right host';
is $url->port,     undef,                                      'no port';
is $url->path,     '/baz/zzz',                                 'right path';
is $url->query,    '',                                         'right query';
is $url->fragment, undef,                                      'no fragment';
is "$url", 'http://foo.bar/baz/zzz', 'right absolute URL';

# Hosts
$url = Mojo::URL->new('http://mojolicio.us');
is $url->host, 'mojolicio.us', 'right host';
$url = Mojo::URL->new('http://[::1]');
is $url->host, '[::1]', 'right host';
$url = Mojo::URL->new('http://127.0.0.1');
is $url->host, '127.0.0.1', 'right host';
$url = Mojo::URL->new('http://0::127.0.0.1');
is $url->host, '0::127.0.0.1', 'right host';
$url = Mojo::URL->new('http://[0::127.0.0.1]');
is $url->host, '[0::127.0.0.1]', 'right host';
$url = Mojo::URL->new('http://mojolicio.us:3000');
is $url->host, 'mojolicio.us', 'right host';
$url = Mojo::URL->new('http://[::1]:3000');
is $url->host, '[::1]', 'right host';
$url = Mojo::URL->new('http://127.0.0.1:3000');
is $url->host, '127.0.0.1', 'right host';
$url = Mojo::URL->new('http://0::127.0.0.1:3000');
is $url->host, '0::127.0.0.1', 'right host';
$url = Mojo::URL->new('http://[0::127.0.0.1]:3000');
is $url->host, '[0::127.0.0.1]', 'right host';
$url = Mojo::URL->new('http://foo.1.1.1.1.de/');
is $url->host, 'foo.1.1.1.1.de', 'right host';
$url = Mojo::URL->new('http://1.1.1.1.1.1/');
is $url->host, '1.1.1.1.1.1', 'right host';

# "%" in path
$url = Mojo::URL->new('http://mojolicio.us/100%_fun');
is $url->path->parts->[0], '100%_fun', 'right part';
is $url->path, '/100%25_fun', 'right path';
is "$url", 'http://mojolicio.us/100%25_fun', 'right format';
$url = Mojo::URL->new('http://mojolicio.us/100%fun');
is $url->path->parts->[0], '100%fun', 'right part';
is $url->path, '/100%25fun', 'right path';
is "$url", 'http://mojolicio.us/100%25fun', 'right format';
$url = Mojo::URL->new('http://mojolicio.us/100%25_fun');
is $url->path->parts->[0], '100%_fun', 'right part';
is $url->path, '/100%25_fun', 'right path';
is "$url", 'http://mojolicio.us/100%25_fun', 'right format';

# Resolve RFC 1808 examples
my $base = Mojo::URL->new('http://a/b/c/d?q#f');
$url = Mojo::URL->new('g');
is $url->to_abs($base), 'http://a/b/c/g', 'right absolute version';
$url = Mojo::URL->new('./g');
is $url->to_abs($base), 'http://a/b/c/g', 'right absolute version';
$url = Mojo::URL->new('g/');
is $url->to_abs($base), 'http://a/b/c/g/', 'right absolute version';
$url = Mojo::URL->new('//g');
is $url->to_abs($base), 'http://g', 'right absolute version';
$url = Mojo::URL->new('?y');
is $url->to_abs($base), 'http://a/b/c/d?y', 'right absolute version';
$url = Mojo::URL->new('g?y');
is $url->to_abs($base), 'http://a/b/c/g?y', 'right absolute version';
$url = Mojo::URL->new('g?y/./x');
is $url->to_abs($base), 'http://a/b/c/g?y%2F.%2Fx', 'right absolute version';
$url = Mojo::URL->new('#s');
is $url->to_abs($base), 'http://a/b/c/d?q#s', 'right absolute version';
$url = Mojo::URL->new('g#s');
is $url->to_abs($base), 'http://a/b/c/g#s', 'right absolute version';
$url = Mojo::URL->new('g#s/./x');
is $url->to_abs($base), 'http://a/b/c/g#s/./x', 'right absolute version';
$url = Mojo::URL->new('g?y#s');
is $url->to_abs($base), 'http://a/b/c/g?y#s', 'right absolute version';
$url = Mojo::URL->new('.');
is $url->to_abs($base), 'http://a/b/c', 'right absolute version';
$url = Mojo::URL->new('./');
is $url->to_abs($base), 'http://a/b/c/', 'right absolute version';
$url = Mojo::URL->new('..');
is $url->to_abs($base), 'http://a/b', 'right absolute version';
$url = Mojo::URL->new('../');
is $url->to_abs($base), 'http://a/b/', 'right absolute version';
$url = Mojo::URL->new('../g');
is $url->to_abs($base), 'http://a/b/g', 'right absolute version';
$url = Mojo::URL->new('../..');
is $url->to_abs($base), 'http://a/', 'right absolute version';
$url = Mojo::URL->new('../../');
is $url->to_abs($base), 'http://a/', 'right absolute version';
$url = Mojo::URL->new('../../g');
is $url->to_abs($base), 'http://a/g', 'right absolute version';
