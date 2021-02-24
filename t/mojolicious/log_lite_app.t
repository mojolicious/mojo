use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojolicious::Lite;
use Mojo::Log;
use Test::Mojo;

hook before_dispatch => sub {
  my $c = shift;
  $c->req->request_id('17a60115');
};

get '/simple' => sub {
  my $c = shift;
  $c->log->debug('First!');
  $c->log->info('Second!', 'Third!');
  $c->app->log->debug('No context!');
  $c->log->warn(sub { 'Fourth!', 'Fifth!' });
  $c->render(text => 'Simple!');
};

my $t = Test::Mojo->new;

# Simple log messages with and without context
my $buffer = '';
open my $handle, '>', \$buffer;
$t->app->log(Mojo::Log->new(handle => $handle, level => 'debug'));
$t->get_ok('/simple')->status_is(200)->content_is('Simple!');
like $buffer, qr/First.*Second.*Third.*No context!.*Fourth.*Fifth/s,    'right order';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] \[17a60115\] First!/,         'message with request id';
like $buffer, qr/\[.+\] \[\d+\] \[info\] \[17a60115\] Second! Third!/s, 'message with request id';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] No context!/,                 'message without request id';
like $buffer, qr/\[.+\] \[\d+\] \[warn\] \[17a60115\] Fourth! Fifth!/s, 'message with request id';

# Concurrent requests
$buffer = '';
my $first = $t->app->build_controller;
$first->req->request_id('123-first');
my $second = $t->app->build_controller;
$second->req->request_id('123-second');
$first->log->debug('First!');
$second->log->debug('Second!');
$first->log->debug('Third!');
$second->log->debug('Fourth!');
$t->app->log->debug('Fifth!');
like $buffer, qr/First.*Second.*Third.*Fourth.*Fifth/s,            'right order';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] \[123-first\] First!/,   'message with request id';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] \[123-second\] Second!/, 'message with request id';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] \[123-first\] Third!/,   'message with request id';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] \[123-second\] Fourth!/, 'message with request id';
like $buffer, qr/\[.+\] \[\d+\] \[debug\] Fifth!/,                 'message without request id';

done_testing();
