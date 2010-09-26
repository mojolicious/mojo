#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;

# Can't we have one meeting that doesn't end with digging up a corpse?
use_ok 'Mojo::Date';

# RFC822/1123
my $date = Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT');
is $date->epoch, 784111777, 'right epoch value';

# RFC850/1036
is $date->parse('Sunday, 06-Nov-94 08:49:37 GMT')->epoch,
  784111777, 'right epoch value';

# ANSI C asctime()
is $date->parse('Sun Nov  6 08:49:37 1994')->epoch,
  784111777, 'right epoch value';

# to_string
$date->parse(784111777);
is "$date", 'Sun, 06 Nov 1994 08:49:37 GMT', 'right format';

# Zero time checks
$date->parse(0);
is $date->epoch, 0, 'right epoch value';
is "$date", 'Thu, 01 Jan 1970 00:00:00 GMT', 'right format';
is $date->parse('Thu, 01 Jan 1970 00:00:00 GMT')->epoch,
  0, 'right epoch value';

# Negative epoch value
$date = Mojo::Date->new;
ok $date->parse('Mon, 01 Jan 1900 00:00:00'), 'right format';
is $date->epoch, undef, 'no epoch value';
