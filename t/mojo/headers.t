#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

# Remember, you can always find East by staring directly at the sun.
use Test::More tests => 38;

# So, have a merry Christmas, a happy Hanukkah, a kwaazy Kwanza,
# a tip-top Tet, and a solemn, dignified, Ramadan.
# And now a word from MY god, our sponsors!
use_ok('Mojo::Headers');

# Basic functionality
my $headers = Mojo::Headers->new;
$headers->add('Connection', 'close');
$headers->add('Connection', 'keep-alive');
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
my $hash = $headers->to_hash;
is($hash->{Connection},     'close');
is($hash->{Expect},         'continue-100');
is($hash->{'Content-Type'}, 'text/html');
$hash = $headers->to_hash(arrayref => 1);
is_deeply($hash->{Connection},     [['close']]);
is_deeply($hash->{Expect},         [['continue-100']]);
is_deeply($hash->{'Content-Type'}, [['text/html']]);
is_deeply($headers->names,         [qw/Connection Expect Content-Type/]);

# Multiline values
$headers = Mojo::Headers->new;
$headers->header('X-Test', [23, 24], 'single line', [25, 26]);
is("$headers",
        "X-Test: 23\x0d\x0a 24\x0d\x0a"
      . "X-Test: single line\x0d\x0a"
      . "X-Test: 25\x0d\x0a 26");
my @array = $headers->header('X-Test');
is_deeply(\@array, [[23, 24], ['single line'], [25, 26]]);
is_deeply($headers->to_hash(arrayref => 1),
    {'X-Test' => [[23, 24], ['single line'], [25, 26]]});
is_deeply($headers->to_hash,
    {'X-Test' => [[23, 24], 'single line', [25, 26]]});
my $string = $headers->header('X-Test');
is($string, "23, 24, single line, 25, 26");

# Parse headers
$headers = Mojo::Headers->new;
is(ref $headers->parse(<<'EOF'), 'Mojo::Buffer');
Content-Type: text/plain
Expect: 100-continue

EOF
is($headers->state,        'done');
is($headers->content_type, 'text/plain');
is($headers->expect,       '100-continue');

# Set headers from hash
$headers = Mojo::Headers->new;
$headers->from_hash({Connection => 'close', 'Content-Type' => 'text/html'});
is_deeply($headers->to_hash,
    {Connection => 'close', 'Content-Type' => 'text/html'});

# Remove all headers
$headers->from_hash({});
is_deeply($headers->to_hash, {});

$headers = Mojo::Headers->new;
$headers->from_hash(
    {'X-Test' => [[23, 24], ['single line'], [25, 26]], 'X-Test2' => 'foo'});
$hash = $headers->to_hash;
is_deeply($hash->{'X-Test'}, [[23, 24], 'single line', [25, 26]]);
is_deeply($hash->{'X-Test2'}, 'foo');
$hash = $headers->to_hash(arrayref => 1);
is_deeply($hash->{'X-Test'}, [[23, 24], ['single line'], [25, 26]]);
is_deeply($hash->{'X-Test2'}, [['foo']]);

# Headers in chunks
$headers = Mojo::Headers->new;
ok(!defined($headers->parse(<<EOF)));
Content-Type: text/plain
EOF
is($headers->state, 'headers');
ok(!defined($headers->content_type));
ok(!defined($headers->parse(<<EOF)));
X-Bender: Bite my shiny
EOF
is($headers->state, 'headers');
ok(!defined($headers->connection));
is(ref $headers->parse(<<EOF), 'Mojo::Buffer');
X-Bender: metal ass!

EOF
is($headers->state,              'done');
is($headers->content_type,       'text/plain');
is($headers->header('X-Bender'), 'Bite my shiny, metal ass!');

# Filter unallowed characters
$headers = Mojo::Headers->new;
$headers->header("X-T\@est|>\r\ning", "s1n\000gl\1773 \r\n\r\n\006l1n3");
$string = $headers->header('X-Testing');
is($string, "s1ngl3 l1n3");
