#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

use Test::More tests => 154;

# I don't want you driving around in a car you built yourself.
# You can sit there complaining, or you can knit me some seat belts.
use_ok 'Mojo::URL';

# Simple
my $url = Mojo::URL->new('HtTp://Kraih.Com');
is $url->scheme, 'HtTp',      'right scheme';
is $url->host,   'Kraih.Com', 'right host';
is "$url", 'http://kraih.com', 'right format';

# Advanced
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
is $url->is_abs,   1,                  'is absolute';
is $url->scheme,   'http',             'right scheme';
is $url->userinfo, 'sri:foobar',       'right userinfo';
is $url->host,     'kraih.com',        'right host';
is $url->port,     '8080',             'right port';
is $url->path,     '/test/index.html', 'right path';
is $url->query,    'monkey=biz&foo=1', 'right query';
is $url->fragment, '23',               'right fragment';
is "$url",
  'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23',
  'right format';
$url->path('/index.xml');
is "$url", 'http://sri:foobar@kraih.com:8080/index.xml?monkey=biz&foo=1#23',
  'right format';

# Parameters
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23');
is $url->is_abs,   1,                           'is absolute';
is $url->scheme,   'http',                      'right scheme';
is $url->userinfo, 'sri:foobar',                'right userinfo';
is $url->host,     'kraih.com',                 'right host';
is $url->port,     '8080',                      'right port';
is $url->path,     '',                          'no path';
is $url->query,    '_monkey=biz%3B&_monkey=23', 'right query';
is_deeply $url->query->to_hash, {_monkey => ['biz;', 23]}, 'right structure';
is $url->fragment, '23', 'right fragment';
is "$url", 'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23',
  'right format';
$url->query(monkey => 'foo');
is "$url", 'http://sri:foobar@kraih.com:8080?monkey=foo#23', 'right format';
$url->query({foo => 'bar'});
is "$url", 'http://sri:foobar@kraih.com:8080?monkey=foo&foo=bar#23',
  'right format';
$url->query('foo');
is "$url", 'http://sri:foobar@kraih.com:8080?foo#23', 'right format';
$url->query('foo=bar');
is "$url", 'http://sri:foobar@kraih.com:8080?foo%3Dbar#23', 'right format';

# Query string
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080?_monkeybiz%3B&_monkey;23#23');
is $url->is_abs,   1,                              'is absolute';
is $url->scheme,   'http',                         'right scheme';
is $url->userinfo, 'sri:foobar',                   'right userinfo';
is $url->host,     'kraih.com',                    'right host';
is $url->port,     '8080',                         'right port';
is $url->path,     '',                             'no path';
is $url->query,    '_monkeybiz%3B%26_monkey%3B23', 'right query';
is_deeply $url->query->params, ['_monkeybiz;&_monkey;23', undef],
  'right structure';
is $url->fragment, '23', 'right fragment';
is "$url", 'http://sri:foobar@kraih.com:8080?_monkeybiz%3B%26_monkey%3B23#23',
  'right format';

# Relative
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/');
is $url->is_abs, 1, 'is absolute';
is $url->to_rel, '/foo?foo=bar#23', 'right relative version';

# Relative with path
$url = Mojo::URL->new('http://kraih.com/foo/index.html?foo=bar#23');
$url->base->parse('http://kraih.com/foo/');
my $rel = $url->to_rel;
is $rel, 'index.html?foo=bar#23', 'right format';
is $rel->is_abs, undef, 'not absolute';
is $rel->to_abs, 'http://kraih.com/foo/index.html?foo=bar#23',
  'right absolute version';

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
is "$url", 'http://kraih.com/baz?foo=bar#23', 'right canonicalized path';

# Absolute (base without trailing slash)
$url = Mojo::URL->new('/foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar');
is $url->is_abs, undef, 'not absolute';
is $url->to_abs, 'http://kraih.com/foo?foo=bar#23', 'right absolute version';

# Absolute with path
$url = Mojo::URL->new('../foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar/baz/');
is $url->is_abs, undef, 'not absolute';
is $url->to_abs, 'http://kraih.com/bar/baz/../foo?foo=bar#23',
  'right absolute version';
is $url->to_abs->to_rel, '../foo?foo=bar#23', 'right relative version';
is $url->to_abs->base, 'http://kraih.com/bar/baz/', 'right base';

# Real world tests
$url = Mojo::URL->new('http://acme.s3.amazonaws.com'
      . '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb');
is $url->is_abs,   1,                                         'is absolute';
is $url->scheme,   'http',                                    'right scheme';
is $url->userinfo, undef,                                     'no userinfo';
is $url->host,     'acme.s3.amazonaws.com',                   'right host';
is $url->port,     undef,                                     'no port';
is $url->path,     '/mojo%2Fg++-4.2_4.2.3-2ubuntu7_i386.deb', 'right path';
ok !$url->query, 'no query';
is_deeply $url->query->to_hash, {}, 'right structure';
is $url->fragment, undef, 'no fragment';
is "$url",
  'http://acme.s3.amazonaws.com/mojo%2Fg++-4.2_4.2.3-2ubuntu7_i386.deb',
  'right format';

# Clone (advanced)
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
my $clone = $url->clone;
is $clone->is_abs,   1,                  'is absolute';
is $clone->scheme,   'http',             'right scheme';
is $clone->userinfo, 'sri:foobar',       'right userinfo';
is $clone->host,     'kraih.com',        'right host';
is $clone->port,     '8080',             'right port';
is $clone->path,     '/test/index.html', 'right path';
is $clone->query,    'monkey=biz&foo=1', 'right query';
is $clone->fragment, '23',               'right fragment';
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
is $clone->is_abs, undef, 'not absolute';
is $clone->scheme, undef, 'no scheme';
is $clone->host,   undef, 'no host';
is $clone->base->scheme, 'http',      'right base scheme';
is $clone->base->host,   '127.0.0.1', 'right base host';
is $clone->path, '/test/index.html', 'right path';
is $clone->to_abs->to_string, 'http://127.0.0.1/test/index.html',
  'right absolute version';

