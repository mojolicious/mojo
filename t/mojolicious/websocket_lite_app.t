use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::ByteStream 'b';
use Mojo::JSON 'j';
use Mojolicious::Lite;
use Test::Mojo;

websocket '/echo' => sub {
  my $self = shift;
  $self->on(binary => sub { shift->send({binary => shift}) });
  $self->on(
    text => sub {
      my ($self, $bytes) = @_;
      $self->send("echo: $bytes");
    }
  );
};

get '/echo' => {text => 'plain echo!'};

websocket '/json' => sub {
  my $self = shift;
  $self->on(binary => sub { shift->send({binary => j([@{j(shift)}, 4])}) });
  $self->on(
    text => sub {
      my ($self, $json) = @_;
      my $hash = j($json);
      $hash->{test} += 1;
      $self->send({text => j($hash)});
    }
  );
};

get '/plain' => {text => 'Nothing to see here!'};

websocket '/push' => sub {
  my $self = shift;
  my $id = Mojo::IOLoop->recurring(0.1 => sub { $self->send('push') });
  $self->on(finish => sub { Mojo::IOLoop->remove($id) });
};

websocket '/unicode' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send("♥: $msg");
    }
  );
};

websocket '/bytes' => sub {
  my $self = shift;
  $self->on(
    frame => sub {
      my ($ws, $frame) = @_;
      $ws->send({$frame->[4] == 2 ? 'binary' : 'text', $frame->[5]});
    }
  );
};

websocket '/once' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send("ONE: $msg");
    }
  );
  $self->tx->once(
    message => sub {
      my ($tx, $msg) = @_;
      $self->send("TWO: $msg");
    }
  );
};

under '/nested';

websocket sub {
  my $self = shift;
  my $echo = $self->cookie('echo') // '';
  $self->cookie(echo => 'again');
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send("nested echo: $msg$echo");
    }
  );
};

get {text => 'plain nested!'};

post {data => 'plain nested too!'};

my $t = Test::Mojo->new;

# Default protocol
$t->websocket_ok('/echo')->header_is('Sec-WebSocket-Protocol' => 'mojo')
  ->send_ok('hello')->message_ok('got a message')->message_is('echo: hello')
  ->finish_ok;

# Multiple roundtrips
$t->websocket_ok('/echo')->send_ok('hello again')
  ->message_ok->message_is('echo: hello again')->send_ok('and one more time')
  ->message_ok->message_is('echo: and one more time')->finish_ok;

# Custom protocol
$t->websocket_ok('/echo', {'Sec-WebSocket-Protocol' => 'foo, bar, baz'})
  ->header_is('Sec-WebSocket-Protocol' => 'foo')->send_ok('hello')
  ->message_ok->message_is('echo: hello')->finish_ok;

# Bytes
$t->websocket_ok('/echo')->send_ok({binary => 'bytes!'})
  ->message_ok->message_is({binary => 'bytes!'})
  ->send_ok({binary => 'bytes!'})
  ->message_ok->message_isnt({text => 'bytes!'})->finish_ok;

# Zero
$t->websocket_ok('/echo')->send_ok(0)->message_ok->message_is('echo: 0')
  ->send_ok(0)->message_ok->message_like({text => qr/0/})->finish_ok;

# Plain alternative
$t->get_ok('/echo')->status_is(200)->content_is('plain echo!');

# JSON roundtrips
$t->websocket_ok('/json')
  ->send_ok({text => j({test => 23, snowman => '☃'})})
  ->message_ok->json_message_is('' => {test => 24, snowman => '☃'})
  ->json_message_has('/test')->json_message_hasnt('/test/2')
  ->send_ok({binary => j([1, 2, 3])})
  ->message_ok->json_message_is('' => [1, 2, 3, 4], 'right content')
  ->send_ok({binary => j([1, 2, 3])})
  ->message_ok->json_message_has('/2', 'has two elements')
  ->json_message_is('/2' => 3)->json_message_hasnt('/5', 'not five elements')
  ->finish_ok;

# Plain request
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# Server push
$t->websocket_ok('/push')->message_ok->message_is('push')
  ->message_ok->message_is('push')->message_ok->message_is('push')->finish_ok;
$t->websocket_ok('/push')->message_ok->message_unlike(qr/shift/)
  ->message_ok->message_isnt('shift')->message_ok->message_like(qr/us/)
  ->message_ok->message_unlike({binary => qr/push/})->finish_ok;

# Another plain request
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# Multiple roundtrips
$t->websocket_ok('/echo')->send_ok('hello')
  ->message_ok->message_is('echo: hello')->finish_ok;
$t->websocket_ok('/echo')->send_ok('this')->send_ok('just')->send_ok('works')
  ->message_ok->message_is('echo: this')->message_ok->message_is('echo: just')
  ->message_ok->message_is('echo: works')->message_like(qr/orks/)->finish_ok;

# Another plain request
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# Unicode roundtrips
$t->websocket_ok('/unicode')->send_ok('hello')
  ->message_ok->message_is('♥: hello')->finish_ok;
$t->websocket_ok('/unicode')->send_ok('hello again')
  ->message_ok->message_is('♥: hello again')
  ->send_ok('and one ☃ more time')
  ->message_ok->message_is('♥: and one ☃ more time')->finish_ok;

# Binary frame and frame event
my $bytes = b("I ♥ Mojolicious")->encode('UTF-16LE')->to_string;
$t->websocket_ok('/bytes');
my $binary;
$t->tx->on(
  frame => sub {
    my ($ws, $frame) = @_;
    $binary++ if $frame->[4] == 2;
  }
);
$t->send_ok({binary => $bytes})->message_ok->message_is($bytes);
ok $binary, 'received binary frame';
$binary = undef;
$t->send_ok({text => $bytes})->message_ok->message_is($bytes)->finish_ok;
ok !$binary, 'received text frame';

# Binary roundtrips
$t->websocket_ok('/bytes')->send_ok({binary => $bytes})
  ->message_ok->message_is($bytes)->send_ok({binary => $bytes})
  ->message_ok->message_is($bytes)->finish_ok;

# Two responses
$t->websocket_ok('/once')->send_ok('hello')
  ->message_ok->message_is('ONE: hello')->message_ok->message_is('TWO: hello')
  ->send_ok('hello')->message_ok->message_is('ONE: hello')->send_ok('hello')
  ->message_ok->message_is('ONE: hello')->finish_ok;

# Nested WebSocket
$t->websocket_ok('/nested')->send_ok('hello')
  ->message_ok->message_is('nested echo: hello')->finish_ok;

# Test custom message
$t->message([binary => 'foobarbaz'])->message_like(qr/bar/)
  ->message_is({binary => 'foobarbaz'});

# Nested WebSocket with cookie
$t->websocket_ok('/nested')->send_ok('hello')
  ->message_ok->message_is('nested echo: helloagain')->finish_ok;

# Nested plain request
$t->get_ok('/nested')->status_is(200)->content_is('plain nested!');

# Another nested plain request
$t->post_ok('/nested')->status_is(200)->content_is('plain nested too!');

done_testing();
