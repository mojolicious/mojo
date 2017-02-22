use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::File 'tempdir';
use IO::Socket::UNIX;

plan skip_all => 'set TEST_UNIX to enable this test (developer only!)'
  unless $ENV{TEST_UNIX};
my $dir   = tempdir;
my $dummy = $dir->child('dummy.sock')->to_string;
plan skip_all => 'UNIX domain socket support required for this test!'
  unless IO::Socket::UNIX->new(Listen => 1, Local => $dummy);

use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojo::Util 'url_escape';
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'works!'};

get '/info' => sub {
  my $c              = shift;
  my $local_address  = $c->tx->local_address // 'None';
  my $local_port     = $c->tx->local_port // 'None';
  my $remote_address = $c->tx->remote_address // 'None';
  my $remote_port    = $c->tx->remote_port // 'None';
  $c->render(text => "$local_address:$local_port:$remote_address:$remote_port");
};

# UNIX domain socket server
my $test    = $dir->child('test.sock');
my $encoded = url_escape "$test";
ok !$ENV{MOJO_REUSE}, 'environment is clean';
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  listen => ["http+unix://$encoded"],
  silent => 1
)->start;
ok -S $test, 'UNIX domain socket exists';
my $fd = fileno $daemon->ioloop->acceptor($daemon->acceptors->[0])->handle;
like $ENV{MOJO_REUSE}, qr/^unix:\Q$test\E:\Q$fd\E/,
  'file descriptor can be reused';

# Root
my $ua = Mojo::UserAgent->new(ioloop => $daemon->ioloop);
my $tx = $ua->get("http+unix://$encoded/");
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# Connection information
$tx = $ua->get("http+unix://$encoded/info");
is $tx->res->code, 200, 'right status';
is $tx->res->body, 'None:None:None:None', 'right content';

# Cleanup
undef $daemon;
ok !$ENV{MOJO_REUSE}, 'environment is clean';

done_testing();
