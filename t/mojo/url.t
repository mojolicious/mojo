use Mojo::Base -strict;

use Test::More;
use Mojo::URL;

# Simple
my $url = Mojo::URL->new('HtTp://Example.Com');
is $url->scheme,    'HtTp',        'right scheme';
is $url->protocol,  'http',        'right protocol';
is $url->host,      'Example.Com', 'right host';
is $url->ihost,     'example.com', 'right internationalized host';
is $url->authority, 'example.com', 'right authority';
is "$url", 'http://example.com', 'right format';

# Advanced
$url = Mojo::URL->new(
  'https://sri:foobar@example.com:8080/x/index.html?monkey=biz&foo=1#/!%?@3');
ok $url->is_abs,     'is absolute';
is $url->scheme,     'https', 'right scheme';
is $url->protocol,   'https', 'right protocol';
is $url->userinfo,   'sri:foobar', 'right userinfo';
is $url->host,       'example.com', 'right host';
is $url->port,       '8080', 'right port';
is $url->authority,  'sri:foobar@example.com:8080', 'right authority';
is $url->path,       '/x/index.html', 'right path';
is $url->query,      'monkey=biz&foo=1', 'right query';
is $url->path_query, '/x/index.html?monkey=biz&foo=1', 'right path and query';
is $url->fragment,   '/!%?@3', 'right fragment';
is "$url",
  'https://sri:foobar@example.com:8080/x/index.html?monkey=biz&foo=1#/!%?@3',
  'right format';
$url->path('/index.xml');
is "$url",
  'https://sri:foobar@example.com:8080/index.xml?monkey=biz&foo=1#/!%?@3',
  'right format';

# Advanced userinfo and fragment roundtrip
$url = Mojo::URL->new(
  'ws://AZaz09-._~!$&\'()*+,;=:@localhost#AZaz09-._~!$&\'()*+,;=%:@/?');
is $url->scheme,   'ws',                          'right scheme';
is $url->userinfo, 'AZaz09-._~!$&\'()*+,;=:',     'right userinfo';
is $url->host,     'localhost',                   'right host';
is $url->fragment, 'AZaz09-._~!$&\'()*+,;=%:@/?', 'right fragment';
is "$url",
  'ws://AZaz09-._~!$&\'()*+,;=:@localhost#AZaz09-._~!$&\'()*+,;=%:@/?',
  'right format';

# Parameters
$url = Mojo::URL->new(
  'http://sri:foobar@example.com:8080?_monkey=biz%3B&_monkey=23#23');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, 'sri:foobar', 'right userinfo';
is $url->host,     'example.com', 'right host';
is $url->port,     '8080', 'right port';
is $url->path,     '', 'no path';
is $url->query,    '_monkey=biz%3B&_monkey=23', 'right query';
is_deeply $url->query->to_hash, {_monkey => ['biz;', 23]}, 'right structure';
is $url->fragment, '23', 'right fragment';
is "$url", 'http://sri:foobar@example.com:8080?_monkey=biz%3B&_monkey=23#23',
  'right format';
$url->query(monkey => 'foo');
is "$url", 'http://sri:foobar@example.com:8080?monkey=foo#23', 'right format';
$url->query([monkey => 'bar']);
is "$url", 'http://sri:foobar@example.com:8080?monkey=bar#23', 'right format';
$url->query({foo => 'bar'});
is "$url", 'http://sri:foobar@example.com:8080?monkey=bar&foo=bar#23',
  'right format';
$url->query('foo');
is "$url", 'http://sri:foobar@example.com:8080?foo#23', 'right format';
$url->query('foo=bar');
is "$url", 'http://sri:foobar@example.com:8080?foo=bar#23', 'right format';
$url->query([foo => undef]);
is "$url", 'http://sri:foobar@example.com:8080#23', 'right format';
$url->query([foo => 23, bar => 24, baz => 25]);
is "$url", 'http://sri:foobar@example.com:8080?foo=23&bar=24&baz=25#23',
  'right format';
