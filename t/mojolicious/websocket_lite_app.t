#!/usr/bin/env perl
use Mojo::Base -strict;

# "Oh, dear. She’s stuck in an infinite loop and he’s an idiot.
#  Well, that’s love for you."
use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 78;

use Mojo::ByteStream 'b';
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

# GET /echo
get '/echo' => {text => 'plain echo!'};

# GET /plain
get '/plain' => {text => 'Nothing to see here!'};

# WebSocket /push
websocket '/push' => sub {
  my $self = shift;
  my $id =
    Mojo::IOLoop->recurring('0.5' => sub { $self->send_message('push') });
  $self->on_finish(sub { Mojo::IOLoop->drop($id) });
};

# WebSocket /unicode
websocket '/unicode' => sub {
  my $self = shift;
  $self->on_message(
    sub {
      my ($self, $message) = @_;
      $self->send_message("♥: $message");
    }
  );
};

# WebSocket /bytes
websocket '/bytes' => sub {
  my $self = shift;
  $self->on_message(
    sub {
      my ($self, $message) = @_;
      $self->send_message([$message]);
    }
  );
};

# /nested
under '/nested';

# WebSocket /nested
websocket sub {
  my $self = shift;
  $self->on_message(
    sub {
      my ($self, $message) = @_;
      $self->send_message("nested echo: $message");
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

# WebSocket /echo
$t->websocket_ok('/echo')->send_message_ok('hello')->message_is('echo: hello')
  ->finish_ok;

# WebSocket /echo (multiple times)
$t->websocket_ok('/echo')->send_message_ok('hello again')
  ->message_is('echo: hello again')->send_message_ok('and one more time')
  ->message_is('echo: and one more time')->finish_ok;

# WebSocket /echo (zero)
$t->websocket_ok('/echo')->send_message_ok(0)->message_is('echo: 0')
  ->finish_ok;

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
$t->websocket_ok('/echo')->send_message_ok('hello')->message_is('echo: hello')
  ->finish_ok;

# WebSocket /echo (mixed)
$t->websocket_ok('/echo')->send_message_ok('this')->send_message_ok('just')
  ->send_message_ok('works')->message_is('echo: this')
  ->message_is('echo: just')->message_is('echo: works')->finish_ok;

# GET /plain (and again)
$t->get_ok('/plain')->status_is(200)->content_is('Nothing to see here!');

# WebSocket /unicode
$t->websocket_ok('/unicode')->send_message_ok('hello')
  ->message_is('♥: hello')->finish_ok;

# WebSocket /unicode (multiple times)
$t->websocket_ok('/unicode')->send_message_ok('hello again')
  ->message_is('♥: hello again')->send_message_ok('and one ☃ more time')
  ->message_is('♥: and one ☃ more time')->finish_ok;

# WebSocket /bytes
my $bytes = b("I ♥ Mojolicious")->encode('UTF-16LE')->to_string;
$t->websocket_ok('/bytes')->send_message_ok([$bytes])->message_is($bytes)
  ->finish_ok;

# WebSocket /bytes (multiple times)
$t->websocket_ok('/bytes')->send_message_ok([$bytes])->message_is($bytes)
  ->send_message_ok([$bytes])->message_is($bytes)->finish_ok;

# WebSocket /nested
$t->websocket_ok('/nested')->send_message_ok('hello')
  ->message_is('nested echo: hello')->finish_ok;

# GET /nested (plain alternative)
$t->get_ok('/nested')->status_is(200)->content_is('plain nested!');

# POST /nested (another plain alternative)
$t->post_ok('/nested')->status_is(200)->content_is('plain nested too!');
