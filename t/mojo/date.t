use Mojo::Base -strict;

use Test::More;
use Mojo::Date;

# RFC 822/1123
my $date = Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT');
is $date->epoch, 784111777, 'right epoch value';
$date = Mojo::Date->new('Fri, 13 May 2011 10:00:24 GMT');
is $date->epoch, 1305280824, 'right epoch value';

# RFC 3339
is(Mojo::Date->new('2014-08-20T20:45:00')->epoch,
  1408567500, 'right epoch value');
is(Mojo::Date->new(1408567500)->to_datetime,
  '2014-08-20T20:45:00Z', 'right format');
is(Mojo::Date->new('2014-08-20T20:45:00.01')->epoch,
  1408567500.01, 'right epoch value');
is(Mojo::Date->new('2014-08-20T20:45:00-00:46')->epoch,
  1408570260, 'right epoch value');
is(Mojo::Date->new(1408570260)->to_datetime,
  '2014-08-20T21:31:00Z', 'right format');
is(Mojo::Date->new('2014-08-20t20:45:00-01:46')->epoch,
  1408573860, 'right epoch value');
is(Mojo::Date->new('2014-08-20t20:45:00+01:46')->epoch,
  1408561140, 'right epoch value');
is(Mojo::Date->new(1408561140)->to_datetime,
  '2014-08-20T18:59:00Z', 'right format');
is(Mojo::Date->new('1994-11-06T08:49:37Z')->epoch,
  784111777, 'right epoch value');
is(Mojo::Date->new('1994-11-06t08:49:37.33z')->epoch,
  784111777.33, 'right epoch value');
is(Mojo::Date->new('2014-08-20  20:45:00')->epoch,
  1408567500, 'right epoch value');
is(Mojo::Date->new(784111777.33)->to_datetime,
  '1994-11-06T08:49:37.33Z', 'right format');

# RFC 850/1036
is(Mojo::Date->new('Sunday, 06-Nov-94 08:49:37 GMT')->epoch,
  784111777, 'right epoch value');
is(Mojo::Date->new('Friday, 13-May-11 10:00:24 GMT')->epoch,
  1305280824, 'right epoch value');

# ANSI C asctime()
is(Mojo::Date->new('Sun Nov  6 08:49:37 1994')->epoch,
  784111777, 'right epoch value');
is(Mojo::Date->new('Fri May 13 10:00:24 2011')->epoch,
  1305280824, 'right epoch value');

# Invalid string
is(Mojo::Date->new('')->epoch,        undef, 'no epoch value');
is(Mojo::Date->new('123 abc')->epoch, undef, 'no epoch value');
is(Mojo::Date->new('abc')->epoch,     undef, 'no epoch value');
is(Mojo::Date->new('Xxx, 00 Xxx 0000 00:00:00 XXX')->epoch,
  undef, 'no epoch value');
is(Mojo::Date->new('Sun, 06 Nov 1994 08:49:37 GMT GARBAGE')->epoch,
  undef, 'no epoch value');
is(Mojo::Date->new('Sunday, 06-Nov-94 08:49:37 GMT GARBAGE')->epoch,
  undef, 'no epoch value');
is(Mojo::Date->new('Sun Nov  6 08:49:37 1994 GARBAGE')->epoch,
  undef, 'no epoch value');
is(Mojo::Date->new('Fri, 75 May 2011 99:99:99 GMT')->epoch,
  undef, 'no epoch value');
is(Mojo::Date->new('0000-00-00T00:00:00+01:00')->epoch,
  undef, 'no epoch value');

# to_string
$date = Mojo::Date->new(784111777);
is "$date", 'Sun, 06 Nov 1994 08:49:37 GMT', 'right format';
$date = Mojo::Date->new(1305280824);
is $date->to_string, 'Fri, 13 May 2011 10:00:24 GMT', 'right format';

# Current time roundtrips
my $before = time;
ok(Mojo::Date->new(Mojo::Date->new->to_string)->epoch >= $before,
  'successful roundtrip');
ok(Mojo::Date->new(Mojo::Date->new->to_datetime)->epoch >= $before,
  'successful roundtrip');

# Zero time checks
$date = Mojo::Date->new(0);
is $date->epoch, 0, 'right epoch value';
is "$date", 'Thu, 01 Jan 1970 00:00:00 GMT', 'right format';
is(Mojo::Date->new('Thu, 01 Jan 1970 00:00:00 GMT')->epoch,
  0, 'right epoch value');

# Negative epoch value
$date = Mojo::Date->new;
ok $date->parse('Mon, 01 Jan 1900 00:00:00'), 'right format';
is $date->epoch, undef, 'no epoch value';

done_testing();
