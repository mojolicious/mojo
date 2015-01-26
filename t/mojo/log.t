use Mojo::Base -strict;

use Test::More;
use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use Mojo::Log;
use Mojo::Util qw(decode slurp);

# Logging to file
my $dir = tempdir CLEANUP => 1;
my $path = catdir $dir, 'test.log';
my $log = Mojo::Log->new(level => 'error', path => $path);
$log->error('Just works');
$log->fatal('I ♥ Mojolicious');
$log->debug('Does not work');
undef $log;
my $content = decode 'UTF-8', slurp($path);
like $content,   qr/\[.*\] \[error\] Just works/,        'right error message';
like $content,   qr/\[.*\] \[fatal\] I ♥ Mojolicious/, 'right fatal message';
unlike $content, qr/\[.*\] \[debug\] Does not work/,     'no debug message';

# Logging to STDERR
my $buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDERR = $handle;
  my $log = Mojo::Log->new;
  $log->error('Just works');
  $log->fatal('I ♥ Mojolicious');
  $log->debug('Works too');
}
$content = decode 'UTF-8', $buffer;
like $content, qr/\[.*\] \[error\] Just works\n/,        'right error message';
like $content, qr/\[.*\] \[fatal\] I ♥ Mojolicious\n/, 'right fatal message';
like $content, qr/\[.*\] \[debug\] Works too\n/,         'right debug message';

# Formatting
$log = Mojo::Log->new;
like $log->format->(time, 'debug', 'Test 123'),
  qr/^\[.*\] \[debug\] Test 123\n$/, 'right format';
like $log->format->(time, 'debug', qw(Test 1 2 3)),
  qr/^\[.*\] \[debug\] Test\n1\n2\n3\n$/, 'right format';
like $log->format->(time, 'error', 'I ♥ Mojolicious'),
  qr/^\[.*\] \[error\] I ♥ Mojolicious\n$/, 'right format';
$log->format(
  sub {
    my ($time, $level, @lines) = @_;
    return join ':', $level, $time, @lines;
  }
);
like $log->format->(time, 'debug', qw(Test 1 2 3)),
  qr/^debug:\d+:Test:1:2:3$/, 'right format';

# Events
$log = Mojo::Log->new;
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

# History
$buffer = '';
my $history;
{
  open my $handle, '>', \$buffer;
  local *STDERR = $handle;
  my $log = Mojo::Log->new->max_history_size(2)->level('info');
  $log->error('First');
  $log->fatal('Second');
  $log->debug('Third');
  $log->info('Fourth', 'Fifth');
  $history = $log->history;
}
$content = decode 'UTF-8', $buffer;
like $content,   qr/\[.*\] \[error\] First\n/,        'right error message';
like $content,   qr/\[.*\] \[info\] Fourth\nFifth\n/, 'right info message';
unlike $content, qr/debug/,                           'no debug message';
like $history->[0][0], qr/^\d+$/, 'right epoch time';
is $history->[0][1],   'fatal',   'right level';
is $history->[0][2],   'Second',  'right message';
is $history->[1][1],   'info',    'right level';
is $history->[1][2],   'Fourth',  'right message';
is $history->[1][3],   'Fifth',   'right message';
ok !$history->[2], 'no more messages';

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

done_testing();
