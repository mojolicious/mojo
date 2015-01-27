use Mojo::Base -strict;
use Mojo::IOLoop;

# Minimal CONNECT proxy server to test TLS tunneling
my %buffer;
Mojo::IOLoop->server(
  {port => 3000} => sub {
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
            my $address = $1;
            my $port = $2 || 80;

            # Connection to server
            $buffer{$client}{connection} = Mojo::IOLoop->client(
              {address => $address, port => $port} => sub {
                my ($loop, $err, $stream) = @_;

                # Connection to server failed
                if ($err) {
                  say "Connection error for $address:$port: $err";
                  Mojo::IOLoop->remove($client);
                  return delete $buffer{$client};
                }

                # Start forwarding data in both directions
                say "Forwarding to $address:$port";
                Mojo::IOLoop->stream($client)
                  ->write("HTTP/1.1 200 OK\x0d\x0a"
                    . "Connection: keep-alive\x0d\x0a\x0d\x0a");
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
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

print <<'EOF';
Starting CONNECT proxy on port 3000.
For testing use something like "HTTPS_PROXY=http://127.0.0.1:3000".
EOF

# Start event loop
Mojo::IOLoop->start;

1;
