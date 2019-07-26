use Mojo::Base -strict;

use Test::More;
use Mojo::Util;
use Mojolicious;

BEGIN {
  plan skip_all => 'IO::Compress::Brotli 0.004001+ required for this test!'
    unless Mojo::Util->IO_COMPRESS_BROTLI;
}

my $app      = Mojolicious->new(secrets => ['works']);
my $renderer = $app->renderer->default_format('test');
my $output   = 'a' x 1000;

$app->log->level('fatal');
$renderer->compress(1);

# Brotli Compression (enabled)
my $c = $app->build_controller;
$c->req->headers->accept_encoding('br');
$renderer->respond($c, $output, 'html');
is $c->res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
is $c->res->headers->vary, 'Accept-Encoding', 'right "Vary" value';
is $c->res->headers->content_encoding, 'br', 'right "Content-Encoding" value';
isnt $c->res->body, $output, 'different string';
is Mojo::Util::unbro($c->res->body, 1_000), $output, 'same string';

# Brotli Compression (precedence)
$c = $app->build_controller;
$c->req->headers->accept_encoding('gzip, deflate, br');
$renderer->respond($c, $output, 'html');
is $c->res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
is $c->res->headers->vary, 'Accept-Encoding', 'right "Vary" value';
is $c->res->headers->content_encoding, 'br', 'right "Content-Encoding" value';
isnt $c->res->body, $output, 'different string';
is Mojo::Util::unbro($c->res->body, 1_000), $output, 'same string';

done_testing();
