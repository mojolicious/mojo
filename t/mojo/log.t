use Mojo::Base -strict;

use Test::More tests => 30;

# "Don't let Krusty's death get you down, boy.
#  People die all the time, just like that.
#  Why, you could wake up dead tomorrow! Well, good night."
use Mojo::Log;

# Formatting
my $log = Mojo::Log->new;
like $log->format(debug => 'Test 123.'), qr/^\[.*\] \[debug\] Test 123\.\n$/,
  'right format';
like $log->format(qw/debug Test 123./), qr/^\[.*\] \[debug\] Test\n123\.\n$/,
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

# "debug"
$log->level('debug');
ok $log->is_debug, '"debug" log level is active';
ok $log->is_info,  '"info" log level is active';
ok $log->is_warn,  '"warn" log level is active';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "info"
$log->level('info');
ok !$log->is_debug, '"debug" log level is inactive';
ok $log->is_info,  '"info" log level is active';
ok $log->is_warn,  '"warn" log level is active';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "warn"
$log->level('warn');
ok !$log->is_debug, '"debug" log level is inactive';
ok !$log->is_info,  '"info" log level is inactive';
ok $log->is_warn,  '"warn" log level is active';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "error"
$log->level('error');
ok !$log->is_debug, '"debug" log level is inactive';
ok !$log->is_info,  '"info" log level is inactive';
ok !$log->is_warn,  '"warn" log level is inactive';
ok $log->is_error, '"error" log level is active';
ok $log->is_fatal, '"fatal" log level is active';

# "fatal"
$log->level('fatal');
ok !$log->is_debug, '"debug" log level is inactive';
ok !$log->is_info,  '"info" log level is inactive';
ok !$log->is_warn,  '"warn" log level is inactive';
ok !$log->is_error, '"error" log level is inactive';
ok $log->is_fatal, '"fatal" log level is active';
