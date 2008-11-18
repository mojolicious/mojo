#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 8;

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
