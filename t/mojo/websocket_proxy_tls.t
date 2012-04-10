use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

# "Hey, Weener Boy... where do you think you're going?"
use Test::More;
use Mojo::IOLoop::Server;
plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.37 required for this test!'
  unless Mojo::IOLoop::Server::TLS;
plan tests => 17;

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => sub {
  my $self = shift;
  $self->res->headers->header('X-Works',
    $self->req->headers->header('X-Works'));
  my $rel = $self->req->url;
  my $abs = $rel->to_abs;
  $self->render_text("Hello World! $rel $abs");
};

# GET /broken_redirect
get '/broken_redirect' => sub {
  my $self = shift;
  $self->render(text => 'Redirecting!', status => 302);
  $self->res->headers->location('/');
};

# GET /proxy
get '/proxy' => sub {
  my $self = shift;
  $self->render_text($self->req->url->to_abs);
};

# WebSocket /test
websocket '/test' => sub {
  my $self = shift;
  my $flag = 0;
  $self->on(
    message => sub {
      my ($self, $message) = @_;
      $self->send("${message}test2");
      $flag = 24;
    }
  );
};

# Web server with valid certificates
my $daemon =
  Mojo::Server::Daemon->new(app => app, ioloop => Mojo::IOLoop->singleton);
my $port = Mojo::IOLoop->new->generate_port;
my $listen =
    "https://127.0.0.1:$port"
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt';
$daemon->listen([$listen])->start;

# Connect proxy server for testing
my $proxy = Mojo::IOLoop->generate_port;
my (%buffer, $connected);
my ($read, $sent, $fail) = 0;
my $nf =
    "HTTP/1.1 404 NOT FOUND\x0d\x0a"
  . "Content-Length: 0\x0d\x0a"
  . "Connection: close\x0d\x0a\x0d\x0a";
my $ok = "HTTP/1.0 200 OK\x0d\x0aX-Something: unimportant\x0d\x0a\x0d\x0a";
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $proxy} => sub {
    my ($loop, $stream, $client) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        if (my $server = $buffer{$client}->{connection}) {
          return Mojo::IOLoop->stream($server)->write($chunk);
        }
        $buffer{$client}->{client} .= $chunk;
        if ($buffer{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
          my $buffer = $buffer{$client}->{client};
          $buffer{$client}->{client} = '';
          if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
            $connected = "$1:$2";
            $fail = 1 if $2 == $port + 1;
            my $server;
            $server = Mojo::IOLoop->client(
              {address => $1, port => $fail ? $port : $2} => sub {
                my ($loop, $err, $stream) = @_;
                if ($err) {
                  Mojo::IOLoop->remove($client);
                  return delete $buffer{$client};
                }
                $buffer{$client}->{connection} = $server;
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    $read += length $chunk;
                    $sent += length $chunk;
                    Mojo::IOLoop->stream($client)->write($chunk);
                  }
                );
                $stream->on(
                  close => sub {
                    Mojo::IOLoop->remove($client);
                    delete $buffer{$client};
                  }
                );
                Mojo::IOLoop->stream($client)->write($fail ? $nf : $ok);
              }
            );
          }
        }
        else { Mojo::IOLoop->remove($client) }
      }
    );
    $stream->on(
      close => sub {
        Mojo::IOLoop->remove($buffer{$client}->{connection})
          if $buffer{$client}->{connection};
        delete $buffer{$client};
      }
    );
  }
);

# User agent with valid certificates
my $ua = Mojo::UserAgent->new(
  ca   => 't/mojo/certs/ca.crt',
  cert => 't/mojo/certs/client.crt',
  key  => 't/mojo/certs/client.key'
);

# GET / (normal request)
my $result;
$ua->get(
  "https://localhost:$port/" => sub {
    $result = pop->success->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / https://localhost:$port/", 'right content';

# GET /broken_redirect (broken redirect)
my $start = 0;
$ua->on(
  start => sub {
    $start++;
    pop->req->headers->header('X-Works', 'it does!');
  }
);
$result = undef;
my $works;
$ua->max_redirects(3)->get(
  "https://localhost:$port/broken_redirect" => sub {
    my $tx = pop;
    $result = $tx->success->body;
    $works  = $tx->res->headers->header('X-Works');
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / https://localhost:$port/", 'right content';
is $works,  'it does!',                                'right header';
is $start,  2,                                         'redirected once';
$ua->unsubscribe('start');

# WebSocket /test (normal websocket)
$result = undef;
$ua->websocket(
  "wss://localhost:$port/test" => sub {
    my $tx = pop;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->finish;
      }
    );
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
is $result, 'test1test2', 'right result';

# GET /proxy (proxy request)
$ua->https_proxy("http://sri:secr3t\@localhost:$proxy");
$result = undef;
my ($auth, $kept_alive);
$ua->get(
  "https://localhost:$port/proxy" => sub {
    my ($ua, $tx) = @_;
    $result     = $tx->success->body;
    $auth       = $tx->req->headers->proxy_authorization;
    $kept_alive = $tx->kept_alive;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "https://localhost:$port/proxy", 'right content';
ok !$auth,       'no "Proxy-Authorization" header';
ok !$kept_alive, 'connection was not kept alive';

# GET /proxy (kept alive proxy request)
($result, $kept_alive) = undef;
$ua->get(
  "https://localhost:$port/proxy" => sub {
    my $tx = pop;
    $result     = $tx->success->body;
    $kept_alive = $tx->kept_alive;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "https://localhost:$port/proxy", 'right content';
ok $kept_alive, 'connection was kept alive';

# WebSocket /test (kept alive proxy websocket)
$ua->https_proxy("http://localhost:$proxy");
($result, $kept_alive) = undef;
$ua->websocket(
  "wss://localhost:$port/test" => sub {
    my $tx = pop;
    $kept_alive = $tx->kept_alive;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $message) = @_;
        $result = $message;
        $tx->finish;
      }
    );
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
ok $kept_alive, 'connection was kept alive';
is $connected,  "localhost:$port", 'connected';
is $result,     'test1test2', 'right result';
ok $read > 25, 'read enough';
ok $sent > 25, 'sent enough';

# WebSocket /test (proxy websocket with bad target)
$ua->https_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $err);
$ua->websocket(
  "wss://localhost:$port2/test" => sub {
    my $tx = pop;
    $success = $tx->success;
    $err     = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$success, 'no success';
is $err, 'Proxy connection failed.', 'right message';
