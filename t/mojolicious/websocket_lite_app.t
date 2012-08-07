use Mojo::Base -strict;

# "Oh, dear. She's stuck in an infinite loop and he's an idiot.
#  Well, that's love for you."
use utf8;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 97;

use Mojo::ByteStream 'b';
use Mojolicious::Lite;
use Test::Mojo;

# WebSocket /echo
websocket '/echo' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send("echo: $message");
    }
  );
};

# GET /echo
get '/echo' => {text => 'plain echo!'};

# GET /plain
get '/plain' => {text => 'Nothing to see here!'};

# WebSocket /push
websocket '/push' => sub {
  my $self = shift;
  my $id = Mojo::IOLoop->recurring(0.25 => sub { $self->send('push') });
  $self->on(finish => sub { Mojo::IOLoop->remove($id) });
};

# WebSocket /unicode
websocket '/unicode' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send("♥: $message");
    }
  );
};

# WebSocket /bytes
websocket '/bytes' => sub {
  my $self = shift;
  $self->tx->on(
    frame => sub {
      my ($ws, $frame) = @_;
      $ws->send({$frame->[4] == 2 ? 'binary' : 'text', $frame->[5]});
    }
  );
  $self->rendered(101);
};

# WebSocket /once
websocket '/once' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send("ONE: $message");
    }
  );
  $self->tx->once(
    message => sub {
      my ($tx, $message) = @_;
      $self->send("TWO: $message");
    }
  );
};

# /nested
under '/nested';

# WebSocket /nested
websocket sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send("nested echo: $message");
    }
  );
};

# GET /nested
get {text => 'plain nested!'};

# POST /nested
post {data => 'plain nested too!'};

# "I was a hero to broken robots 'cause I was one of them, but how can I sing
#  about being damaged if I'm not?
#  That's like Christina Aguilera singing Spanish.
#  Ooh, wait! That's it! I'll fake it!"
my $t = Test::Mojo->new;

# WebSocket /echo (default protocol)
$t->websocket_ok('/echo')->header_is('Sec-WebSocket-Protocol' => 'mojo')
  ->send_ok('hello')->message_is('echo: hello')->finish_ok;

# WebSocket /echo (multiple times)
$t->websocket_ok('/echo')->send_ok('hello again')
  ->message_is('echo: hello again')->send_ok('and one more time')
  ->message_is('echo: and one more time')->finish_ok;

# WebSocket /echo (with custom protocol)
$t->websocket_ok('/echo', {'Sec-WebSocket-Protocol' => 'foo, bar, baz'})
  ->header_is('Sec-WebSocket-Protocol' => 'foo')->send_ok('hello')
  ->message_is('echo: hello')->finish_ok;

# WebSocket /echo (zero)
$t->websocket_ok('/echo')->send_ok(0)->message_is('echo: 0')->finish_ok;

# GET /echo (plain alternative)
$t->get_ok('/echo')->status_is(200)->content_is('plain echo!');

# GET /plain
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# WebSocket /push
$t->websocket_ok('/push')->message_is('push')->message_is('push')
  ->message_is('push')->finish_ok;

# WebSocket /push (again)
$t->websocket_ok('/push')->message_unlike(qr/shift/)->message_isnt('shift')
  ->message_like(qr/us/)->finish_ok;

# GET /plain (again)
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# WebSocket /echo (again)
$t->websocket_ok('/echo')->send_ok('hello')->message_is('echo: hello')
  ->finish_ok;

# WebSocket /echo (mixed)
$t->websocket_ok('/echo')->send_ok('this')->send_ok('just')->send_ok('works')
  ->message_is('echo: this')->message_is('echo: just')
  ->message_is('echo: works')->finish_ok;

# GET /plain (and again)
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# WebSocket /unicode
$t->websocket_ok('/unicode')->send_ok('hello')->message_is('♥: hello')
  ->finish_ok;

# WebSocket /unicode (multiple times)
$t->websocket_ok('/unicode')->send_ok('hello again')
  ->message_is('♥: hello again')->send_ok('and one ☃ more time')
  ->message_is('♥: and one ☃ more time')->finish_ok;

# WebSocket /bytes (binary frame and frame event)
my $bytes = b("I ♥ Mojolicious")->encode('UTF-16LE')->to_string;
$t->websocket_ok('/bytes');
my $binary;
$t->tx->on(
  frame => sub {
    my ($ws, $frame) = @_;
    $binary++ if $frame->[4] == 2;
  }
);
$t->send_ok({binary => $bytes})->message_is($bytes);
ok $binary, 'received binary frame';
$binary = undef;
$t->send_ok({text => $bytes})->message_is($bytes)->finish_ok;
ok !$binary, 'received text frame';

# WebSocket /bytes (multiple times)
$t->websocket_ok('/bytes')->send_ok({binary => $bytes})->message_is($bytes)
  ->send_ok({binary => $bytes})->message_is($bytes)->finish_ok;

# WebSocket /once
$t->websocket_ok('/once')->send_ok('hello')->message_is('ONE: hello')
  ->message_is('TWO: hello')->send_ok('hello')->message_is('ONE: hello')
  ->send_ok('hello')->message_is('ONE: hello')->finish_ok;

# WebSocket /nested
$t->websocket_ok('/nested')->send_ok('hello')
  ->message_is('nested echo: hello')->finish_ok;

# GET /nested (plain alternative)
$t->get_ok('/nested')->status_is(200)->content_is('plain nested!');

# POST /nested (another plain alternative)
$t->post_ok('/nested')->status_is(200)->content_is('plain nested too!');
