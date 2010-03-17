#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Use bundled libraries
use FindBin;
use lib "$FindBin::Bin/../lib";

# Cheating in a fake fight. That's low.
use Mojo::IOLoop;

# The loop
my $loop = Mojo::IOLoop->new;

# Connection buffer
my $c = {};

# Minimal connect proxy server to test TLS tunneling
$loop->listen(
    port => 3000,
    cb   => sub {
        my ($loop, $client) = @_;

        # Start read only mode on the client side
        $loop->not_writing($client);

        # Read callback for the client side
        $loop->read_cb(
            $client => sub {
                my ($loop, $client, $chunk) = @_;

                # Buffer client chunk for server forwarding
                $c->{$client}->{client} ||= '';
                $c->{$client}->{client} .= $chunk;

                # Write chunk to server
                if (my $server = $c->{$client}->{connection}) {
                    $loop->writing($server);
                    return;
                }

                # Open connection to server
                if ($c->{$client}->{client} =~ /\x0d?\x0a\x0d?\x0a$/) {

                    # Parse CONNECT request
                    my $buffer = delete $c->{$client}->{client};
                    if ($buffer =~ /CONNECT (\S+):(\d+)?/) {

                        # Connect server
                        my $server = $loop->connect(
                            address => $1,
                            port    => $2 || 80,
                            cb      => sub {
                                my ($loop, $server) = @_;

                                # Bind server to client
                                $c->{$client}->{connection} = $server;

                                # Write response to client
                                $c->{$client}->{server} =
                                    "HTTP/1.1 200 OK\x0d\x0a"
                                  . "Connection: keep-alive\x0d\x0a\x0d\x0a";
                                $loop->writing($client);
                            }
                        );

                        # Error callback for the server side
                        $loop->error_cb(
                            $server => sub {

                                # Drop client connection
                                shift->drop($client);
                                delete $c->{$client};
                            }
                        );

                        # Read callback for the server side
                        $loop->read_cb(
                            $server => sub {
                                my ($loop, $server, $chunk) = @_;

                                # Buffer server chunk for client forwarding
                                $c->{$client}->{server} ||= '';
                                $c->{$client}->{server} .= $chunk;

                                # Write chunk to client
                                $loop->writing($client);
                            }
                        );

                        # Write callback for the server side
                        $loop->write_cb(
                            $server => sub {
                                my ($loop, $server) = @_;

                                # Write chunk to server
                                $loop->not_writing($server);
                                return delete $c->{$client}->{client};
                            }
                        );
                    }

                    # End connection
                    else { $loop->drop($client) }
                }
            }
        );

        # Write callback for the client side
        $loop->write_cb(
            $client => sub {
                my ($loop, $client) = @_;

                # Write chunk to client
                $loop->not_writing($client);
                return delete $c->{$client}->{server};
            }
        );

        # Error callback for the client side
        $loop->error_cb(
            $client => sub {
                my ($self, $client) = @_;

                # Drop server connection
                shift->drop($c->{$client}->{connection})
                  if $c->{$client}->{connection};
                delete $c->{$client};
            }
        );
    }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting connect proxy on port 3000.
For testing use something like "HTTPS_PROXY=https://127.0.0.1:3000".
EOF

# Start loop
$loop->start;

1;