$url->query([foo => 26, bar => undef, baz => undef]);
is "$url", 'http://sri:foobar@example.com:8080?foo=26#23', 'right format';
$url->query(c => 3);
is "$url", 'http://sri:foobar@example.com:8080?c=3#23', 'right format';
$url->query(Mojo::Parameters->new('a=1&b=2'));
is_deeply $url->query->to_hash, {a => 1, b => 2}, 'right structure';
is "$url", 'http://sri:foobar@example.com:8080?a=1&b=2#23', 'right format';
$url->query(Mojo::Parameters->new('%E5=%E4')->charset(undef));
is_deeply $url->query->to_hash, {"\xe5" => "\xe4"}, 'right structure';
is "$url", 'http://sri:foobar@example.com:8080?%E5=%E4#23', 'right format';

# Query string
$url = Mojo::URL->new(
  'wss://sri:foobar@example.com:8080?_monkeybiz%3B&_monkey;23#23');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'wss', 'right scheme';
is $url->userinfo, 'sri:foobar', 'right userinfo';
is $url->host,     'example.com', 'right host';
is $url->port,     '8080', 'right port';
is $url->path,     '', 'no path';
is $url->query,    '_monkeybiz%3B&_monkey;23', 'right query';
is_deeply $url->query->params, ['_monkeybiz;', '', '_monkey;23', ''],
  'right structure';
is $url->query, '_monkeybiz%3B=&_monkey%3B23=', 'right query';
is $url->fragment, '23', 'right fragment';
is "$url", 'wss://sri:foobar@example.com:8080?_monkeybiz%3B=&_monkey%3B23=#23',
  'right format';
$url = Mojo::URL->new('https://example.com/0?0#0');
ok $url->is_abs,    'is absolute';
is $url->scheme,    'https', 'right scheme';
is $url->userinfo,  undef, 'no userinfo';
is $url->host,      'example.com', 'right host';
is $url->port,      undef, 'no port';
is $url->host_port, 'example.com', 'right host and port';
is $url->path,      '/0', 'no path';
is $url->query,     '0', 'right query';
is $url->fragment,  '0', 'right fragment';
is "$url", 'https://example.com/0?0#0', 'right format';

# No authority
$url = Mojo::URL->new('DATA:image/png;base64,helloworld123');
is $url->scheme,    'DATA',                           'right scheme';
is $url->protocol,  'data',                           'right protocol';
is $url->userinfo,  undef,                            'no userinfo';
is $url->host,      undef,                            'no host';
is $url->port,      undef,                            'no port';
is $url->authority, undef,                            'no authority';
is $url->path,      'image/png;base64,helloworld123', 'right path';
is $url->query,     '',                               'no query';
is $url->fragment,  undef,                            'no fragment';
is "$url", 'data:image/png;base64,helloworld123', 'right format';
$url = $url->clone;
is $url->scheme,    'DATA',                           'right scheme';
is $url->protocol,  'data',                           'right protocol';
is $url->userinfo,  undef,                            'no userinfo';
is $url->host,      undef,                            'no host';
is $url->port,      undef,                            'no port';
is $url->authority, undef,                            'no authority';
is $url->path,      'image/png;base64,helloworld123', 'right path';
is $url->query,     '',                               'no query';
is $url->fragment,  undef,                            'no fragment';
is "$url", 'data:image/png;base64,helloworld123', 'right format';
$url = Mojo::URL->new->parse('mailto:sri@example.com');
is $url->scheme,   'mailto',          'right scheme';
is $url->protocol, 'mailto',          'right protocol';
is $url->path,     'sri@example.com', 'right path';
is "$url", 'mailto:sri@example.com', 'right format';
$url = Mojo::URL->new->parse('foo:/test/123?foo=bar#baz');
is $url->scheme,   'foo',       'right scheme';
is $url->protocol, 'foo',       'right protocol';
is $url->path,     '/test/123', 'right path';
is $url->query,    'foo=bar',   'right query';
is $url->fragment, 'baz',       'right fragment';
is "$url", 'foo:/test/123?foo=bar#baz', 'right format';
is $url->scheme('Bar')->to_string, 'bar:/test/123?foo=bar#baz', 'right format';
is $url->scheme,    'Bar',       'right scheme';
is $url->protocol,  'bar',       'right protocol';
is $url->host,      undef,       'no host';
is $url->authority, undef,       'no authority';
is $url->path,      '/test/123', 'right path';
is $url->query,     'foo=bar',   'right query';
is $url->fragment,  'baz',       'right fragment';
is "$url", 'bar:/test/123?foo=bar#baz', 'right format';
$url = Mojo::URL->new->parse('file:///foo/bar');
is $url->scheme,   'file',     'right scheme';
is $url->protocol, 'file',     'right protocol';
is $url->path,     '/foo/bar', 'right path';
is "$url", 'file:///foo/bar', 'right format';
$url = $url->clone;
is $url->scheme,   'file',     'right scheme';
is $url->protocol, 'file',     'right protocol';
is $url->path,     '/foo/bar', 'right path';
is "$url", 'file:///foo/bar', 'right format';
$url = Mojo::URL->new->parse('foo:0');
is $url->scheme,   'foo', 'right scheme';
is $url->protocol, 'foo', 'right protocol';
is $url->path,     '0',   'right path';
is "$url", 'foo:0', 'right format';

