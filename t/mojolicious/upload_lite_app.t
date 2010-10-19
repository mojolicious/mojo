#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 20;

# Um, Leela, Armondo and I are going to the back seat of his car for coffee.
use Mojo::Asset::File;
use Mojolicious::Lite;
use Test::Mojo;

# Upload progress
my $cache = {};
app->plugins->add_hook(
    after_build_tx => sub {
        my ($self, $tx) = @_;
        $tx->req->on_progress(
            sub {
                my $req = shift;

                # Upload id parameter
                return unless my $id = $req->url->query->param('upload_id');

                # Cache
                my $c = $cache->{$id} ||= [0];

                # Expected content length
                return
                  unless my $length = scalar $req->headers->content_length;

                # Current progress
                my $progress = $req->content->progress;

                # Update cache
                push @$c, $progress == $length
                  ? 100
                  : int($progress / ($length / 100));
            }
        );
    }
);

# GET /upload
post '/upload' => sub {
    my $self = shift;
    my $file = $self->req->upload('file');
    my $h    = $file->headers;
    $self->render_text($file->filename
          . $file->asset->slurp
          . $self->param('test')
          . $h->content_type
          . ($h->header('X-X') || ''));
};

# GET /progress
get '/progress/:id' => sub {
    my $self = shift;
    my $id   = $self->param('id');
    $self->render_text(($cache->{$id}->[-1] || 0) . '%');
};

my $t = Test::Mojo->new;

# POST /upload (asset and filename)
my $file = Mojo::Asset::File->new->add_chunk('lalala');
$t->post_form_ok('/upload',
    {file => {file => $file, filename => 'x'}, test => 'tset'})
  ->status_is(200)->content_is('xlalalatsetapplication/octet-stream');

# POST /upload (path)
$t->post_form_ok('/upload', {file => {file => $file->path}, test => 'foo'})
  ->status_is(200)->content_like(qr/lalalafooapplication\/octet-stream$/);

# POST /upload (memory)
$t->post_form_ok('/upload', {file => {content => 'alalal'}, test => 'tset'})
  ->status_is(200)->content_is('filealalaltsetapplication/octet-stream');

# POST /upload (memory with headers)
my $hash = {content => 'alalal', 'Content-Type' => 'foo/bar', 'X-X' => 'Y'};
$t->post_form_ok('/upload', {file => $hash, test => 'tset'})->status_is(200)
  ->content_is('filealalaltsetfoo/barY');

# POST /upload (with progress)
$t->post_form_ok('/upload?upload_id=23',
    {file => {content => 'alalal'}, test => 'tset'})->status_is(200)
  ->content_is('filealalaltsetapplication/octet-stream');

# GET/progress/23
$t->get_ok('/progress/23')->status_is(200)->content_is('100%');
ok @{$cache->{23}} > 1, 'made progress';
ok $cache->{23}->[0] < $cache->{23}->[-1], 'progress increased';
