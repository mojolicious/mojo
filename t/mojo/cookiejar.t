#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 24;

# Hello, my name is Mr. Burns. I believe you have a letter for me.
# Okay Mr. Burns, what’s your first name.
# I don’t know.
use_ok('Mojo::CookieJar');
use_ok('Mojo::Cookie::Response');
use_ok('Mojo::URL');

my $jar = Mojo::CookieJar->new;

# Session cookie
$jar->add(
    Mojo::Cookie::Response->new(
        domain => 'kraih.com',
        path   => '/foo',
        name   => 'foo',
        value  => 'bar'
    )
);
my @cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is($cookies[0]->name,  'foo');
is($cookies[0]->value, 'bar');
is($cookies[1],        undef);

# Huge cookie
$jar->add(
    Mojo::Cookie::Response->new(
        domain => 'kraih.com',
        path   => '/foo',
        name   => 'huge',
        value  => 'foo' x 4096
    )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is($cookies[0]->name,  'foo');
is($cookies[0]->value, 'bar');
is($cookies[1],        undef);

# Expired cookie
my $expired = Mojo::Cookie::Response->new(
    domain => 'labs.kraih.com',
    path   => '/',
    name   => 'baz',
    value  => '23'
);
$expired->expires(time - 1);
$jar->add($expired);
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/foo'));
is($cookies[0]->name,  'foo');
is($cookies[0]->value, 'bar');
is($cookies[1],        undef);

# Multiple cookies
$jar->add(
    Mojo::Cookie::Response->new(
        domain  => 'labs.kraih.com',
        path    => '/',
        name    => 'baz',
        value   => '23',
        max_age => 60
    )
);
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/foo'));
is($cookies[0]->name,  'baz');
is($cookies[0]->value, '23');
is($cookies[1]->name,  'foo');
is($cookies[1]->value, 'bar');
is($cookies[2],        undef);

# Multiple cookies with leading dot
$jar->add(
    Mojo::Cookie::Response->new(
        domain => '.kraih.com',
        path   => '/',
        name   => 'this',
        value  => 'that'
    )
);
@cookies = $jar->find(Mojo::URL->new('http://labs.kraih.com/fo'));
is($cookies[0]->name,  'baz');
is($cookies[0]->value, '23');
is($cookies[1]->name,  'this');
is($cookies[1]->value, 'that');
is($cookies[2],        undef);

# Replace cookie
$jar = Mojo::CookieJar->new;
$jar->add(
    Mojo::Cookie::Response->new(
        domain => 'kraih.com',
        path   => '/foo',
        name   => 'foo',
        value  => 'bar1'
    )
);
$jar->add(
    Mojo::Cookie::Response->new(
        domain => 'kraih.com',
        path   => '/foo',
        name   => 'foo',
        value  => 'bar2'
    )
);
@cookies = $jar->find(Mojo::URL->new('http://kraih.com/foo'));
is($cookies[0]->value, 'bar2');
is($cookies[1],        undef);
