use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

helper steps => sub {
  my ($c, $cb) = @_;
  $c->render_steps(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub {
      $c->stash(text => 'helper', steps => 'action');
      Mojo::IOLoop->next_tick($cb);
    }
  );
};

get '/steps' => sub {
  my $c = shift;
  $c->render_steps(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub { shift->pass('three steps') },
    sub { $c->render(data => pop) unless $c->param('auto') }
  );
};

get '/nested' => sub {
  my $c = shift;
  $c->render_steps(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub { $c->steps(shift->begin) },
    sub { $c->stash(text => $c->stash('steps')) }
  );
};

my $early;
get '/early' => sub {
  my $c = shift;
  $c->render_steps(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub {
      Mojo::IOLoop->next_tick(shift->begin);
      $c->render(text => 'second');
      $c->res->headers->header('X-Next' => 'third');
    },
    sub { $early = $c->res->headers->header('X-Next') }
  );
};

get '/not_found' => sub {
  my $c = shift;
  $c->render_steps(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub { $c->stash(template => 'does_not_exist') }
  );
};

get '/exception' => sub {
  my $c = shift;
  $c->render_steps(
    sub { Mojo::IOLoop->next_tick(shift->begin) },
    sub { die 'Intentional error' },
    sub { $c->render(text => 'fail') }
  );
};

my $t = Test::Mojo->new;

# Event loop is automatically started
my $c = app->build_controller;
$c->steps(sub { });
is $c->res->body, 'helper', 'right content';

# Three steps with manual rendering
$t->get_ok('/steps')->status_is(200)->content_is('three steps');

# Three steps with template
$t->get_ok('/steps?auto=1')->status_is(200)
  ->content_is("three steps (template)\n");

# Nested steps
$t->get_ok('/nested')->status_is(200)->content_is('action');

# Transaction is available after rendering early
$t->get_ok('/early')->status_is(200)->content_is('second');
Mojo::IOLoop->one_tick until $early;
is $early, 'third', 'right result';

# Template not found
$t->get_ok('/not_found')->status_is(404);

# Exception in step
$t->get_ok('/exception')->status_is(500)->content_like(qr/Intentional error/);

done_testing();

__DATA__
@@ steps.html.ep
three steps (template)
