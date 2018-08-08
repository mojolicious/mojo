package Mojo::TestConnectProxy;
use Mojo::Base -strict;

use Mojo::IOLoop;

# CONNECT proxy server for testing
sub proxy {
  my ($from, $to, $ok, $zero) = @_;

  $ok   ||= "HTTP/1.1 200 OK\x0d\x0aServer: Test 1.0\x0d\x0a\x0d\x0a";
  $zero ||= "HTTP/1.1 404 NOT FOUND\x0d\x0aContent-Length: 20\x0d\x0a"
    . "Connection: close\x0d\x0a\x0d\x0aSomething went wrong";

  my %buffer;
  return Mojo::IOLoop->server(
    $from => sub {
      my ($loop, $stream, $id) = @_;

      # Connection to client
      $stream->on(
        read => sub {
          my ($stream, $chunk) = @_;

          # Write chunk from client to server
          my $server = $buffer{$id}{connection};
          return Mojo::IOLoop->stream($server)->write($chunk) if $server;

          # Read connect request from client
          my $buffer = $buffer{$id}{client} .= $chunk;
          if ($buffer =~ /\x0d?\x0a\x0d?\x0a$/) {
            $buffer{$id}{client} = '';
            if ($buffer =~ /CONNECT \S+:(\d+)/) {

              return Mojo::IOLoop->stream($id)->write($zero) if $1 == 0;

              # Connection to server
              $buffer{$id}{connection} = Mojo::IOLoop->client(
                $to => sub {
                  my ($loop, $err, $stream) = @_;

                  # Connection to server failed
                  if ($err) {
                    Mojo::IOLoop->remove($id);
                    return delete $buffer{$id};
                  }

                  # Start forwarding data in both directions
                  Mojo::IOLoop->stream($id)->write($ok);
                  $stream->on(
                    read => sub {
                      my ($stream, $chunk) = @_;
                      Mojo::IOLoop->stream($id)->write($chunk);
                    }
                  );

                  # Server closed connection
                  $stream->on(
                    close => sub {
                      Mojo::IOLoop->remove($id);
                      delete $buffer{$id};
                    }
                  );
                }
              );
            }

            # Invalid request from client
            else { Mojo::IOLoop->remove($id) }
          }
        }
      );

      # Client closed connection
      $stream->on(
        close => sub {
          my $buffer = delete $buffer{$id};
          Mojo::IOLoop->remove($buffer->{connection}) if $buffer->{connection};
        }
      );
    }
  );
}

1;