# Relative
$url = Mojo::URL->new('foo?foo=bar#23');
is $url->path_query, 'foo?foo=bar', 'right path and query';
ok !$url->is_abs, 'is not absolute';
is "$url", 'foo?foo=bar#23', 'right relative version';
$url = Mojo::URL->new('/foo?foo=bar#23');
is $url->path_query, '/foo?foo=bar', 'right path and query';
ok !$url->is_abs, 'is not absolute';
is "$url", '/foo?foo=bar#23', 'right relative version';

# Relative without scheme
$url = Mojo::URL->new('//localhost/23/');
ok !$url->is_abs, 'is not absolute';
is $url->scheme,   undef,       'no scheme';
is $url->protocol, '',          'no protocol';
is $url->host,     'localhost', 'right host';
is $url->path,     '/23/',      'right path';
is "$url", '//localhost/23/', 'right relative version';
is $url->to_abs(Mojo::URL->new('http://')), 'http://localhost/23/',
  'right absolute version';
is $url->to_abs(Mojo::URL->new('https://')), 'https://localhost/23/',
  'right absolute version';
is $url->to_abs(Mojo::URL->new('http://mojolicio.us')),
  'http://localhost/23/', 'right absolute version';
is $url->to_abs(Mojo::URL->new('http://mojolicio.us:8080')),
  'http://localhost/23/', 'right absolute version';
$url = Mojo::URL->new('///bar/23/');
ok !$url->is_abs, 'is not absolute';
is $url->host, '',         'no host';
is $url->path, '/bar/23/', 'right path';
is "$url", '///bar/23/', 'right relative version';
$url = Mojo::URL->new('////bar//23/');
ok !$url->is_abs, 'is not absolute';
is $url->host, '',           'no host';
is $url->path, '//bar//23/', 'right path';
is "$url", '////bar//23/', 'right relative version';

# Relative path
$url = Mojo::URL->new('http://example.com/foo/?foo=bar#23');
$url->path('bar');
is "$url", 'http://example.com/foo/bar?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://example.com?foo=bar#23');
$url->path('bar');
is "$url", 'http://example.com/bar?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://example.com/foo?foo=bar#23');
$url->path('bar');
is "$url", 'http://example.com/bar?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://example.com/foo/bar?foo=bar#23');
$url->path('yada/baz');
is "$url", 'http://example.com/foo/yada/baz?foo=bar#23', 'right path';
$url = Mojo::URL->new('http://example.com/foo/bar?foo=bar#23');
$url->path('../baz');
is "$url", 'http://example.com/foo/../baz?foo=bar#23', 'right path';
$url->path->canonicalize;
is "$url", 'http://example.com/baz?foo=bar#23', 'right absolute path';

# Absolute (base without trailing slash)
$url = Mojo::URL->new('/foo?foo=bar#23');
$url->base->parse('http://example.com/bar');
ok !$url->is_abs, 'not absolute';
is $url->to_abs, 'http://example.com/foo?foo=bar#23', 'right absolute version';
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
$url->base->parse('http://example.com/bar/baz/');
ok !$url->is_abs, 'not absolute';
is $url->to_abs, 'http://example.com/bar/foo?foo=bar#23',
  'right absolute version';
is $url->to_abs->base, 'http://example.com/bar/baz/', 'right base';

