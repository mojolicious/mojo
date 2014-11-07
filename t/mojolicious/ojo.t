use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_PROXY}   = 0;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use ojo;

# Application
a('/' => sub { $_->render(data => $_->req->method . $_->req->body) })
  ->secrets(['foobarbaz']);
is a->secrets->[0], 'foobarbaz', 'right secret';

# Requests
is g('/')->body, 'GET',     'right content';
is h('/')->body, '',        'no content';
is o('/')->body, 'OPTIONS', 'right content';
is t('/')->body, 'PATCH',   'right content';
is p('/')->body, 'POST',    'right content';
is u('/')->body, 'PUT',     'right content';
is d('/')->body, 'DELETE',  'right content';
is p('/' => form => {foo => 'bar'})->body, 'POSTfoo=bar', 'right content';
is p('/' => json => {foo => 'bar'})->body, 'POST{"foo":"bar"}',
  'right content';

# Mojolicious::Lite
get '/test' => {text => 'pass'};
is app->ua->get('/test')->res->body, 'pass', 'right content';

# Parse XML
is x('<title>works</title>')->at('title')->text, 'works', 'right text';

# JSON
is j([1, 2]), '[1,2]', 'right result';
is_deeply j('[1,2]'), [1, 2], 'right structure';
is j({foo => 'bar'}), '{"foo":"bar"}', 'right result';
is_deeply j('{"foo":"bar"}'), {foo => 'bar'}, 'right structure';

# ByteStream
is b('<foo>')->url_escape, '%3Cfoo%3E', 'right result';

# Collection
is c(1, 2, 3)->join('-'), '1-2-3', 'right result';

# Dumper
is r([1, 2]), "[\n  1,\n  2\n]\n", 'right result';

# Benchmark
{
  my $buffer = '';
  open my $handle, '>', \$buffer;
  local *STDERR = $handle;
  my $i = 0;
  n { ++$i };
  is $i,        1,             'block has been invoked once';
  like $buffer, qr/wallclock/, 'right output';
  n { $i++ } 10;
  is $i, 11, 'block has been invoked ten times';
  like $buffer, qr/wallclock.*wallclock/s, 'right output';
}

done_testing();
