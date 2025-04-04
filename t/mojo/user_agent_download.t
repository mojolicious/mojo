use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::File qw(tempdir);
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('trace')->unsubscribe('message');

get '/test1' => sub {
  my $c = shift;
  $c->res->headers->accept_ranges('bytes');
  return $c->render(data => 'CHUNK1CHUNK2CHUNK3');
};

get '/test2' => sub {
  my $c = shift;
  $c->res->headers->accept_ranges('bytes');
  return $c->render(data => 'CHUNK1CHUNK2CHUNK3') if $c->req->method eq 'HEAD';
  my $range = $c->req->headers->range;
  return $c->write('CHUNK1')->finish unless $range;
  return $c->write('CHUNK2')->finish if $range eq 'bytes=6-18';
  return $c->write('CHUNK3')->finish;
};

get '/test4' => sub {
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

my $dir = tempdir;
my $ua  = Mojo::UserAgent->new;

subtest 'Basic file download' => sub {
  my $file = $dir->child('test1a.txt');
  ok $ua->download('/test1', $file), 'file downloaded';
  ok -e $file,                       'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'File already downloaded' => sub {
  my $file = $dir->child('test1a.txt');
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
  ok $ua->download('/test1', $file), 'file downloaded';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'Basic file download (non-blocking)' => sub {
  my $file = $dir->child('test1b.txt');
  my $result;
  $ua->download_p('/test1', $file)->then(sub { $result = shift })->wait;
  ok $result,  'file downloaded';
  ok -e $file, 'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'Exsiting file is larger' => sub {
  my $file = $dir->child('test1c.txt')->spew('CHUNK1CHUNK2CHUNK3CHUNK4');
  eval { $ua->download('/test1', $file) };
  like $@, qr/Download error: File size mismatch/, 'right error';
};

subtest 'Resumed file download' => sub {
  my $file = $dir->child('test2a.txt');
  ok !$ua->download('/test2', $file), 'file partially downloaded';
  ok !$ua->download('/test2', $file), 'file continued';
  ok $ua->download('/test2',  $file), 'file downloaded';
  ok -e $file, 'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3', 'right content';
};

subtest 'Missing file' => sub {
  my $file = $dir->child('test3a.txt');
  eval { $ua->download('/test3', $file) };
  like $@, qr/404 response: Not Found/, 'file not found';
};

subtest 'Missing file (non-blocking)' => sub {
  my $file = $dir->child('test3b.txt');
  my $err;
  $ua->download_p('/test3', $file)->catch(sub { $err = shift })->wait;
  like $err, qr/404 response: Not Found/, 'file not found';
};

subtest 'File of unknown size' => sub {
  my $file = $dir->child('test4a.txt')->spew('C');
  eval { $ua->download('/test4', $file) };
  like $@, qr/Download error: Unknown file size/, 'right error';
};

subtest 'File of unknown size (non-blocking)' => sub {
  my $file = $dir->child('test4b.txt')->spew('C');
  my $err;
  $ua->download_p('/test4', $file)->catch(sub { $err = shift })->wait;
  like $err, qr/Download error: Unknown file size/, 'right error';
};

subtest 'File of unknown size downloaded' => sub {
  my $file = $dir->child('test4c.txt');
  ok $ua->download('/test4', $file), 'file downloaded';
  ok -e $file,                       'file exists';
  is $file->slurp, 'CHUNK1CHUNK2CHUNK3CHUNK4', 'right content';
};

done_testing();
