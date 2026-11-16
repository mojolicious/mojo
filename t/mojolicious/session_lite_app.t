use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;

use Mojo::Util;
use Mojolicious::Lite;

app->secrets(['test1']);

get '/login' => sub {
  my $c = shift;
  $c->session(user => 'sri');
  $c->render(text => 'logged in');
};

get '/session' => sub {
  my $c    = shift;
  my $user = $c->session->{user} // 'nobody';
  $c->render(text => "user:$user");
};

get '/logout' => sub {
  my $c = shift;
  delete $c->session->{user};
  $c->render(text => 'logged out');
};

my $t = Test::Mojo->new;

subtest 'User session (signed cookie)' => sub {
  is $t->app->sessions->encrypted, undef, 'not encrypted by default';
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  $t->get_ok('/login')->status_is(200)->content_is('logged in');
  $t->get_ok('/session')->status_is(200)->content_is('user:sri');
  like $t->tx->res->cookies->[0]->value, qr/^[^-]+-+[^-]+$/, 'signed cookie format';
  $t->get_ok('/session')->status_is(200)->content_is('user:sri');
  $t->get_ok('/logout')->status_is(200)->content_is('logged out');
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
};

subtest 'User session (encrypted cookie)' => sub {
  plan skip_all => 'CryptX required!' unless Mojo::Util->CRYPTX;
  $t->reset_session;
  $t->app->sessions->encrypted(1);
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  $t->get_ok('/login')->status_is(200)->content_is('logged in');
  $t->get_ok('/session')->status_is(200)->content_is('user:sri');
  like $t->tx->res->cookies->[0]->value, qr/^[^-]+-[^-]+-[^-]+$/, 'encrypted cookie format';
  $t->get_ok('/session')->status_is(200)->content_is('user:sri');
  $t->get_ok('/logout')->status_is(200)->content_is('logged out');
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
};

subtest 'Rotating secrets' => sub {
  subtest 'User session (signed cookie)' => sub {
    $t->reset_session;
    $t->app->secrets(['test1']);
    $t->app->sessions->encrypted(0);
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
    $t->get_ok('/login')->status_is(200)->content_is('logged in');
    $t->get_ok('/session')->status_is(200)->content_is('user:sri');
    $t->app->secrets(['test2', 'test1']);
    $t->get_ok('/session')->status_is(200)->content_is('user:sri');
    $t->get_ok('/logout')->status_is(200)->content_is('logged out');
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  };

  subtest 'User session (encrypted cookie)' => sub {
    plan skip_all => 'CryptX required!' unless Mojo::Util->CRYPTX;
    $t->reset_session;
    $t->app->secrets(['test1']);
    $t->app->sessions->encrypted(1);
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
    $t->get_ok('/login')->status_is(200)->content_is('logged in');
    $t->get_ok('/session')->status_is(200)->content_is('user:sri');
    $t->app->secrets(['test2', 'test1']);
    $t->get_ok('/session')->status_is(200)->content_is('user:sri');
    $t->get_ok('/logout')->status_is(200)->content_is('logged out');
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
    $t->get_ok('/session')->status_is(200)->content_is('user:nobody');
  };
};

subtest 'Insecure secret' => sub {
  subtest 'Insecure secret (signed cookie)' => sub {
    $t->reset_session;
    $t->app->secrets([app->moniker]);
    $t->app->sessions->encrypted(0);
    $t->get_ok('/login')->status_is(500);
  };

  subtest 'Insecure secret (encrypted cookie)' => sub {
    plan skip_all => 'CryptX required!' unless Mojo::Util->CRYPTX;
    $t->reset_session;
    $t->app->secrets([app->moniker]);
    $t->app->sessions->encrypted(1);
    $t->get_ok('/login')->status_is(500);
  };
};

done_testing();
