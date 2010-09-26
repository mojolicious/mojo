#!/usr/bin/env perl

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
    port      => 3000,
    on_accept => sub {
        my ($loop, $id) = @_;

        # Initialize buffer
        $buffer->{$id} = '';
    },
    on_read => sub {
        my ($loop, $id, $chunk) = @_;

        # Append chunk to buffer
        $buffer->{$id} .= $chunk;

        # Check if we got start line and headers (no body support)
        if (index $buffer->{$id}, "\x0d\x0a\x0d\x0a") {

            # Clean buffer
            delete $buffer->{$id};

            # Write a minimal HTTP response
            # (not spec compliant but benchmarks won't care)
            $loop->write($id => "HTTP/1.1 200 OK\x0d\x0a"
                  . "Connection: keep-alive\x0d\x0a\x0d\x0a");
        }
    },
    on_error => sub {
        my ($self, $id) = @_;

        # Clean buffer
        delete $buffer->{$id};
    }
) or die "Couldn't create listen socket!\n";

print <<'EOF';
Starting server on port 3000.
Try something like "ab -c 30 -n 100000 -k http://127.0.0.1:3000/" for testing.
On a MacBook Pro 13" this results in about 19k req/s.
EOF

# Start loop
$loop->start;

1;
