use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::IOLoop::Server;

plan skip_all => 'set TEST_TLS to enable this test (developer only!)'
  unless $ENV{TEST_TLS};
plan skip_all => 'IO::Socket::SSL 1.75 required for this test!'
  unless Mojo::IOLoop::Server::TLS;

use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => sub {
  my $self = shift;
  $self->res->headers->header('X-Works',
    $self->req->headers->header('X-Works'));
  my $rel = $self->req->url;
  my $abs = $rel->to_abs;
  $self->render(text => "Hello World! $rel $abs");
};

get '/broken_redirect' => sub {
  my $self = shift;
  $self->render(text => 'Redirecting!', status => 302);
  $self->res->headers->location('/');
};

get '/proxy' => sub {
  my $self = shift;
  $self->render(text => $self->req->url->to_abs);
};

websocket '/test' => sub {
  my $self = shift;
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send("${msg}test2");
    }
  );
};

# Web server with valid certificates
my $daemon = Mojo::Server::Daemon->new(app => app, silent => 1);
my $port = Mojo::IOLoop->new->generate_port;
my $listen
  = "https://127.0.0.1:$port"
  . '?cert=t/mojo/certs/server.crt'
  . '&key=t/mojo/certs/server.key'
  . '&ca=t/mojo/certs/ca.crt';
$daemon->listen([$listen])->start;

# Connect proxy server for testing
my $proxy = Mojo::IOLoop->generate_port;
my (%buffer, $connected, $read, $sent);
my $nf
  = "HTTP/1.1 404 NOT FOUND\x0d\x0a"
  . "Content-Length: 0\x0d\x0a"
  . "Connection: close\x0d\x0a\x0d\x0a";
my $ok = "HTTP/1.0 200 OK\x0d\x0aX-Something: unimportant\x0d\x0a\x0d\x0a";
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $proxy} => sub {
    my ($loop, $stream, $client) = @_;

    # Connection to client
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;

        # Write chunk from client to server
        my $server = $buffer{$client}{connection};
        return Mojo::IOLoop->stream($server)->write($chunk) if $server;

        # Read connect request from client
        my $buffer = $buffer{$client}{client} .= $chunk;
        if ($buffer =~ /\x0d?\x0a\x0d?\x0a$/) {
          $buffer{$client}{client} = '';
          if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
            $connected = "$1:$2";
            my $fail = $2 == $port + 1;

            # Connection to server
            $buffer{$client}{connection} = Mojo::IOLoop->client(
              {address => $1, port => $fail ? $port : $2} => sub {
                my ($loop, $err, $stream) = @_;

                # Connection to server failed
                if ($err) {
                  Mojo::IOLoop->remove($client);
                  return delete $buffer{$client};
                }

                # Start forwarding data in both directions
                Mojo::IOLoop->stream($client)->write($fail ? $nf : $ok);
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    $read += length $chunk;
                    $sent += length $chunk;
                    Mojo::IOLoop->stream($client)->write($chunk);
                  }
                );

                # Server closed connection
                $stream->on(
                  close => sub {
                    Mojo::IOLoop->remove($client);
                    delete $buffer{$client};
                  }
                );
              }
            );
          }
        }

        # Invalid request from client
        else { Mojo::IOLoop->remove($client) }
      }
    );

    # Client closed connection
    $stream->on(
      close => sub {
        my $buffer = delete $buffer{$client};
        Mojo::IOLoop->remove($buffer->{connection}) if $buffer->{connection};
      }
    );
  }
);

# User agent with valid certificates
my $ua = Mojo::UserAgent->new(
  ioloop => Mojo::IOLoop->singleton,
  ca     => 't/mojo/certs/ca.crt',
  cert   => 't/mojo/certs/client.crt',
  key    => 't/mojo/certs/client.key'
);

# Normal non-blocking request
my $result;
$ua->get(
  "https://localhost:$port/" => sub {
    $result = pop->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / https://localhost:$port/", 'right content';

# Broken redirect
my $start;
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
    my ($ua, $tx) = @_;
    $result = $tx->res->body;
    $works  = $tx->res->headers->header('X-Works');
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / https://localhost:$port/", 'right content';
is $works,  'it does!',                                'right header';
is $start,  2,                                         'redirected once';
$ua->unsubscribe('start');

# Normal WebSocket
$result = undef;
$ua->websocket(
  "wss://localhost:$port/test" => sub {
    my ($ua, $tx) = @_;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result = $msg;
        $tx->finish;
      }
    );
    $tx->send('test1');
  }
);
Mojo::IOLoop->start;
is $result, 'test1test2', 'right result';

# Non-blocking proxy request
$ua->https_proxy("http://sri:secr3t\@localhost:$proxy");
$result = undef;
my ($auth, $kept_alive);
$ua->get(
  "https://localhost:$port/proxy" => sub {
    my ($ua, $tx) = @_;
    $result     = $tx->res->body;
    $auth       = $tx->req->headers->proxy_authorization;
    $kept_alive = $tx->kept_alive;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$auth,       'no "Proxy-Authorization" header';
ok !$kept_alive, 'connection was not kept alive';
is $result, "https://localhost:$port/proxy", 'right content';

# Non-blocking kept alive proxy request
($kept_alive, $result) = ();
$ua->get(
  "https://localhost:$port/proxy" => sub {
    my ($ua, $tx) = @_;
    $kept_alive = $tx->kept_alive;
    $result     = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "https://localhost:$port/proxy", 'right content';
ok $kept_alive, 'connection was kept alive';

# Kept alive proxy WebSocket
$ua->https_proxy("http://localhost:$proxy");
($kept_alive, $result) = ();
$ua->websocket(
  "wss://localhost:$port/test" => sub {
    my ($ua, $tx) = @_;
    $kept_alive = $tx->kept_alive;
    $tx->on(finish => sub { Mojo::IOLoop->stop });
    $tx->on(
      message => sub {
        my ($tx, $msg) = @_;
        $result = $msg;
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

# Blocking proxy request
$ua->https_proxy("http://sri:secr3t\@localhost:$proxy");
my $tx = $ua->get("https://localhost:$port/proxy");
is $tx->res->code, 200, 'right status';
is $tx->res->body, "https://localhost:$port/proxy", 'right content';

# Proxy WebSocket with bad target
$ua->https_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $err);
$ua->websocket(
  "wss://localhost:$port2/test" => sub {
    my ($ua, $tx) = @_;
    $success = $tx->success;
    $err     = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$success, 'no success';
is $err, 'Proxy connection failed', 'right message';

# Blocking proxy request again
$ua->https_proxy("http://localhost:$proxy");
$tx = $ua->get("https://localhost:$port/proxy");
is $tx->res->code, 200, 'right status';
is $tx->res->body, "https://localhost:$port/proxy", 'right content';

done_testing();
