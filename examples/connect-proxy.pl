#!/usr/bin/env perl

use strict;
use warnings;

# Use bundled libraries
use FindBin;
use lib "$FindBin::Bin/../lib";

# Cheating in a fake fight. That's low.
use Mojo::ByteStream 'b';
use Mojo::IOLoop;

# The loop
my $loop = Mojo::IOLoop->new;

# Connection buffer
my $c = {};

# Minimal connect proxy server to test TLS tunneling
$loop->listen(
    port    => 3000,
    on_read => sub {
        my ($loop, $client, $chunk) = @_;
        if (my $server = $c->{$client}->{connection}) {
            return $loop->write($server, $chunk);
        }
        $c->{$client}->{client} = b unless exists $c->{$client}->{client};
        $c->{$client}->{client}->add_chunk($chunk);
        if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
            my $buffer = $c->{$client}->{client}->empty;
            if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
                my $address = $1;
                my $port    = $2 || 80;
                my $server  = $loop->connect(
                    address    => $address,
                    port       => $port,
                    on_connect => sub {
                        my ($loop, $server) = @_;
                        print "Forwarding to $address:$port.\n";
                        $c->{$client}->{connection} = $server;
                        $loop->write($client,
                                "HTTP/1.1 200 OK\x0d\x0a"
                              . "Connection: keep-alive\x0d\x0a\x0d\x0a");
                    },
                    on_read => sub {
                        my ($loop, $server, $chunk) = @_;
                        $loop->write($client, $chunk);
                    },
                    on_error => sub {
                        shift->drop($client);
                        delete $c->{$client};
                    }
                );
            }
            else { $loop->drop($client) }
        }
    },
    on_error => sub {
        my ($self, $client) = @_;
        shift->drop($c->{$client}->{connection})
          if $c->{$client}->{connection};
        delete $c->{$client};
    }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting connect proxy on port 3000.
For testing use something like "HTTPS_PROXY=https://127.0.0.1:3000".
EOF

# Start loop
$loop->start;

1;
