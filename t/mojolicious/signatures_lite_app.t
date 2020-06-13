use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;

BEGIN { plan skip_all => 'Perl 5.20+ required for this test!' if $] < 5.020 }

use Mojolicious::Lite -signatures;

helper send_json => sub ($c, $hash) { $c->send({json => $hash}) };

get '/' => sub ($c) {
  $c->render(text => 'works!');
};

websocket '/json' => sub ($c) {
  $c->on(
    json => sub ($c, $hash) {
      $c->send_json($hash);
    }
  );
};

my $t = Test::Mojo->new;

# Plain action
$t->get_ok('/')->status_is(200)->content_is('works!');

# WebSocket
$t->websocket_ok('/json')->send_ok({json => {snowman => '☃'}})->message_ok->json_message_is('' => {snowman => '☃'})
  ->finish_ok;

done_testing();
