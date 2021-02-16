use Mojo::Base -strict;

use Test::More;
use Mojo::File qw(path tempdir);
use Mojo::Log;
use Mojo::Util qw(decode);
use Time::HiRes qw(time);

my $dir  = tempdir;
my $path = $dir->child('test.log');

subtest 'Logging to file' => sub {
  my $log = Mojo::Log->new(level => 'error', path => $path);
  $log->error('Works');
  $log->fatal('I ♥ Mojolicious');
  $log->error(sub {'This too'});
  $log->debug('Does not work');
  $log->debug(sub { return 'And this', 'too' });
  undef $log;
  my $content = decode 'UTF-8', path($path)->slurp;
  like $content,   qr/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{5}] \[\d+\] \[error\] Works/, 'right error message';
  like $content,   qr/\[.*\] \[\d+\] \[fatal\] I ♥ Mojolicious/,                              'right fatal message';
  like $content,   qr/\[.*\] \[\d+\] \[error\] This too/,                                     'right error message';
  unlike $content, qr/\[.*\] \[\d+\] \[debug\] Does not work/,                                'no debug message';
  unlike $content, qr/\[.*\] \[\d+\] \[debug\] And this too\n/,                               'right debug message';
};

subtest 'Logging to STDERR' => sub {
  my $log    = Mojo::Log->new(level => 'error', path => $path);
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDERR = $handle;
    my $log = Mojo::Log->new;
    $log->error('Just works');
    $log->fatal('I ♥ Mojolicious');
    $log->debug('Works too');
    $log->debug(sub { return 'And this', 'too' });
  }
  my $content = decode 'UTF-8', $buffer;
  like $content, qr/\[.*\] \[error\] Just works\n/,      'right error message';
  like $content, qr/\[.*\] \[fatal\] I ♥ Mojolicious\n/, 'right fatal message';
  like $content, qr/\[.*\] \[debug\] Works too\n/,       'right debug message';
  like $content, qr/\[.*\] \[debug\] And this too\n/,    'right debug message';
};

subtest 'Formatting' => sub {
  my $log = Mojo::Log->new;
  like $log->format->(time,       'debug', 'Test 123'), qr/^\[.*\] \[debug\] Test 123\n$/, 'right format';
  like $log->format->(time,       'debug', qw(Test 1 2 3)), qr/^\[.*\] \[debug\] Test 1 2 3\n$/, 'right format';
  like $log->format->(time,       'error', 'I ♥ Mojolicious'), qr/^\[.*\] \[error\] I ♥ Mojolicious\n$/, 'right format';
  like $log->format->(CORE::time, 'error', 'I ♥ Mojolicious'), qr/^\[.*\] \[error\] I ♥ Mojolicious\n$/, 'right format';
  $log->format(sub {
    my ($time, $level, @lines) = @_;
    return join ':', $level, $time, @lines;
  });
  like $log->format->(time, 'debug', qw(Test 1 2 3)), qr/^debug:[0-9.]+:Test:1:2:3$/, 'right format';
};

subtest 'Short log messages (systemd)' => sub {
  my $log = Mojo::Log->new;
  ok !$log->short, 'long messages';
  like $log->format->(time, 'debug', 'Test 123'), qr/^\[.*\] \[debug\] Test 123\n$/, 'right format';
  local $ENV{MOJO_LOG_SHORT} = 1;
  $log = Mojo::Log->new;
  ok $log->short, 'short messages';
  $log = Mojo::Log->new(short => 1);
  ok $log->short, 'short messages';
  like $log->format->(time, 'debug', 'Test 123'), qr/^<7>\[\d+\] \[d\] Test 123\n$/, 'right format';
  like $log->format->(time, 'info',  'Test 123'), qr/^<6>\[\d+\] \[i\] Test 123\n$/, 'right format';
  like $log->format->(time, 'warn',  'Test 123'), qr/^<4>\[\d+\] \[w\] Test 123\n$/, 'right format';
  like $log->format->(time, 'error', 'Test 123'), qr/^<3>\[\d+\] \[e\] Test 123\n$/, 'right format';
  like $log->format->(time, 'fatal', 'Test 123'), qr/^<2>\[\d+\] \[f\] Test 123\n$/, 'right format';
  like $log->format->(time, 'debug', 'Test', '1', '2', '3'), qr/^<7>\[\d+\] \[d\] Test 1 2 3\n$/, 'right format';
};