# IPv6
$url = Mojo::URL->new('http://[::1]:3000/');
is $url->is_abs, 1,       'is absolute';
is $url->scheme, 'http',  'right scheme';
is $url->host,   '[::1]', 'right host';
is $url->port,   3000,    'right port';
is $url->path,   '/',     'right path';
is "$url", 'http://[::1]:3000/', 'right format';

# IDNA
$url = Mojo::URL->new('http://bücher.ch:3000/foo');
is $url->is_abs, 1,                  'is absolute';
is $url->scheme, 'http',             'right scheme';
is $url->host,   'bücher.ch',       'right host';
is $url->ihost,  'xn--bcher-kva.ch', 'right internationalized host';
is $url->port,   3000,               'right port';
is $url->path,   '/foo',             'right path';
is "$url", 'http://xn--bcher-kva.ch:3000/foo', 'right format';

# IDNA (snowman)
$url = Mojo::URL->new('http://☃.net/');
is $url->is_abs, 1,             'is absolute';
is $url->scheme, 'http',        'right scheme';
is $url->host,   '☃.net',     'right host';
is $url->ihost,  'xn--n3h.net', 'right internationalized host';
is $url->path,   '/',           'right path';
is "$url", 'http://xn--n3h.net/', 'right format';

# Already absolute
$url = Mojo::URL->new('http://foo.com/');
is $url->to_abs, 'http://foo.com/', 'right absolute version';

# Already relative
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/');
my $url2 = $url->to_rel;
is $url->to_rel, '/foo?foo=bar#23', 'right relative version';

# IRI
$url =
  Mojo::URL->new('http://sharifulin.ru/привет/?q=шарифулин');
is $url->path->parts->[0], 'привет', 'right path part';
is $url->path, '/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82/', 'right path';
is $url->query, 'q=%D1%88%D0%B0%D1%80%D0%B8%D1%84%D1%83%D0%BB%D0%B8%D0%BD',
  'right query';
is $url->query->param('q'), 'шарифулин', 'right query value';

# IRI/IDNA
$url = Mojo::URL->new(
    'http://☃.net/привет/привет/?привет=шарифулин'
);
is $url->is_abs, 1,             'is absolute';
is $url->scheme, 'http',        'right scheme';
is $url->host,   '☃.net',     'right host';
is $url->ihost,  'xn--n3h.net', 'right internationalized host';
is $url->path, '/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82'
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
is $url->is_abs, 1;
is $url->to_rel, '/foo//bar/23/';
$url = Mojo::URL->new('http://kraih.com//foo//bar/23/');
$url->base->parse('http://kraih.com/');
is $url->is_abs, 1;
is $url->to_rel, '/foo//bar/23/';
$url = Mojo::URL->new('http://kraih.com/foo///bar/23/');
$url->base->parse('http://kraih.com/');
is $url->is_abs, 1;
is $url->to_rel, '/foo///bar/23/';

# Check host for IPv4 and IPv6 addresses
$url = Mojo::URL->new('http://mojolicio.us');
is $url->host,    'mojolicio.us', 'right host';
is $url->is_ipv4, undef,          'not an IPv4 address';
is $url->is_ipv6, undef,          'not an IPv6 address';
$url = Mojo::URL->new('http://[::1]');
is $url->host,    '[::1]', 'right host';
is $url->is_ipv4, undef,   'not an IPv4 address';
is $url->is_ipv6, 1,       'is an IPv6 address';
$url = Mojo::URL->new('http://127.0.0.1');
is $url->host,    '127.0.0.1', 'right host';
is $url->is_ipv4, 1,           'is an IPv4 address';
is $url->is_ipv6, undef,       'not an IPv6 address';
$url = Mojo::URL->new('http://0::127.0.0.1');
is $url->host,    '0::127.0.0.1', 'right host';
is $url->is_ipv4, 1,              'is an IPv4 address';
is $url->is_ipv6, 1,              'is an IPv6 address';
$url = Mojo::URL->new('http://[0::127.0.0.1]');
is $url->host,    '[0::127.0.0.1]', 'right host';
is $url->is_ipv4, 1,                'is an IPv4 address';
is $url->is_ipv6, 1,                'is an IPv6 address';
$url = Mojo::URL->new('http://mojolicio.us:3000');
is $url->host,    'mojolicio.us', 'right host';
is $url->is_ipv4, undef,          'not an IPv4 address';
is $url->is_ipv6, undef,          'not an IPv6 address';
$url = Mojo::URL->new('http://[::1]:3000');
is $url->host,    '[::1]', 'right host';
is $url->is_ipv4, undef,   'not an IPv4 address';
is $url->is_ipv6, 1,       'is an IPv6 address';
$url = Mojo::URL->new('http://127.0.0.1:3000');
is $url->host,    '127.0.0.1', 'right host';
is $url->is_ipv4, 1,           'is an IPv4 address';
is $url->is_ipv6, undef,       'not an IPv6 address';
$url = Mojo::URL->new('http://0::127.0.0.1:3000');
is $url->host,    '0::127.0.0.1', 'right host';
is $url->is_ipv4, 1,              'is an IPv4 address';
is $url->is_ipv6, 1,              'is an IPv6 address';
$url = Mojo::URL->new('http://[0::127.0.0.1]:3000');
is $url->host,    '[0::127.0.0.1]', 'right host';
is $url->is_ipv4, 1,                'is an IPv4 address';
is $url->is_ipv6, 1,                'is an IPv6 address';
