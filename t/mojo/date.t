#!/usr/bin/env perl

use Mojo::Base -strict;

use Test::More tests => 15;

# "Can't we have one meeting that doesn't end with digging up a corpse?"
use_ok 'Mojo::Date';

# RFC 822/1123
my $date = Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT');
is $date->epoch, 784111777, 'right epoch value';

# RFC 822/1123 - not strict RFC2616
is $date->new('Sun, 06 Nov 1994 08:49:37 UT')->epoch,
  784111777, 'right epoch value';

is $date->new('Sun, 06 Nov 1994 08:49:37 EST')->epoch,
  784111777 + (5 * 60 * 60), 'right epoch value';

is $date->new('Sun, 06 Nov 1994 08:49:37 CST')->epoch,
  784111777 + (6 * 60 * 60), 'right epoch value';

is $date->new('Sun, 06 Nov 1994 08:49:37 MDT')->epoch,
  784111777 + (6 * 60 * 60), 'right epoch value';

is $date->new('Sun, 06 Nov 1994 08:49:37 PDT')->epoch,
  784111777 + (7 * 60 * 60), 'right epoch value';


# RFC 850/1036
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
