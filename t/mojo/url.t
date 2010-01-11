#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use utf8;

use Test::More tests => 94;

# I don't want you driving around in a car you built yourself.
# You can sit there complaining, or you can knit me some seat belts.
use_ok('Mojo::URL');

# Simple
my $url = Mojo::URL->new('HtTp://Kraih.Com');
is($url->scheme, 'HtTp');
is($url->host,   'Kraih.Com');
is("$url",       'http://kraih.com');

# Advanced
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
is($url->is_abs,   1);
is($url->scheme,   'http');
is($url->userinfo, 'sri:foobar');
is($url->host,     'kraih.com');
is($url->port,     '8080');
is($url->path,     '/test/index.html');
is($url->query,    'monkey=biz&foo=1');
is($url->fragment, '23');
is("$url",
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
$url->path('/index.xml');
is("$url", 'http://sri:foobar@kraih.com:8080/index.xml?monkey=biz&foo=1#23');

# Parameters
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23');
is($url->is_abs,   1);
is($url->scheme,   'http');
is($url->userinfo, 'sri:foobar');
is($url->host,     'kraih.com');
is($url->port,     '8080');
is($url->path,     '');
is($url->query,    '_monkey=biz%3B&_monkey=23');
is_deeply($url->query->to_hash, {_monkey => ['biz;', 23]});
is($url->fragment, '23');
is("$url", 'http://sri:foobar@kraih.com:8080?_monkey=biz%3B&_monkey=23#23');
$url->query(monkey => 'foo');
is("$url", 'http://sri:foobar@kraih.com:8080?monkey=foo#23');

# Query string
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080?_monkeybiz%3B&_monkey;23#23');
is($url->is_abs,   1);
is($url->scheme,   'http');
is($url->userinfo, 'sri:foobar');
is($url->host,     'kraih.com');
is($url->port,     '8080');
is($url->path,     '');
is($url->query,    '_monkeybiz%3B%26_monkey%3B23');
is_deeply($url->query->params, ['_monkeybiz;&_monkey;23', undef]);
is($url->fragment, '23');
is("$url",
    'http://sri:foobar@kraih.com:8080?_monkeybiz%3B%26_monkey%3B23#23');

# Relative
$url = Mojo::URL->new('http://sri:foobar@kraih.com:8080/foo?foo=bar#23');
$url->base->parse('http://sri:foobar@kraih.com:8080/');
is($url->is_abs, 1);
is($url->to_rel, '/foo?foo=bar#23');

# Relative with path
$url = Mojo::URL->new('http://kraih.com/foo/index.html?foo=bar#23');
$url->base->parse('http://kraih.com/foo/');
my $rel = $url->to_rel;
is($rel,         'index.html?foo=bar#23');
is($rel->is_abs, undef);
is($rel->to_abs, 'http://kraih.com/foo/index.html?foo=bar#23');

# Absolute (base without trailing slash)
$url = Mojo::URL->new('/foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar');
is($url->is_abs, undef);
is($url->to_abs, 'http://kraih.com/foo?foo=bar#23');

# Absolute with path
$url = Mojo::URL->new('../foo?foo=bar#23');
$url->base->parse('http://kraih.com/bar/baz/');
is($url->is_abs,         undef);
is($url->to_abs,         'http://kraih.com/bar/baz/../foo?foo=bar#23');
is($url->to_abs->to_rel, '../foo?foo=bar#23');
is($url->to_abs->base,   'http://kraih.com/bar/baz/');

# Real world tests
$url = Mojo::URL->new('http://acme.s3.amazonaws.com'
      . '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb');
is($url->is_abs,   1);
is($url->scheme,   'http');
is($url->userinfo, undef);
is($url->host,     'acme.s3.amazonaws.com');
is($url->port,     undef);
is($url->path,     '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb');
is($url->query,    undef);
is_deeply($url->query->to_hash, {});
is($url->fragment, undef);
is("$url",
        'http://acme.s3.amazonaws.com'
      . '/mojo%2Fg%2B%2B-4%2E2_4%2E2%2E3-2ubuntu7_i386%2Edeb');

# Clone (advanced)
$url = Mojo::URL->new(
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
my $clone = $url->clone;
is($clone->is_abs,   1);
is($clone->scheme,   'http');
is($clone->userinfo, 'sri:foobar');
is($clone->host,     'kraih.com');
is($clone->port,     '8080');
is($clone->path,     '/test/index.html');
is($clone->query,    'monkey=biz&foo=1');
is($clone->fragment, '23');
is("$clone",
    'http://sri:foobar@kraih.com:8080/test/index.html?monkey=biz&foo=1#23');
$clone->path('/index.xml');
is("$clone",
    'http://sri:foobar@kraih.com:8080/index.xml?monkey=biz&foo=1#23');

# Clone (with base)
$url = Mojo::URL->new('/test/index.html');
$url->base->parse('http://127.0.0.1');
is("$url", '/test/index.html');
$clone = $url->clone;
is("$url",                    '/test/index.html');
is($clone->is_abs,            undef);
is($clone->scheme,            undef);
is($clone->host,              undef);
is($clone->base->scheme,      'http');
is($clone->base->host,        '127.0.0.1');
is($clone->path,              '/test/index.html');
is($clone->to_abs->to_string, 'http://127.0.0.1/test/index.html');

# IPv6
$url = Mojo::URL->new('http://[::1]:3000/');
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->host,   '[::1]');
is($url->port,   3000);
is($url->path,   '/');
is("$url",       'http://[::1]:3000/');

# IDNA
$url = Mojo::URL->new('http://bücher.ch:3000/foo');
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->host,   'bücher.ch');
is($url->ihost,  'xn--bcher-kva.ch');
is($url->port,   3000);
is($url->path,   '/foo');
is("$url",       'http://bücher.ch:3000/foo');

# IDNA (snowman)
$url = Mojo::URL->new('http://☃.net/');
is($url->is_abs, 1);
is($url->scheme, 'http');
is($url->host,   '☃.net');
is($url->ihost,  'xn--n3h.net');
is($url->path,   '/');
is("$url",       'http://☃.net/');
