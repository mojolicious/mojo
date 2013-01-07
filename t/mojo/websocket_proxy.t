use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
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
  $self->on(
    message => sub {
      my ($self, $msg) = @_;
      $self->send("${msg}test2");
    }
  );
};

# HTTP server for testing
my $ua     = Mojo::UserAgent->new;
my $daemon = Mojo::Server::Daemon->new(
  app    => app,
  ioloop => Mojo::IOLoop->singleton,
  silent => 1
);
my $port = Mojo::IOLoop->new->generate_port;
$daemon->listen(["http://127.0.0.1:$port"])->start;

# Connect proxy server for testing
my $proxy = Mojo::IOLoop->generate_port;
my (%buffer, $connected, $read, $sent, $fail);
my $nf
  = "HTTP/1.1 404 NOT FOUND\x0d\x0a"
  . "Content-Length: 0\x0d\x0a"
  . "Connection: close\x0d\x0a\x0d\x0a";
my $ok = "HTTP/1.1 200 OK\x0d\x0aConnection: keep-alive\x0d\x0a\x0d\x0a";
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
            $fail = 1 if $2 == $port + 1;

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

# GET http://kraih.com/proxy (proxy request)
$ua->http_proxy("http://localhost:$port");
my $kept_alive;
$result = undef;
$ua->get(
  "http://kraih.com/proxy" => sub {
    my ($ua, $tx) = @_;
    $kept_alive = $tx->kept_alive;
    $result     = $tx->success->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$kept_alive, 'connection was not kept alive';
is $result, 'http://kraih.com/proxy', 'right content';

# WebSocket /test (kept alive proxy websocket)
($kept_alive, $result) = ();
$ua->websocket(
  "ws://localhost:$port/test" => sub {
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
is $result, 'test1test2', 'right result';

# WebSocket /test (proxy websocket)
$ua = Mojo::UserAgent->new(http_proxy => "http://localhost:$proxy");
$result = undef;
$ua->websocket(
  "ws://localhost:$port/test" => sub {
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
    my ($ua, $tx) = @_;
    $success = $tx->success;
    $err     = $tx->error;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok !$success, 'no success';
is $err, 'Proxy connection failed', 'right message';

done_testing();
