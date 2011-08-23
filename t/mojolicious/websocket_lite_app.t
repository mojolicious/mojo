#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

# "Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
#  Well, that’s love for you."
use Test::More tests => 41;

# "Your mistletoe is no match for my *tow* missile."
use Mojolicious::Lite;
use Test::Mojo;

# WebSocket /echo
websocket '/echo' => sub {
  my $self = shift;
  $self->on_message(
    sub {
      my ($self, $message) = @_;
      $self->send_message("echo: $message");
    }
  );
};

# GET /plain
get '/plain' => {text => 'Nothing to see here!'};

# WebSocket /push
websocket '/push' => sub {
  my $self = shift;
  my $id =
    Mojo::IOLoop->recurring('0.5' => sub { $self->send_message('push') });
  $self->on_finish(sub { Mojo::IOLoop->drop($id) });
};

# "I was a hero to broken robots 'cause I was one of them, but how can I sing
#  about being damaged if I'm not?
#  That's like Christina Aguilera singing Spanish.
#  Ooh, wait! That's it! I'll fake it!"
my $t = Test::Mojo->new;

# WebSocket /echo
$t->websocket_ok('/echo')->send_message_ok('hello')->message_is('echo: hello')
  ->finish_ok;

# WebSocket /echo (multiple times)
$t->websocket_ok('/echo')->send_message_ok('hello again')
  ->message_is('echo: hello again')->send_message_ok('and one more time')
  ->message_is('echo: and one more time')->finish_ok;

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
$t->websocket_ok('/echo')->send_message_ok('hello')->message_is('echo: hello')
  ->finish_ok;

# WebSocket /echo (mixed)
$t->websocket_ok('/echo')->send_message_ok('this')->send_message_ok('just')
  ->send_message_ok('works')->message_is('echo: this')
  ->message_is('echo: just')->message_is('echo: works')->finish_ok;

# GET /plain (and again)
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');
