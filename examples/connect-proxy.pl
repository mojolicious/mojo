use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::Base -strict;

# "Cheating in a fake fight. That's low."
use Mojo::IOLoop;

# Connection buffer
my $c = {};

# Minimal connect proxy server to test TLS tunneling
Mojo::IOLoop->server(
  {port => 3000} => sub {
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
            my $address = $1;
            my $port = $2 || 80;
            my $server;
            $server = Mojo::IOLoop->client(
              {address => $address, port => $port} => sub {
                my ($loop, $err, $stream) = @_;
                if ($err) {
                  say "Connection error for $address:$port: $err";
                  Mojo::IOLoop->remove($client);
                  return delete $c->{$client};
                }
                say "Forwarding to $address:$port.";
                $c->{$client}->{connection} = $server;
                $stream->on(
                  read => sub {
                    my ($stream, $chunk) = @_;
                    Mojo::IOLoop->stream($client)->write($chunk);
                  }
                );
                $stream->on(
                  close => sub {
                    Mojo::IOLoop->remove($client);
                    delete $c->{$client};
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
        Mojo::IOLoop->remove($c->{$client}->{connection})
          if $c->{$client}->{connection};
        delete $c->{$client};
      }
    );
  }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting connect proxy on port 3000.
For testing use something like "HTTPS_PROXY=http://127.0.0.1:3000".
EOF

# Start loop
Mojo::IOLoop->start;

1;