# Clone (advanced)
$url = Mojo::URL->new(
  'ws://sri:foobar@example.com:8080/test/index.html?monkey=biz&foo=1#23');
my $clone = $url->clone;
ok $clone->is_abs,   'is absolute';
is $clone->scheme,   'ws', 'right scheme';
is $clone->userinfo, 'sri:foobar', 'right userinfo';
is $clone->host,     'example.com', 'right host';
is $clone->port,     '8080', 'right port';
is $clone->path,     '/test/index.html', 'right path';
is $clone->query,    'monkey=biz&foo=1', 'right query';
is $clone->fragment, '23', 'right fragment';
is "$clone",
  'ws://sri:foobar@example.com:8080/test/index.html?monkey=biz&foo=1#23',
  'right format';
$clone->path('/index.xml');
is "$clone", 'ws://sri:foobar@example.com:8080/index.xml?monkey=biz&foo=1#23',
  'right format';

# Clone (with base)
$url = Mojo::URL->new('/test/index.html');
$url->base->parse('http://127.0.0.1');
is "$url", '/test/index.html', 'right format';
$clone = $url->clone;
is "$url", '/test/index.html', 'right format';
ok !$clone->is_abs, 'not absolute';
is $clone->scheme, undef, 'no scheme';
is $clone->host,   undef, 'no host';
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
is $clone->host,   undef, 'no host';
is $clone->base->scheme, 'http',      'right base scheme';
is $clone->base->host,   '127.0.0.1', 'right base host';
is $clone->path, 'test/index.html', 'right path';
is $clone->to_abs->to_string, 'http://127.0.0.1/foo/test/index.html',
  'right absolute version';

# IPv6
$url = Mojo::URL->new('wss://[::1]:3000/');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'wss', 'right scheme';
is $url->host,   '[::1]', 'right host';
is $url->port,   3000, 'right port';
is $url->path,   '/', 'right path';
is "$url", 'wss://[::1]:3000/', 'right format';

# IDNA
$url = Mojo::URL->new('http://bücher.ch:3000/foo');
ok $url->is_abs,     'is absolute';
is $url->scheme,     'http', 'right scheme';
is $url->host,       'bücher.ch', 'right host';
is $url->ihost,      'xn--bcher-kva.ch', 'right internationalized host';
is $url->port,       3000, 'right port';
is $url->host_port,  'xn--bcher-kva.ch:3000', 'right host and port';
is $url->path,       '/foo', 'right path';
is $url->path_query, '/foo', 'right path and query';
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

# IDNA (escaped userinfo and host)
$url = Mojo::URL->new('https://%E2%99%A5:%E2%99%A5@kr%E4ih.com:3000');
is $url->userinfo, '♥:♥',          'right userinfo';
is $url->host,     "kr\xe4ih.com",     'right host';
is $url->ihost,    'xn--krih-moa.com', 'right internationalized host';
is $url->port,     3000,               'right port';
is "$url", 'https://%E2%99%A5:%E2%99%A5@xn--krih-moa.com:3000', 'right format';

# IDNA (snowman)
$url = Mojo::URL->new('http://☃:☃@☃.net/☃?☃#☃');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, '☃:☃', 'right userinfo';
is $url->host,     '☃.net', 'right host';
is $url->ihost,    'xn--n3h.net', 'right internationalized host';
is $url->path,     '/%E2%98%83', 'right path';
is $url->query,    '%E2%98%83', 'right query';
is $url->fragment, '☃', 'right fragment';
is "$url",
  'http://%E2%98%83:%E2%98%83@xn--n3h.net/%E2%98%83?%E2%98%83#%E2%98%83',
  'right format';

# IRI/IDNA
$url = Mojo::URL->new('http://☃.net/♥/?q=♥☃');
is $url->path->parts->[0], '♥', 'right path part';
is $url->path,  '/%E2%99%A5/',          'right path';
is $url->query, 'q=%E2%99%A5%E2%98%83', 'right query';
is $url->query->param('q'), '♥☃', 'right query value';
$url = Mojo::URL->new('http://☃.Net/♥/♥/?♥=☃');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   '☃.Net', 'right host';
is $url->ihost,  'xn--n3h.net', 'right internationalized host';
is $url->path,   '/%E2%99%A5/%E2%99%A5/', 'right path';
is_deeply $url->path->parts, ['♥', '♥'], 'right structure';
is $url->query->param('♥'), '☃', 'right query value';
is "$url", 'http://xn--n3h.net/%E2%99%A5/%E2%99%A5/?%E2%99%A5=%E2%98%83',
  'right format';
