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
use Test::More tests => 15;

use Mojolicious::Lite;
use Scalar::Util 'weaken';
use Test::Mojo;

app->hook(
  after_build_tx => sub {
    my $tx = shift;
    weaken $tx;
    $tx->req->on_progress(
      sub {
        my $req = shift;

        # Check if we've reached the body yet
        return unless $req->content->is_parsing_body;

        # Trigger early request for everything under "/upload"
        $tx->on_request->($tx) if $req->url->path->contains('/upload');
      }
    );
  }
);

# POST /upload
my $cache = {};
post '/upload' => sub {
  my $self = shift;

  # First invocation, prepare streaming
  my $id = $self->param('id');
  $self->req->body(sub { $cache->{$id} .= pop });
  return unless $self->req->on_progress(undef)->is_done;

  # Second invocation, render response
  $self->render(data => $cache->{$id});
};

# GET /download
get '/download' => sub {
  my $self = shift;
  $self->render(data => $cache->{$self->param('id')});
};

my $t = Test::Mojo->new;

# POST /upload (small upload)
$t->post_ok('/upload?id=23' => 'whatever')->status_is(200)
  ->content_is('whatever');

# GET /download (small download)
$t->get_ok('/download?id=23')->status_is(200)->content_is('whatever');

# POST /upload (big upload)
$t->post_ok('/upload?id=24' => '1234' x 131072)->status_is(200)
  ->content_is('1234' x 131072);

# GET /download (big download)
$t->get_ok('/download?id=24')->status_is(200)->content_is('1234' x 131072);

# GET /download (small download again)
$t->get_ok('/download?id=23')->status_is(200)->content_is('whatever');
