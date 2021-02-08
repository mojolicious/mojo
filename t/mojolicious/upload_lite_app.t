use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;
use Mojo::Asset::File;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojolicious::Lite;

get '/request_size' => sub {
  my $c = shift;
  $c->render(text => $c->req->max_message_size);
};

post '/upload' => sub {
  my $c       = shift;
  my $file    = $c->param('file');
  my $headers = $file->headers;
  $c->render(text => $file->filename
      . $file->asset->slurp
      . $c->param('test')
      . ($headers->content_type  // '')
      . ($headers->header('X-X') // ''));
};

post '/multi' => sub {
  my $c       = shift;
  my @uploads = map { @{$c->every_param($_)} } @{$c->every_param('name')};
  $c->render(text => join '', map { $_->filename, $_->asset->slurp } @uploads);
};

my $t = Test::Mojo->new;

subtest 'Request size limit' => sub {
  $t->get_ok('/request_size')->status_is(200)->content_is(16777216);
  $t->app->max_request_size(0);
  $t->get_ok('/request_size')->status_is(200)->content_is(0);
};

subtest 'Asset and filename' => sub {
  my $file = Mojo::Asset::File->new->add_chunk('lalala');
  $t->post_ok('/upload' => form => {file => {file => $file, filename => 'x'}, test => 'tset'})->status_is(200)
    ->content_is('xlalalatset');
};

subtest 'Path' => sub {
  my $file = Mojo::Asset::File->new->add_chunk('lalala');
  $t->post_ok('/upload' => form => {file => {file => $file->path}, test => 'foo'})->status_is(200)
    ->content_like(qr!lalalafoo$!);
};

subtest 'Memory' => sub {
  $t->post_ok('/upload' => form => {file => {content => 'alalal'}, test => 'tset'})->status_is(200)
    ->content_is('filealalaltset');
};

subtest 'Memory with headers' => sub {
  my $hash = {content => 'alalal', 'Content-Type' => 'foo/bar', 'X-X' => 'Y'};
  $t->post_ok('/upload' => form => {file => $hash, test => 'tset'})->status_is(200)
    ->content_is('filealalaltsetfoo/barY');
};

subtest 'Multiple file uploads' => sub {
  $t->post_ok(
    '/multi?name=file1&name=file2' => form => {file1 => {content => '1111'}, file2 => {content => '11112222'}})
    ->status_is(200)->content_is('file11111file211112222');
};

subtest 'Multiple file uploads reverse' => sub {
  $t->post_ok(
    '/multi?name=file2&name=file1' => form => {file1 => {content => '1111'}, file2 => {content => '11112222'}})
    ->status_is(200)->content_is('file211112222file11111');
};

subtest 'Multiple file uploads with same name' => sub {
  $t->post_ok('/multi?name=file' => form =>
      {file => [{content => 'just', filename => 'one.txt'}, {content => 'works', filename => 'two.txt'}]})
    ->status_is(200)->content_is('one.txtjusttwo.txtworks');
};

done_testing();
