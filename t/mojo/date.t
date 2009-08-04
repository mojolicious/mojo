#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 26;

# Can't we have one meeting that doesn't end with digging up a corpse?
use_ok('Mojo::Date');

# RFC822/1123
my $date = Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT');
is($date->epoch, 784111777);

# RFC850/1036
is($date->parse('Sunday, 06-Nov-94 08:49:37 GMT')->epoch, 784111777);

# ANSI C asctime()
is($date->parse('Sun Nov  6 08:49:37 1994')->epoch, 784111777);

# to_http
$date->parse(784111777);
is("$date", 'Sun, 06 Nov 1994 08:49:37 GMT');

# Zero time checks
$date->parse(0);
is($date->epoch, 0);
is("$date",      'Thu, 01 Jan 1970 00:00:00 GMT');
is($date->parse('Thu, 01 Jan 1970 00:00:00 GMT')->epoch, 0);

# Negative epoch value
$date = Mojo::Date->new;
ok($date->parse('Mon, 01 Jan 1900 00:00:00'));
is($date->epoch, undef);

# Hash
$date = Mojo::Date->new(year => 2009);
is($date->epoch, '1230768000');
is("$date",      'Thu, 01 Jan 2009 00:00:00 GMT');
$date = Mojo::Date->new(day => 1, month => 1, year => 2007);
is($date->epoch, '1167609600');
is("$date",      'Mon, 01 Jan 2007 00:00:00 GMT');
$date = Mojo::Date->new(
    day    => 1,
    month  => 1,
    year   => 2007,
    hour   => 0,
    minute => 0,
    second => 1
);
is($date->epoch, '1167609601');
is("$date",      'Mon, 01 Jan 2007 00:00:01 GMT');
$date = Mojo::Date->new(
    day    => 23,
    month  => 12,
    year   => 2007,
    hour   => 22,
    minute => 12,
    second => 0
);
is($date->epoch, '1198447920');
is("$date",      'Sun, 23 Dec 2007 22:12:00 GMT');
my $hash = $date->to_hash;
is($hash->{day},    23);
is($hash->{month},  12);
is($hash->{year},   2007);
is($hash->{hour},   22);
is($hash->{minute}, 12);
is($hash->{second}, 0);
$date = Mojo::Date->new($date->to_hash);
is($date->epoch, '1198447920');
is("$date",      'Sun, 23 Dec 2007 22:12:00 GMT');
