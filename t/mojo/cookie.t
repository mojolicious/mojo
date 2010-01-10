#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 43;

# What good is money if it can't inspire terror in your fellow man?
use_ok('Mojo::Cookie::Request');
use_ok('Mojo::Cookie::Response');

# Request cookie as string
my $cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
$cookie->value('ba =r');
$cookie->path('/test');
$cookie->version(1);
is("$cookie",                      'foo=ba =r; $Path=/test');
is($cookie->to_string_with_prefix, '$Version=1; foo=ba =r; $Path=/test');

# Empty cookie
$cookie = Mojo::Cookie::Request->new;
my $cookies = $cookie->parse();

# Parse normal request cookie
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=bar; $Path="/test"');
is($cookies->[0]->name,    'foo');
is($cookies->[0]->value,   'bar');
is($cookies->[0]->path,    '/test');
is($cookies->[0]->version, '1');

# Parse quoted request cookie
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b a\" r\"\\"; $Path="/test"');
is($cookies->[0]->name,    'foo');
is($cookies->[0]->value,   'b a" r"\\');
is($cookies->[0]->path,    '/test');
is($cookies->[0]->version, '1');

# Parse multiple cookie request
$cookies = Mojo::Cookie::Request->parse(
    '$Version=1; foo=bar; $Path=/test; baz=la la; $Path=/tset');
is($cookies->[0]->name,    'foo');
is($cookies->[0]->value,   'bar');
is($cookies->[0]->path,    '/test');
is($cookies->[0]->version, '1');
is($cookies->[1]->name,    'baz');
is($cookies->[1]->value,   'la la');
is($cookies->[1]->path,    '/tset');
is($cookies->[1]->version, '1');

# Response cookie as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('ba r');
$cookie->path('/test');
$cookie->version(1);
is("$cookie", 'foo=ba r; Version=1; Path=/test');

# Full response cookie as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('ba r');
$cookie->domain('kraih.com');
$cookie->path('/test');
$cookie->max_age(60);
$cookie->expires(1218092879);
$cookie->port('80 8080');
$cookie->secure(1);
$cookie->httponly(1);
$cookie->comment('lalalala');
$cookie->version(1);
is("$cookie",
        'foo=ba r; Version=1; Domain=kraih.com; Path=/test;'
      . ' Max-Age=60; expires=Thu, 07 Aug 2008 07:07:59 GMT;'
      . ' Port="80 8080"; Secure; HttpOnly; Comment=lalalala');

# Parse response cookie
$cookies = Mojo::Cookie::Response->parse(
        'foo=ba r; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
      . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
      . ' Comment=lalalala');
is($cookies->[0]->name,    'foo');
is($cookies->[0]->value,   'ba r');
is($cookies->[0]->domain,  'kraih.com');
is($cookies->[0]->path,    '/test');
is($cookies->[0]->max_age, 60);
is($cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT');
is($cookies->[0]->port,    '80 8080');
is($cookies->[0]->secure,  '1');
is($cookies->[0]->comment, 'lalalala');
is($cookies->[0]->version, '1');

# Cookie with Max-Age 0 and expires 0
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('bar');
$cookie->path('/');
$cookie->max_age(0);
$cookie->expires(0);
$cookie->version(1);
is("$cookie",
        'foo=bar; Version=1; Path=/; Max-Age=0;'
      . ' expires=Thu, 01 Jan 1970 00:00:00 GMT');

# Parse response cookie with Max-Age 0 and expires 0
$cookies = Mojo::Cookie::Response->parse(
        'foo=bar; Version=1; Domain=kraih.com; Path=/; Max-Age=0;'
      . ' expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; Comment=lalalala');
is($cookies->[0]->name,           'foo');
is($cookies->[0]->value,          'bar');
is($cookies->[0]->domain,         'kraih.com');
is($cookies->[0]->path,           '/');
is($cookies->[0]->max_age,        0);
is($cookies->[0]->expires,        'Thu, 01 Jan 1970 00:00:00 GMT');
is($cookies->[0]->expires->epoch, 0);
is($cookies->[0]->secure,         '1');
is($cookies->[0]->comment,        'lalalala');
is($cookies->[0]->version,        '1');
