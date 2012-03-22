use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 9;

# "I cheated the wrong way!
#  I wrote the Lisa name and gave the Ralph answers!"
use Mojo::IOLoop;
use Mojo::Server::Daemon;
use Mojo::UserAgent;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => sub {
  my $self = shift;
  my $rel  = $self->req->url;
  my $abs  = $rel->to_abs;
  $self->render_text("Hello World! $rel $abs");
};

# GET /proxy
get '/proxy' => sub {
  my $self = shift;
  $self->render_text($self->req->url);
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

# HTTP server for testing
my $ua = Mojo::UserAgent->new;
my $daemon =
  Mojo::Server::Daemon->new(app => app, ioloop => Mojo::IOLoop->singleton);
my $port = Mojo::IOLoop->new->generate_port;
$daemon->listen(["http://127.0.0.1:$port"])->start;

# Connect proxy server for testing
my $proxy = Mojo::IOLoop->generate_port;
my $c     = {};
my $connected;
my ($read, $sent, $fail) = 0;
my $nf =
    "HTTP/1.1 404 NOT FOUND\x0d\x0a"
  . "Content-Length: 0\x0d\x0a"
  . "Connection: close\x0d\x0a\x0d\x0a";
my $ok = "HTTP/1.1 200 OK\x0d\x0aConnection: keep-alive\x0d\x0a\x0d\x0a";
Mojo::IOLoop->server(
  {address => '127.0.0.1', port => $proxy} => sub {
    my ($loop, $stream, $client) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        if (my $server = $c->{$client}->{connection}) {
          return Mojo::IOLoop->stream($server)->write($chunk);
        }
        $c->{$client}->{client} //= '';
        $c->{$client}->{client} .= $chunk;
        if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
          my $buffer = $c->{$client}->{client};
          $c->{$client}->{client} = '';
          if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
            $connected = "$1:$2";
            $fail = 1 if $2 == $port + 1;
            my $server;
            $server = Mojo::IOLoop->client(
              {address => $1, port => $fail ? $port : $2} => sub {
                my ($loop, $err, $stream) = @_;
                if ($err) {
                  Mojo::IOLoop->remove($client);
                  return delete $c->{$client};
                }
                $c->{$client}->{connection} = $server;
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
                    delete $c->{$client};
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
        Mojo::IOLoop->remove($c->{$client}->{connection})
          if $c->{$client}->{connection};
        delete $c->{$client};
      }
    );
  }
);

# GET / (normal request)
my $result;
$ua->get(
  "http://localhost:$port/" => sub {
    $result = pop->success->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, "Hello World! / http://localhost:$port/", 'right content';

# WebSocket /test (normal websocket)
$result = undef;
$ua->websocket(
  "ws://localhost:$port/test" => sub {
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

# GET http://kraih.com/proxy (proxy request)
$ua->http_proxy("http://localhost:$port");
$result = undef;
$ua->get(
  "http://kraih.com/proxy" => sub {
    $result = pop->success->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
is $result, 'http://kraih.com/proxy', 'right content';

# WebSocket /test (proxy websocket)
$ua->http_proxy("http://localhost:$proxy");
$result = undef;
$ua->websocket(
  "ws://localhost:$port/test" => sub {
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
is $connected, "localhost:$port", 'connected';
is $result,    'test1test2',      'right result';
ok $read > 25, 'read enough';
ok $sent > 25, 'sent enough';

# WebSocket /test (proxy websocket with bad target)
$ua->http_proxy("http://localhost:$proxy");
my $port2 = $port + 1;
my ($success, $err);
$ua->websocket(
  "ws://localhost:$port2/test" => sub {
    my $tx = pop;
    $success = $tx->success;
    $err     = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$success, 'no success';
is $err, 'Proxy connection failed.', 'right message';
