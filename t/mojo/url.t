#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 56;

# I don't want you driving around in a car you built yourself.
# You can sit there complaining, or you can knit me some seat belts.
use_ok('Mojo::URL');

# Simple
my $url = Mojo::URL->new('HtTp://Kraih.Com');
is($url->scheme, 'HtTp');
is($url->host, 'Kraih.Com');
is("$url", 'http://kraih.com');

# Advanced
$url = Mojo::URL->new(
  'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23'
);
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->userinfo, 'sri:foobar');
is($url->user, 'sri');
is($url->password, 'foobar');
is($url->host, 'kraih.com');
is($url->port, '8080');
is($url->path, '/test/index.html');
is($url->query, 'monkey=biz&foo=1');
is($url->fragment, '23');
is(
    "$url",
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23'
);

# Parameters
$url = Mojo::URL->new(
  'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23'
);
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->userinfo, 'sri:foobar');
is($url->host, 'kraih.com');
is($url->port, '8080');
is($url->path, '');
is($url->query, '_monkey=biz%3B&_monkey=23');
is_deeply($url->query->to_hash, {_monkey => ['biz;', 23]});
is($url->fragment, '23');
is("$url", 'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23');

# Query string
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080?_monkeybiz%3B&_monkey;23#23'
);
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->userinfo, 'sri:foobar');
is($url->host, 'kraih.com');
is($url->port, '8080');
is($url->path, '');
is($url->query, '_monkeybiz%3B&_monkey;23');
is_deeply($url->query->params, ['_monkeybiz%3B&_monkey;23', undef]);
is($url->fragment, '23');
is("$url", 'http://sri:foobar@kraih.com:8080?_monkeybiz%3B&_monkey;23#23');

# Relative
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/');
is($url->is_abs, 1);
is($url->to_rel, '/foo?foo=bar#23');

# Relative with path
$url = Mojo::URL->new('http://kraih.com/foo/index.html?foo=bar#23');
$url->base->parse('http://kraih.com/foo/');
my $rel = $url->to_rel;
is($rel, 'index.html?foo=bar#23');
is($rel->is_abs, 0);
is($rel->to_abs, 'http://kraih.com/foo/index.html?foo=bar#23');

# Absolute (base without trailing slash)
$url = Mojo::URL->new('/foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar');
is($url->is_abs, 0);
is($url->to_abs, 'http://kraih.com/foo?foo=bar#23');

# Absolute with path
$url = Mojo::URL->new('../foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar/baz/');
is($url->is_abs, 0);
is($url->to_abs, 'http://kraih.com/bar/baz/../foo?foo=bar#23');
is($url->to_abs->to_rel, '../foo?foo=bar#23');
is($url->to_abs->base, 'http://kraih.com/bar/baz/');

# Real world test
$url = Mojo::URL->new(
    'http://acme.s3.amazonaws.com'
  . '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb'
);
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->userinfo, undef);
is($url->host, 'acme.s3.amazonaws.com');
is($url->port, undef);
is($url->path, '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb');
is($url->query, undef);
is_deeply($url->query->to_hash, {});
is($url->fragment, undef);
is("$url",
      'http://acme.s3.amazonaws.com'
    . '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb'
);