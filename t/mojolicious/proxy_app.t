use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Test::Mojo;

use Mojo::Server::Daemon;
use Mojo::URL;
use Mojolicious;
use Mojolicious::Lite;

# Test server with various response variants
my $app    = Mojolicious->new;
my $daemon = Mojo::Server::Daemon->new(listen => ['http://127.0.0.1'], silent => 1, app => $app);
my $port   = $daemon->start->ports->[0];
my $url    = Mojo::URL->new("http://127.0.0.1:$port");
my $r      = $app->routes;
$r->get(
  '/size/:code/:length' => {code => 204, length => 0} => sub {
    my $c      = shift;
    my $code   = $c->param('code');
    my $length = $c->param('length');
    $c->res->headers->header('X-Mojo-App' => 'Size');
    $c->render(data => 'x' x $length, status => $code);
  }
)->name('size');
$r->get(
  '/redirect/:code1/:code2/:length' => {code1 => 302, code2 => 204, length => 0} => sub {
    my $c      = shift;
    my $code1  = $c->param('code1');
    my $code2  = $c->param('code2');
    my $length = $c->param('length');
    $c->res->headers->header('X-Mojo-App' => 'Redirect');
    $c->res->code($code1);
    $c->redirect_to($c->url_for('size', {code => $code2, length => $length})->to_abs);
  }
)->name('redirect');
$r->get(
  '/res1' => sub {
    my $c = shift;
    $c->res->headers->header('X-Mojo-App' => 'One');
    $c->render(data => 'One!');
  }
);
$r->get(
  '/res2' => sub {
    my $c = shift;
    $c->res->headers->header('X-Mojo-App' => 'Two');
    $c->write('Tw');
    $c->write('o!');
    $c->write('');
  }
);
$r->any(
  '/res3' => sub {
    my $c = shift;
    $c->res->headers->header('X-Mojo-App'    => 'Three');
    $c->res->headers->header('X-Mojo-Method' => $c->req->method);
    $c->res->headers->header('X-Mojo-More'   => $c->req->headers->header('X-Mojo-More') // '');
    $c->res->headers->header('X-Mojo-Body'   => length $c->req->body);
    $c->write_chunk('Th');
    $c->write_chunk('ree!');
    $c->write_chunk('');
  }
);
$r->get(
  '/res4' => sub {
    my $c = shift;
    $c->res->headers->header('X-Mojo-App' => 'Four');
    $c->render(data => '', status => 204);
  }
);
$r->get(
  '/res5' => sub {
    my $c = shift;
    Mojo::IOLoop->stream($c->tx->connection)->close;
  }
);
$r->get(
  '/res6' => sub {
    my $c = shift;
    $c->res->headers->content_length(4);
    $c->write;
    Mojo::IOLoop->timer(0.1 => sub { $c->write("Six!") });
  }
);

get '/proxy1/*target' => sub {
  my $c      = shift;
  my $target = $c->stash('target');
  $c->proxy->get_p($url->clone->path($target))->catch(sub {
    my $err = shift;
    $c->render(text => "Error: $err", status => 400);
  });
};

patch '/proxy2/*target' => sub {
  my $c      = shift;
  my $target = $c->stash('target');
  $c->proxy->post_p($url->path($target), {'X-Mojo-More' => 'Less'}, 'Hello!');
};

get '/proxy3/:method/*target' => sub {
  my $c = shift;

  my $method = $c->stash('method');
  my $target = $c->stash('target');

  my $tx = $c->ua->build_tx($method, $url->path($target));
  $c->proxy->start_p($tx);

  $tx->res->content->once(
    body => sub {
      $c->res->headers->remove('X-Mojo-App');
      $c->res->headers->header('X-Mojo-Proxy1' => 'just');
      $c->res->headers->header('X-Mojo-Proxy2' => 'works!');
    }
  );
};

my $t = Test::Mojo->new;

subtest 'Various response variants' => sub {
  $t->get_ok('/proxy1/size/200/2')->status_is(200)->header_is('X-Mojo-App' => 'Size')->header_is('Content-Length' => 2)
    ->content_is('xx');
  $t->get_ok('/proxy1/size/200/1')->status_is(200)->header_is('X-Mojo-App' => 'Size')->header_is('Content-Length' => 1)
    ->content_is('x');
  $t->get_ok('/proxy1/size/200/0')->status_is(200)->header_is('X-Mojo-App' => 'Size')->header_is('Content-Length' => 0)
    ->content_is('');
  $t->get_ok('/proxy1/size/204/0')->status_is(204)->header_is('X-Mojo-App' => 'Size')
    ->header_is('Content-Length' => undef)->content_is('');
  $t->get_ok('/proxy1/redirect/304/200/1')->status_is(304)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => undef)->content_is('');
  $t->get_ok('/proxy1/redirect/302/200/1')->status_is(302)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => 0)->content_is('');
  $t->get_ok('/proxy1/redirect/301/200/1')->status_is(301)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => 0)->content_is('');
  $t->get_ok('/proxy1/redirect/304/200/0')->status_is(304)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => undef)->content_is('');
  $t->get_ok('/proxy1/redirect/302/200/0')->status_is(302)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => 0)->content_is('');
  $t->get_ok('/proxy1/redirect/301/200/0')->status_is(301)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => 0)->content_is('');
  $t->get_ok('/proxy1/redirect/304/204/0')->status_is(304)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => undef)->content_is('');
  $t->get_ok('/proxy1/redirect/302/204/0')->status_is(302)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => 0)->content_is('');
  $t->get_ok('/proxy1/redirect/301/204/0')->status_is(301)->header_is('X-Mojo-App' => 'Redirect')
    ->header_is('Content-Length' => 0)->content_is('');
  $t->get_ok('/proxy1/res1')->status_is(200)->header_is('X-Mojo-App' => 'One')->content_is('One!');
  $t->get_ok('/proxy1/res2')->status_is(200)->header_is('X-Mojo-App' => 'Two')->content_is('Two!');
  $t->get_ok('/proxy1/res3')->status_is(200)->header_is('X-Mojo-App' => 'Three')->header_is('X-Mojo-Method' => 'GET')
    ->header_is('X-Mojo-More' => '')->header_is('X-Mojo-Body' => 0)->content_is('Three!');
  $t->get_ok('/proxy1/res4')->status_is(204)->header_is('X-Mojo-App' => 'Four')->content_is('');
  $t->get_ok('/proxy1/res5')->status_is(400)->content_like(qr/Error: /);
  $t->get_ok('/proxy1/res6')->status_is(200)->content_is('Six!');
};

subtest 'Custom request' => sub {
  $t->patch_ok('/proxy2/res3')->status_is(200)->header_is('X-Mojo-App' => 'Three')
    ->header_is('X-Mojo-Method' => 'POST')->header_is('X-Mojo-More' => 'Less')->header_is('X-Mojo-Body' => 6)
    ->content_is('Three!');
};

subtest 'Response modification' => sub {
  $t->get_ok('/proxy3/GET/res1')->status_is(200)->header_exists_not('X-Mojo-App')->header_is('X-Mojo-Proxy1' => 'just')
    ->header_is('X-Mojo-Proxy2' => 'works!')->content_is('One!');
  $t->get_ok('/proxy3/POST/res3')->status_is(200)->header_is('X-Mojo-Method' => 'POST')
    ->header_exists_not('X-Mojo-App')->header_is('X-Mojo-Proxy1' => 'just')->header_is('X-Mojo-Proxy2' => 'works!')
    ->content_is('Three!');
};

done_testing();
