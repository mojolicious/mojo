#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

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
    read_cb => sub {
        my ($loop, $client, $chunk) = @_;
        $c->{$client}->{client} = b unless exists $c->{$client}->{client};
        $c->{$client}->{client}->add_chunk($chunk);
        if (my $server = $c->{$client}->{connection}) {
            $loop->writing($server);
            return;
        }
        if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {
            my $buffer = $c->{$client}->{client}->empty;
            if ($buffer =~ /CONNECT (\S+):(\d+)?/) {
                my $address = $1;
                my $port    = $2 || 80;
                my $server  = $loop->connect(
                    address    => $address,
                    port       => $port,
                    connect_cb => sub {
                        my ($loop, $server) = @_;
                        print "Forwarding to $address:$port.\n";
                        $c->{$client}->{connection} = $server;
                        $c->{$client}->{server} = b("HTTP/1.1 200 OK\x0d\x0a"
                              . "Connection: keep-alive\x0d\x0a\x0d\x0a");
                        $loop->writing($client);
                    },
                    error_cb => sub {
                        shift->drop($client);
                        delete $c->{$client};
                    },
                    read_cb => sub {
                        my ($loop, $server, $chunk) = @_;
                        $c->{$client}->{server}->add_chunk($chunk);
                        $loop->writing($client);
                    },
                    write_cb => sub {
                        my ($loop, $server) = @_;
                        $loop->not_writing($server);
                        return $c->{$client}->{client}->empty;
                    }
                );
            }
            else { $loop->drop($client) }
        }
    },
    write_cb => sub {
        my ($loop, $client) = @_;
        $loop->not_writing($client);
        return $c->{$client}->{server}->empty;
    },
    error_cb => sub {
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
