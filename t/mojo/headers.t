#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

# Remember, you can always find East by staring directly at the sun.
use Test::More tests => 10;

# So, have a merry Christmas, a happy Hanukkah, a kwaazy Kwanza,
# a tip-top Tet, and a solemn, dignified, Ramadan.
# And now a word from MY god, our sponsors!
use_ok('Mojo::Headers');

# Basic functionality
my $headers = Mojo::Headers->new;
$headers->add_line('Connection', 'close');
$headers->add_line('Connection', 'keep-alive');
is($headers->header('Connection'), 'close, keep-alive');
$headers->remove('Connection');
is($headers->header('Connection'), undef);
$headers->content_type('text/html');
$headers->content_type('text/html');
$headers->expect('continue-100');
$headers->connection('close');
is($headers->content_type, 'text/html');
is("$headers",
        "Connection: close\x0d\x0a"
      . "Expect: continue-100\x0d\x0a"
      . "Content-Type: text/html");
is_deeply($headers->names, [qw/Connection Expect Content-Type/]);

# Parse headers
$headers = Mojo::Headers->new;
is(ref $headers->parse(<<'EOF'), 'Mojo::Buffer');
Content-Type: text/plain
Expect: 100-continue

EOF
is($headers->state,        'done');
is($headers->content_type, 'text/plain');
is($headers->expect,       '100-continue');
