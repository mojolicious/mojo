use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::Asset::File;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojolicious::Lite;
use Test::Mojo;

post '/upload' => sub {
  my $c       = shift;
  my $file    = $c->param('file');
  my $headers = $file->headers;
  $c->render(text => $file->filename
      . $file->asset->slurp
      . $c->param('test')
      . ($headers->content_type  // '')
      . ($headers->header('X-X') // '')
      . join(',', $c->param));
};

post '/multi' => sub {
  my $c = shift;
  my @uploads = map { @{$c->every_param($_)} } @{$c->every_param('name')};
  $c->render(text => join '', map { $_->filename, $_->asset->slurp } @uploads);
};

my $t = Test::Mojo->new;

# Asset and filename
my $file = Mojo::Asset::File->new->add_chunk('lalala');
$t->post_ok('/upload' => form =>
    {file => {file => $file, filename => 'x'}, test => 'tset'})
  ->status_is(200)->content_is('xlalalatsetfile,test');

# Path
$t->post_ok(
  '/upload' => form => {file => {file => $file->path}, test => 'foo'})
  ->status_is(200)->content_like(qr!lalalafoofile,test$!);

# Memory
$t->post_ok(
  '/upload' => form => {file => {content => 'alalal'}, test => 'tset'})
  ->status_is(200)->content_is('filealalaltsetfile,test');

# Memory with headers
my $hash = {content => 'alalal', 'Content-Type' => 'foo/bar', 'X-X' => 'Y'};
$t->post_ok('/upload' => form => {file => $hash, test => 'tset'})
  ->status_is(200)->content_is('filealalaltsetfoo/barYfile,test');

# Multiple file uploads
$t->post_ok('/multi?name=file1&name=file2' => form =>
    {file1 => {content => '1111'}, file2 => {content => '11112222'}})
  ->status_is(200)->content_is('file11111file211112222');

# Multiple file uploads reverse
$t->post_ok('/multi?name=file2&name=file1' => form =>
    {file1 => {content => '1111'}, file2 => {content => '11112222'}})
  ->status_is(200)->content_is('file211112222file11111');

# Multiple file uploads with same name
$t->post_ok(
  '/multi?name=file' => form => {
    file => [
      {content => 'just',  filename => 'one.txt'},
      {content => 'works', filename => 'two.txt'}
    ]
  }
)->status_is(200)->content_is('one.txtjusttwo.txtworks');

done_testing();
