use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::File qw(tempdir);
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('trace')->unsubscribe('message');

get '/simple' => sub {
  my $c = shift;
  $c->res->headers->accept_ranges('bytes');
  return $c->render(data => 'CHUNK1CHUNK2CHUNK3');
};

get '/redirect' => sub {
  my $c = shift;
  return $c->redirect_to('/simple');
};

get '/resume' => sub {
  my $c = shift;
  $c->res->headers->accept_ranges('bytes');
  return $c->render(data => 'CHUNK1CHUNK2CHUNK3') if $c->req->method eq 'HEAD';
  my $range = $c->req->headers->range;
  return $c->write('CHUNK1')->finish unless $range;
  return $c->write('CHUNK2')->finish if $range eq 'bytes=6-18';
  return $c->write('CHUNK3')->finish;
};

get '/stream' => sub {
  my $c      = shift;
  my $chunks = [qw(CHUNK1 CHUNK2 CHUNK3 CHUNK4)];
  $c->res->code(200);
  $c->res->headers->content_type('text/plain');
  my $cb = sub {
    my $content = shift;
    my $chunk   = shift @$chunks || '';
    $content->write_chunk($chunk, $chunk ? __SUB__ : undef);
  };
  $c->res->content->$cb;
  $c->rendered;
};

get '/header' => sub {
  my $c      = shift;
  my $custom = $c->req->headers->header('X-Custom-Header') || 'MISSINGHEADER';
  $c->res->headers->accept_ranges('bytes');
  return $c->render(data => $custom);
};

my $dir = tempdir;
my $ua  = Mojo::UserAgent->new;

subtest 'Basic file download' => sub {
  my $file = $dir->child('simple1.txt');
  ok $file->download('/simple'), 'file downloaded';
  ok -e $file,                   'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'File already downloaded' => sub {
  my $file = $dir->child('simple1.txt');
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
  ok $file->download('/simple'), 'file downloaded';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'Basic file download (custom header)' => sub {
  my $file = $dir->child('header1.txt');
  ok $file->download('/header', {headers => {'X-Custom-Header' => 'CORRECTFILECONTENT'}}), 'file downloaded';
  ok -e $file,                                                                             'file exists';
  is $file->slurp, 'CORRECTFILECONTENT', 'right content';

  my $file2 = $dir->child('header2.txt');
  ok $file2->download('/header'), 'file downloaded';
  ok -e $file2,                   'file exists';
  is $file2->slurp, 'MISSINGHEADER', 'right content';
};

subtest 'Basic file download (redirect)' => sub {
  my $file = $dir->child('redirect1.txt');
  ok $file->download('/redirect'), 'file downloaded';
  ok -e $file,                     'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';

  my $ua2   = Mojo::UserAgent->new(max_redirects => 0);
  my $file2 = $dir->child('redirect2.txt');
  ok $file2->download('/redirect', {ua => $ua2}), 'file downloaded';
  ok -e $file2,                                   'file exists';
  is $file2->slurp, '', 'right content';
};

subtest 'Existing file is larger' => sub {
  my $file = $dir->child('simple2.txt')->spew('CHUNK1CHUNK2CHUNK3CHUNK4');
  eval { $file->download('/simple') };
  like $@, qr/Download error: File size mismatch/, 'right error';
};

subtest 'Resumed file download' => sub {
  my $file = $dir->child('resume1.txt');
  ok !$file->download('/resume'), 'file partially downloaded';
  ok !$file->download('/resume'), 'file continued';
  ok $file->download('/resume'),  'file downloaded';
  ok -e $file,                    'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'Missing file' => sub {
  my $file = $dir->child('missing1.txt');
  eval { $file->download('/missing') };
  like $@, qr/404 response: Not Found/, 'file not found';
};

subtest 'File of unknown size' => sub {
  my $file = $dir->child('stream1.txt')->spew('C');
  eval { $file->download('/stream') };
  like $@, qr/Download error: Unknown file size/, 'right error';
};

subtest 'File of unknown size downloaded' => sub {
  my $file = $dir->child('stream2.txt');
  ok $file->download('/stream'), 'file downloaded';
  ok -e $file,                   'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3CHUNK4', 'right content';
};

done_testing();
