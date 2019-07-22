use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_NNR}  = $ENV{MOJO_NO_SOCKS} = $ENV{MOJO_NO_TLS} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('debug')->unsubscribe('message');

get '/' => sub {
  my $c = shift;
  $c->render(template => 'index');
};

get '/foo' => sub {
  my $c = shift;
  $c->render(json => $c->req->query_params->to_hash);
};

my $ua = new_ok 'Mojo::UserAgent';
my $tx = $ua->get('/');
my $dom = $tx->result->dom;
my $form = $dom->at('form');

is $form->tag, 'form', 'correct element';
my $exp = { a => 'A', b => 'B', c => 'C', d => 'D', f => ['I', 'J'], m => 'M',
  n => undef, o => 'O', q => undef, r => 'on', s => undef, t => '', u => undef,
};
is_deeply $form->val, $exp, 'val';
is_deeply [ $form->target('#submit-form') ], [qw{GET /foo url-encoded}], 'correct element';

isa_ok $tx->submit(), 'Mojo::Transaction::HTTP';
isa_ok $tx->submit('input[name=p]'), 'Mojo::Transaction::HTTP';
is $tx->submit('#broken-id'), undef, 'no button with that id';
is $tx->submit('input[name=pause]'), undef, 'disabled button';
is $tx->submit('input[name=oooh]'), undef, 'not a submit button';

my $submit_tx = $tx->submit('#submit-form');
$ua->start($submit_tx);
is_deeply $submit_tx->res->json, {'a' => 'A', 'b' => 'B', 'c' => 'C',
  'd' => 'D', 'f' => ['I', 'J'], 'm' => 'M', 'o' => 'O', 'r' => 'on',
  't' => ''}, 'expected response';

$submit_tx = $tx->submit('#submit-form', a => 'Z', o => 'L', foo => 'bar');
$ua->start($submit_tx);
is_deeply $submit_tx->res->json, {'a' => 'Z', 'b' => 'B', 'c' => 'C',
  'd' => 'D', 'f' => ['I', 'J'], 'm' => 'M', 'o' => 'L', 'r' => 'on',
  't' => ''}, 'expected response - foo not included';


$submit_tx = $tx->submit(a => 'X', 'm' => 'on');
ok $submit_tx;
$ua->start($submit_tx);
is_deeply $submit_tx->res->json, {'a' => 'X', 'b' => 'B', 'c' => 'C',
  'd' => 'D', 'f' => ['I', 'J'], 'm' => 'on', 'o' => 'O', 'r' => 'on',
  't' => ''}, 'expected response';

my $json = {};
$ua->get_p('/')->then(sub {
  my $tx     = shift;
  my $submit = $tx->submit(a => 'x');
  return $ua->start_p($submit);
})->then(sub {
  my $tx = shift;
  $json = $tx->res->json;
})->catch(sub {
  my $err = shift;
  warn "Connection error: $err";
})->wait;

is_deeply $json, {'a' => 'x', 'b' => 'B', 'c' => 'C', 'd' => 'D',
  'f' => ['I', 'J'], 'm' => 'M', 'o' => 'O', 'r' => 'on', 't' => ''},
  'expected response';

done_testing;

__DATA__
@@ index.html.ep
% layout 'default';
% title 'Welcome';
<h1>Welcome to the Mojolicious real-time web framework!</h1>
<div>
  <form action="/foo">
    <p>Test</p>
    <input type="text" name="a" value="A" />
    <input type="checkbox" name="q">
    <input type="checkbox" checked name="b" value="B">
    <input type="radio" name="r">
    <input type="radio" checked name="c" value="C">
    <input name="s">
    <input type="checkbox" name="t" value="">
    <input type=text name="u">
    <select multiple name="f">
      <option value="F">G</option>
      <optgroup>
        <option>H</option>
        <option selected>I</option>
        <option selected disabled>V</option>
      </optgroup>
      <option value="J" selected>K</option>
      <optgroup disabled>
        <option selected>I2</option>
      </optgroup>
    </select>
    <select name="n"><option>N</option></select>
    <select multiple name="q"><option>Q</option></select>
    <select name="y" disabled>
      <option selected>Y</option>
    </select>
    <select name="d">
      <option selected>R</option>
      <option selected>D</option>
    </select>
    <textarea name="m">M</textarea>
    <button name="o" value="O">No!</button>
    <input type="submit" name="p" value="P" id="submit-form" />
    <input type="submit" name="pause" value="||" disabled />
    <button type=button name="oooh" value="Arrh">No!</button>
  </form>
</div>
@@ layouts/default.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title></head>
  <body><%= content %></body>
</html>
