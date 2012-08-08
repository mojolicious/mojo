use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::Base -strict;

# "Cheating in a fake fight. That's low."
use Mojo::IOLoop;

# Connection buffer
my %buffer;

# Minimal connect proxy server to test TLS tunneling
Mojo::IOLoop->server(
  {port => 3000} => sub {
    my ($loop, $stream, $client) = @_;
    $stream->on(
      read => sub {
        my ($stream, $chunk) = @_;
        if (my $server = $buffer{$client}{connection}) {
          return Mojo::IOLoop->stream($server)->write($chunk);
        }
        $buffer{$client}{client} .= $chunk;
        if ($buffer{$client}{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
          my $buffer = $buffer{$client}{client};
          $buffer{$client}{client} = '';
          if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
            my $address = $1;
            my $port = $2 || 80;
            my $server;
            $server = Mojo::IOLoop->client(
              {address => $address, port => $port} => sub {
                my ($loop, $err, $stream) = @_;
                if ($err) {
                  say "Connection error for $address:$port: $err";
                  Mojo::IOLoop->remove($client);
                  return delete $buffer{$client};
                }
                say "Forwarding to $address:$port.";
                $buffer{$client}{connection} = $server;
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    Mojo::IOLoop->stream($client)->write($chunk);
                  }
                );
                $stream->on(
                  close => sub {
                    Mojo::IOLoop->remove($client);
                    delete $buffer{$client};
                  }
                );
                Mojo::IOLoop->stream($client)
                  ->write("HTTP/1.1 200 OK\x0d\x0a"
                    . "Connection: keep-alive\x0d\x0a\x0d\x0a");
              }
            );
          }
        }
        else { Mojo::IOLoop->remove($client) }
      }
    );
    $stream->on(
      close => sub {
        Mojo::IOLoop->remove($buffer{$client}{connection})
          if $buffer{$client}{connection};
        delete $buffer{$client};
      }
    );
  }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting connect proxy on port 3000.
For testing use something like "HTTPS_PROXY=http://127.0.0.1:3000".
EOF

# Start event loop
Mojo::IOLoop->start;

1;