subtest 'Colorized log messages' => sub {
  my $log = Mojo::Log->new;
  ok !$log->color, 'plain messages';
  like $log->format->(time, 'debug', 'Test 123'), qr/^\[.*\] \[debug\] Test 123\n$/, 'right format';
  local $ENV{MOJO_LOG_COLOR} = 1;
  $log = Mojo::Log->new;
  ok $log->color, 'colored messages';
  $log = Mojo::Log->new(color => 1);
  ok $log->color, 'colored messages';
  like $log->format->(time, 'debug', 'Test 123'), qr/^\[.+\] \[\d+\] \[debug\] Test 123\n$/,             'right format';
  like $log->format->(time, 'info',  'Test 123'), qr/^\[.+\] \[\d+\] \[info\] Test 123\n$/,              'right format';
  like $log->format->(time, 'warn',  'Test 123'), qr/^\e\[33m\[.+\] \[\d+\] \[warn\] Test 123\n\e\[0m$/, 'right format';
  like $log->format->(time, 'error', 'Test 123'), qr/^\e\[31m\[.+\] \[\d+\] \[error\] Test 123\n\e\[0m$/,
    'right format';
  like $log->format->(time, 'fatal', 'Test 123'), qr/^\e\[37;41m\[.+\] \[\d+\] \[fatal\] Test 123\n\e\[0m$/,
    'right format';
  is $log->format->(1613484767, 'debug', 'Test', '1', '2', '3'),
    "[2021-02-16 15:12:47.00000] [$$] [debug] Test 1 2 3\n", 'right format';
};

subtest 'Events' => sub {
  my $log  = Mojo::Log->new;
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
};

subtest 'History' => sub {
  my $buffer = '';
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
  my $content = decode 'UTF-8', $buffer;
  like $content,   qr/\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{5}\] \[$$\] \[error\] First\n/, 'right error message';
  like $content,   qr/\[.*\] \[info\] Fourth Fifth\n/,                                          'right info message';
  unlike $content, qr/debug/,                                                                   'no debug message';
  like $history->[0][0], qr/^[0-9.]+$/, 'right epoch time';
  is $history->[0][1],   'fatal',       'right level';
  is $history->[0][2],   'Second',      'right message';
  is $history->[1][1],   'info',        'right level';
  is $history->[1][2],   'Fourth',      'right message';
  is $history->[1][3],   'Fifth',       'right message';
  ok !$history->[2], 'no more messages';
};

subtest '"debug"' => sub {
  my $log = Mojo::Log->new;
  is $log->level('debug')->level, 'debug', 'right level';
  ok $log->is_level('debug'), '"debug" log level is active';
  ok $log->is_level('info'),  '"info" log level is active';
  ok $log->is_level('warn'),  '"warn" log level is active';
  ok $log->is_level('error'), '"error" log level is active';
};

subtest '"info"' => sub {
  my $log = Mojo::Log->new;
  is $log->level('info')->level, 'info', 'right level';
  ok !$log->is_level('debug'), '"debug" log level is inactive';
  ok $log->is_level('info'),  '"info" log level is active';
  ok $log->is_level('warn'),  '"warn" log level is active';
  ok $log->is_level('error'), '"error" log level is active';
};

subtest '"warn"' => sub {
  my $log = Mojo::Log->new;
  is $log->level('warn')->level, 'warn', 'right level';
  ok !$log->is_level('debug'), '"debug" log level is inactive';
  ok !$log->is_level('info'),  '"info" log level is inactive';
  ok $log->is_level('warn'),  '"warn" log level is active';
  ok $log->is_level('error'), '"error" log level is active';
};

subtest '"error"' => sub {
  my $log = Mojo::Log->new;
  is $log->level('error')->level, 'error', 'right level';
  ok !$log->is_level('debug'), '"debug" log level is inactive';
  ok !$log->is_level('info'),  '"info" log level is inactive';
  ok !$log->is_level('warn'),  '"warn" log level is inactive';
  ok $log->is_level('error'), '"error" log level is active';
};

subtest '"fatal"' => sub {
  my $log = Mojo::Log->new;
  is $log->level('fatal')->level, 'fatal', 'right level';
  ok !$log->is_level('debug'), '"debug" log level is inactive';
  ok !$log->is_level('info'),  '"info" log level is inactive';
  ok !$log->is_level('warn'),  '"warn" log level is inactive';
  ok !$log->is_level('error'), '"error" log level is inactive';
};

subtest 'Context' => sub {
  my $log     = Mojo::Log->new(level => 'warn');
  my $context = $log->context('[123]');
  is $context->level, 'warn';
  my $buffer = '';
  {
    open my $handle, '>', \$buffer;
    local *STDERR = $handle;
    my $log = Mojo::Log->new;
    $context->debug('Fail');
    $context->error('Just works');
    $log->warn('No context');
    $context->fatal('Mojolicious rocks');
  }
  unlike $buffer, qr/\[debug\]/,                                    'no debug message';
  like $buffer,   qr/\[.*\] \[error\] \[123\] Just works\n/,        'right error message';
  like $buffer,   qr/\[.*\] \[warn\] No context\n/,                 'right warn message';
  like $buffer,   qr/\[.*\] \[fatal\] \[123\] Mojolicious rocks\n/, 'right fatal message';
};

done_testing();
