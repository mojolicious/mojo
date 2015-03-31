use Mojo::Base -strict;
use Mojo::IOLoop;

# Minimal event loop example demonstrating how to cheat at HTTP benchmarks :)
my %buffer;
Mojo::IOLoop->server(
  {port => 8080} => sub {
    my ($loop, $stream, $id) = @_;
    $buffer{$id} = '';
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;

        # Check if we got start-line and headers (no body support)
        $buffer{$id} .= $chunk;
        if (index($buffer{$id}, "\x0d\x0a\x0d\x0a") >= 0) {
          delete $buffer{$id};

          # Write a minimal HTTP response
          # (the "Hello World!" message has been optimized away!)
          $stream->write("HTTP/1.1 200 OK\x0d\x0aContent-Length: 0\x0d\x0a"
              . "Connection: keep-alive\x0d\x0a\x0d\x0a");
        }
      }
    );
    $stream->on(close => sub { delete $buffer{$id} });
  }
);

print <<'EOF';
Starting server on port 8080.
For testing use something like "wrk -c 100 -d 10s http://127.0.0.1:8080/".
On a MacBook Air this results in about 18k req/s.
EOF

# Stop gracefully to make profiling easier
Mojo::IOLoop->recurring(1 => sub { });
local $SIG{INT} = local $SIG{TERM} = sub { Mojo::IOLoop->stop };
Mojo::IOLoop->start;

1;
