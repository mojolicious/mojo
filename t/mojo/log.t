use Mojo::Base -strict;

use Test::More tests => 47;

use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use Mojo::Asset::File;
use Mojo::Log;

# Logging to file
my $dir = tempdir CLEANUP => 1;
my $path = catdir $dir, 'test.log';
my $log = Mojo::Log->new(level => 'error', path => $path);
$log->error('Just works.');
$log->fatal('Works too.');
$log->debug('Does not work.');
undef $log;
my $content = Mojo::Asset::File->new(path => $path)->slurp;
like $content,   qr/\[.*\] \[error\] Just works\.\n/,    'has error message';
like $content,   qr/\[.*\] \[fatal\] Works too\.\n/,     'has fatal message';
unlike $content, qr/\[.*\] \[debug\] Does not work\.\n/, 'no debug message';

# Formatting
$log = Mojo::Log->new;
like $log->format(debug => 'Test 123.'), qr/^\[.*\] \[debug\] Test 123\.\n$/,
  'right format';
like $log->format(qw(debug Test 1 2 3)),
  qr/^\[.*\] \[debug\] Test\n1\n2\n3\n$/, 'right format';

# Events
my $msgs = [];
$log->unsubscribe('message')->on(
  message => sub {
    my ($log, $level, @lines) = @_;
    push @$msgs, $level, @lines;
  }
);
$log->debug('Test', 1, 2, 3);
is_deeply $msgs, [qw(debug Test 1 2 3)], 'right message';
$msgs = [];
$log->info('Test', 1, 2, 3);
is_deeply $msgs, [qw(info Test 1 2 3)], 'right message';
$msgs = [];
$log->warn('Test', 1, 2, 3);
is_deeply $msgs, [qw(warn Test 1 2 3)], 'right message';
$msgs = [];
$log->error('Test', 1, 2, 3);
is_deeply $msgs, [qw(error Test 1 2 3)], 'right message';
$msgs = [];
$log->fatal('Test', 1, 2, 3);
is_deeply $msgs, [qw(fatal Test 1 2 3)], 'right message';
$msgs = [];
$log->log('fatal', 'Test', 1, 2, 3);
is_deeply $msgs, [qw(fatal Test 1 2 3)], 'right message';

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
