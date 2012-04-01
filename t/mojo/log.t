use Mojo::Base -strict;

use Test::More tests => 45;

# "Don't let Krusty's death get you down, boy.
#  People die all the time, just like that.
#  Why, you could wake up dead tomorrow! Well, good night."
use File::Spec::Functions 'catdir';
use File::Temp;
use Mojo::Asset::File;
use Mojo::Log;

# Logging to file
my $dir = File::Temp::tempdir(CLEANUP => 1);
my $path = catdir $dir, 'test.log';
my $log = Mojo::Log->new(level => 'debug', path => $path);
$log->debug('Just works.');
undef $log;
like(
  Mojo::Asset::File->new(path => $path)->slurp,
  qr/^\[.*\] \[debug\] Just works\.\n$/,
  'right content'
);

# Formatting
$log = Mojo::Log->new;
like $log->format(debug => 'Test 123.'), qr/^\[.*\] \[debug\] Test 123\.\n$/,
  'right format';
like $log->format(qw/debug Test 1 2 3/),
  qr/^\[.*\] \[debug\] Test\n1\n2\n3\n$/,
  'right format';

# Events
my $messages = [];
$log->unsubscribe('message')->on(
  message => sub {
    my ($log, $level, @messages) = @_;
    push @$messages, $level, @messages;
  }
);
$log->info('Whatever.');
is_deeply $messages, [qw/info Whatever./], 'right messages';
$log->level('error')->info('Again.');
is_deeply $messages, [qw/info Whatever./], 'right messages';
$log->fatal('Test', 123);
is_deeply $messages, [qw/info Whatever. fatal Test 123/], 'right messages';
$messages = [];
$log->level('debug')->log(info => 'Whatever.');
is_deeply $messages, [qw/info Whatever./], 'right messages';
$log->level('error')->log(info => 'Again.');
is_deeply $messages, [qw/info Whatever./], 'right messages';
$log->log(fatal => 'Test', 1, 2, 3);
is_deeply $messages, [qw/info Whatever. fatal Test 1 2 3/], 'right messages';

# "debug"
is $log->level('debug')->level, 'debug', 'right level';
ok $log->is_level('debug'), '"debug" log level is active';
ok $log->is_level('info'),  '"info" log level is active';
ok $log->is_debug, '"debug" log level is active';
ok $log->is_info,  '"info" log level is active';
ok $log->is_warn,  '"warn" log level is active';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "info"
is $log->level('info')->level, 'info', 'right level';
ok !$log->is_level('debug'), '"debug" log level is inactive';
ok $log->is_level('info'), '"info" log level is active';
ok !$log->is_debug, '"debug" log level is inactive';
ok $log->is_info,  '"info" log level is active';
ok $log->is_warn,  '"warn" log level is active';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "warn"
is $log->level('warn')->level, 'warn', 'right level';
ok !$log->is_level('debug'), '"debug" log level is inactive';
ok !$log->is_level('info'),  '"info" log level is inactive';
ok !$log->is_debug, '"debug" log level is inactive';
ok !$log->is_info,  '"info" log level is inactive';
ok $log->is_warn,  '"warn" log level is active';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "error"
is $log->level('error')->level, 'error', 'right level';
ok !$log->is_debug, '"debug" log level is inactive';
ok !$log->is_info,  '"info" log level is inactive';
ok !$log->is_warn,  '"warn" log level is inactive';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "fatal"
is $log->level('fatal')->level, 'fatal', 'right level';
ok !$log->is_debug, '"debug" log level is inactive';
ok !$log->is_info,  '"info" log level is inactive';
ok !$log->is_warn,  '"warn" log level is inactive';
ok !$log->is_error, '"error" log level is inactive';
ok $log->is_fatal, '"fatal" log level is active';
