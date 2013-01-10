use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::Asset::File;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojolicious::Lite;
use Test::Mojo;

# POST /upload
post '/upload' => sub {
  my $self    = shift;
  my $file    = $self->param('file');
  my $headers = $file->headers;
  $self->render_text($file->filename
      . $file->asset->slurp
      . $self->param('test')
      . ($headers->content_type  || '')
      . ($headers->header('X-X') || '')
      . join(',', $self->param));
};

# POST /multi
post '/multi' => sub {
  my $self = shift;
  my @uploads = map { $self->param($_) } $self->param('name');
  $self->render_text(join '', map { $_->filename, $_->asset->slurp } @uploads);
};

my $t = Test::Mojo->new;

# POST /upload (asset and filename)
my $file = Mojo::Asset::File->new->add_chunk('lalala');
$t->post_form_ok(
  '/upload' => {file => {file => $file, filename => 'x'}, test => 'tset'})
  ->status_is(200)->content_is('xlalalatsetfile,test');

# POST /upload (path)
$t->post_form_ok('/upload' => {file => {file => $file->path}, test => 'foo'})
  ->status_is(200)->content_like(qr!lalalafoofile,test$!);

# POST /upload (memory)
$t->post_form_ok('/upload' => {file => {content => 'alalal'}, test => 'tset'})
  ->status_is(200)->content_is('filealalaltsetfile,test');

# POST /upload (memory with headers)
my $hash = {content => 'alalal', 'Content-Type' => 'foo/bar', 'X-X' => 'Y'};
$t->post_form_ok('/upload' => {file => $hash, test => 'tset'})->status_is(200)
  ->content_is('filealalaltsetfoo/barYfile,test');

# POST /multi
$t->post_form_ok('/multi?name=file1&name=file2',
  {file1 => {content => '1111'}, file2 => {content => '11112222'}})
  ->status_is(200)->content_is('file11111file211112222');

# POST /multi (reverse)
$t->post_form_ok('/multi?name=file2&name=file1',
  {file1 => {content => '1111'}, file2 => {content => '11112222'}})
  ->status_is(200)->content_is('file211112222file11111');

# POST /multi (multiple file uploads with same name)
$t->post_form_ok(
  '/multi?name=file' => {
    file => [
      {content => 'just',  filename => 'one.txt'},
      {content => 'works', filename => 'two.txt'}
    ]
  }
)->status_is(200)->content_is('one.txtjusttwo.txtworks');

done_testing();
