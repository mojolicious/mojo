#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;
plan skip_all => 'Windows is too fragile for this test!' if $^O eq 'MSWin32';
plan tests => 25;

# Um, Leela, Armondo and I are going to the back seat of his car for coffee.
use Mojo::Asset::File;
use Mojo::ByteStream 'b';
use Mojolicious::Lite;
use Test::Mojo;

# Upload progress
my $cache = {};
app->hook(
    after_build_tx => sub {
        my $tx = shift;
        $tx->req->on_progress(
            sub {
                my $req = shift;

                # Upload id parameter
                return unless my $id = $req->url->query->param('upload_id');

                # Cache
                my $c = $cache->{$id} ||= [0];

                # Expected content length
                return
                  unless my $length = $req->headers->content_length;

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

# POST /uploadlimit
post '/uploadlimit' => sub {
    my $self = shift;
    $self->rendered;
    my $body = $self->res->body || '';
    $self->res->body("called, $body");
    return if $self->req->is_limit_exceeded;
    if (my $u = $self->req->upload('Вячеслав')) {
        $self->res->body($self->res->body . $u->filename . $u->size);
    }
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

my $client = $t->client;

# POST /uploadlimit (huge upload without appropriate max message size)
my $backup = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 2048;
my $tx   = Mojo::Transaction::HTTP->new;
my $part = Mojo::Content::Single->new;
my $name = b('Вячеслав')->url_escape;
$part->headers->content_disposition(
    qq/form-data; name="$name"; filename="$name.jpg"/);
$part->headers->content_type('image/jpeg');
$part->asset->add_chunk('1234' x 1024);
my $content = Mojo::Content::MultiPart->new;
$content->headers($tx->req->headers);
$content->headers->content_type('multipart/form-data');
$content->parts([$part]);
$tx->req->method('POST');
$tx->req->url->parse('/uploadlimit');
$tx->req->content($content);
$client->start($tx);
is $tx->res->code, 413,        'right status';
is $tx->res->body, 'called, ', 'right content';
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;

# POST /uploadlimit (huge upload with appropriate max message size)
$backup = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1073741824;
$tx                         = Mojo::Transaction::HTTP->new;
$part                       = Mojo::Content::Single->new;
$name                       = b('Вячеслав')->url_escape;
$part->headers->content_disposition(
    qq/form-data; name="$name"; filename="$name.jpg"/);
$part->headers->content_type('image/jpeg');
$part->asset->add_chunk('1234' x 1024);
$content = Mojo::Content::MultiPart->new;
$content->headers($tx->req->headers);
$content->headers->content_type('multipart/form-data');
$content->parts([$part]);
$tx->req->method('POST');
$tx->req->url->parse('/uploadlimit');
$tx->req->content($content);
$client->start($tx);
ok $tx->is_done, 'transaction is done';
is $tx->res->code, 200, 'right status';
is b($tx->res->body)->decode('UTF-8')->to_string,
  'called, Вячеслав.jpg4096', 'right content';
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;
