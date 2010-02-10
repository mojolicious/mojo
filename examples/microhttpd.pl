#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Use bundled libraries
use FindBin;
use lib "$FindBin::Bin/../lib";

# Kif, I'm feeling the Captain's Itch.
# I'll get the powder, sir.
use Mojo::IOLoop;

# The loop
my $loop = Mojo::IOLoop->new;

# Buffer for incoming data
my $buffer = {};

# Minimal ioloop example demonstrating how to cheat at HTTP benchmarks :)
$loop->listen(
    port => 3000,
    cb   => sub {
        my ($loop, $id) = @_;

        # Initialize buffer
        $buffer->{$id} = '';

        # Start read only mode
        $loop->not_writing($id);

        # Read callback
        $loop->read_cb(
            $id => sub {
                my ($loop, $id, $chunk) = @_;

                # Append chunk to buffer
                $buffer->{$id} .= $chunk;

                # Check if we got start line and headers (no body support)
                if ($buffer->{$id} =~ /\x0d?\x0a\x0d?\x0a$/) {

                    # Clean buffer
                    delete $buffer->{$id};

                    # Start read/write mode
                    $loop->writing($id);
                }
            }
        );

        # Write callback
        $loop->write_cb(
            $id => sub {
                my ($loop, $id) = @_;

                # Start read only mode again
                $loop->not_writing($id);

                # Write a minimal HTTP response
                # (not spec compliant but benchmarks won't care)
                return
                    "HTTP/1.1 200 OK\x0d\x0a"
                  . "Connection: keep-alive\x0d\x0aContent-Length: 11\x0d\x0a\x0d\x0a"
                  . "Hello Mojo!";
            }
        );

        # Error callback (clean buffer)
        $loop->error_cb(
            $id => sub {
                my ($self, $id) = @_;

                # Clean buffer
                delete $buffer->{$id};
            }
        );
    }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting server on port 3000.
Try something like "ab -c 30 -n 10000 -k http://127.0.0.1:3000/" for testing.
On a recent MacBook 13" this should result in about 10k req/s.
EOF

# Start loop
$loop->start;

1;