$url = Mojo::URL->new(
  'http://xn--n3h.net/%E2%99%A5/%E2%99%A5/?%E2%99%A5=%E2%98%83');
ok $url->is_abs, 'is absolute';
is $url->scheme, 'http', 'right scheme';
is $url->host,   'xn--n3h.net', 'right host';
is $url->ihost,  'xn--n3h.net', 'right internationalized host';
is $url->path,   '/%E2%99%A5/%E2%99%A5/', 'right path';
is_deeply $url->path->parts, ['♥', '♥'], 'right structure';
is $url->query->param('♥'), '☃', 'right query value';
is "$url", 'http://xn--n3h.net/%E2%99%A5/%E2%99%A5/?%E2%99%A5=%E2%98%83',
  'right format';

# Already absolute
$url = Mojo::URL->new('http://foo.com/');
is $url->to_abs, 'http://foo.com/', 'right absolute version';

# "0"
$url = Mojo::URL->new('http://0@foo.com#0');
is $url->scheme,   'http',    'right scheme';
is $url->userinfo, '0',       'right userinfo';
is $url->host,     'foo.com', 'right host';
is $url->fragment, '0',       'right fragment';
is "$url", 'http://0@foo.com#0', 'right format';

# Empty path elements
$url = Mojo::URL->new('http://example.com/foo//bar/23/');
ok $url->is_abs, 'is absolute';
is $url->path, '/foo//bar/23/', 'right path';
is "$url", 'http://example.com/foo//bar/23/', 'right format';
$url = Mojo::URL->new('http://example.com//foo//bar/23/');
ok $url->is_abs, 'is absolute';
is $url->path, '//foo//bar/23/', 'right path';
is "$url", 'http://example.com//foo//bar/23/', 'right format';
$url = Mojo::URL->new('http://example.com/foo///bar/23/');
ok $url->is_abs, 'is absolute';
is $url->path, '/foo///bar/23/', 'right path';
is "$url", 'http://example.com/foo///bar/23/', 'right format';

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
is $url->query,    '',                                         'no query';
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
is $url->query,    '',                                         'no query';
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
is $url->query,    '',                                         'no query';
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
is $url->query,    '',                                         'no query';
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

# Heavily escaped path and empty fragment
$url = Mojo::URL->new(
  'http://example.com/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb#');
ok $url->is_abs,   'is absolute';
is $url->scheme,   'http', 'right scheme';
is $url->userinfo, undef, 'no userinfo';
is $url->host,     'example.com', 'right host';
is $url->port,     undef, 'no port';
is $url->path,     '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb',
  'right path';
is $url->query,    '', 'no query';
is $url->fragment, '', 'right fragment';
is "$url",
  'http://example.com/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb#',
  'right format';
$url->path->canonicalize;
is "$url", 'http://example.com/mojo/g++-4.2_4.2.3-2ubuntu7_i386.deb#',
  'right format';

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

# No charset
$url = Mojo::URL->new;
$url->path->charset(undef);
$url->query->charset(undef);
$url->parse('HTTP://FOO.BAR/%E4/?%E5=%E4');
is $url->scheme,   'HTTP',    'right scheme';
is $url->protocol, 'http',    'right protocol';
is $url->host,     'FOO.BAR', 'right host';
is $url->ihost,    'foo.bar', 'right internationalized host';
is $url->path,     '/%E4/',   'right path';
is_deeply $url->path->parts, ["\xe4"], 'right structure';
ok $url->path->leading_slash,  'has leading slash';
ok $url->path->trailing_slash, 'has trailing slash';
is $url->query, '%E5=%E4', 'right query';
is $url->query->param("\xe5"), "\xe4", 'right value';
is "$url", 'http://foo.bar/%E4/?%E5=%E4', 'right format';

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
is $url->to_abs($base), 'http://a/b/c/g?y/./x', 'right absolute version';
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

done_testing();
