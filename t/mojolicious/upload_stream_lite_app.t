#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

# "On the count of three, you will awaken feeling refreshed,
#  as if Futurama had never been canceled by idiots,
#  then brought back by bigger idiots. One. Two."
use Test::More tests => 6;

use Mojolicious::Lite;
use Test::Mojo;

# Stream uploads into cache
my $cache = {};
app->hook(
  after_build_tx => sub {
    shift->req->on_progress(
      sub {
        my $req = shift;

        # Check if we've reached the body yet
        return unless $req->content->is_parsing_body;

        # Check if we are already streaming
        return unless my $id = $req->url->query->param('id');
        return if exists $cache->{$id};

        # Use body callback for streaming
        $req->body(sub { $cache->{$id} .= pop });
      }
    );
  }
);

# POST /upload_stream
post '/upload_stream' => sub {
  my $self = shift;
  $self->render(data => $cache->{$self->param('id')});
};

my $t = Test::Mojo->new;

# POST /upload_stream
$t->post_ok('/upload_stream?id=23' => 'whatever')->status_is(200)
  ->content_is('whatever');

# POST /upload_stream (big content)
$t->post_ok('/upload_stream?id=24' => '1234' x 131072)->status_is(200)
  ->content_is('1234' x 131072);
