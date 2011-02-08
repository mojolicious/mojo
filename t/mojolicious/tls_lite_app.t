#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More;
use Mojo::IOLoop;
use Mojo::Cookie::Response;
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::TLS;
plan skip_all => 'Windows is too fragile for this test!'
  if Mojo::IOLoop::WINDOWS;
plan tests => 5;

# Homer: Look at these low, low prices on famous brand-name electronics!
# Bart:  Don't be a sap, Dad. These are just crappy knockoffs.
# Homer: Pfft. I know a genuine Panaphonics when I see it. And look,
#        there's a Magnetbox and Sorny.
use Mojo::Client;
use Mojo::Server::Daemon;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');
app->sessions->secure(1);

# GET /
get '/' => sub {
  my $self = shift;
  my $rel  = $self->req->url;
  my $abs  = $rel->to_abs;
  $self->render_text("Hello World! $rel $abs");
};

get '/cookie' => sub {
  my $self = shift;
  $self->session(foo => 42);
  $self->render_text("Here, have a cookie");
};

# HTTP server for testing
my $client = Mojo::Client->new;
my $loop   = $client->ioloop;
my $server = Mojo::Server::Daemon->new(app => app, ioloop => $loop);
my $port   = Mojo::IOLoop->new->generate_port;
$server->listen(["https://*:$port"]);
$server->prepare_ioloop;

# GET / (normal request)
is $client->get("https://localhost:$port/")->success->body,
  "Hello World! / https://localhost:$port/", 'right content';

# GET /cookie (to test secure flag)
my $res = $client->get("https://localhost:$port/cookie")->success;
ok defined $res, 'got response';
is $res->body, "Here, have a cookie", 'right content';
my $c = $res->cookies;
is @$c, 1, 'got a cookie';
ok $c->[0]->secure, 'cookie is secure';
