use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 18;

use Mojo::Asset::File;
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

# POST /multi_reverse
post '/multi_reverse' => sub {
  my $self  = shift;
  my $file2 = $self->param('file2');
  my $file1 = $self->param('file1');
  $self->render_text($file1->filename
      . $file1->asset->slurp
      . $file2->filename
      . $file2->asset->slurp);
};

# POST /multi
post '/multi' => sub {
  my $self  = shift;
  my $file1 = $self->param('file1');
  my $file2 = $self->param('file2');
  $self->render_text($file1->filename
      . $file1->asset->slurp
      . $file2->filename
      . $file2->asset->slurp);
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

# POST /multi_reverse
$t->post_form_ok('/multi_reverse',
  {file1 => {content => '1111'}, file2 => {content => '11112222'},})
  ->status_is(200)->content_is('file11111file211112222');

# POST /multi
$t->post_form_ok('/multi',
  {file1 => {content => '1111'}, file2 => {content => '11112222'},})
  ->status_is(200)->content_is('file11111file211112222');
