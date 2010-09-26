#!/usr/bin/env perl

use strict;
use warnings;

# Remember, you can always find East by staring directly at the sun.
use Test::More tests => 37;

# So, have a merry Christmas, a happy Hanukkah, a kwaazy Kwanza,
# a tip-top Tet, and a solemn, dignified, Ramadan.
# And now a word from MY god, our sponsors!
use_ok 'Mojo::Headers';

# Basic functionality
my $headers = Mojo::Headers->new;
$headers->add('Connection', 'close');
$headers->add('Connection', 'keep-alive');
is $headers->header('Connection'), 'close, keep-alive', 'right value';
$headers->remove('Connection');
is $headers->header('Connection'), undef, 'no value';
$headers->content_type('text/html');
$headers->content_type('text/html');
$headers->expect('continue-100');
$headers->connection('close');
is $headers->content_type, 'text/html', 'right value';
like "$headers", qr/.*\x0d\x0a.*\x0d\x0a.*/, 'right format';
my $hash = $headers->to_hash;
is $hash->{Connection}, 'close',        'right value';
is $hash->{Expect},     'continue-100', 'right value';
is $hash->{'Content-Type'}, 'text/html', 'right value';
$hash = $headers->to_hash(arrayref => 1);
is_deeply $hash->{Connection},     [['close']],        'right structure';
is_deeply $hash->{Expect},         [['continue-100']], 'right structure';
is_deeply $hash->{'Content-Type'}, [['text/html']],    'right structure';
is_deeply [sort @{$headers->names}], [qw/Connection Content-Type Expect/],
  'right structure';

# Multiline values
$headers = Mojo::Headers->new;
$headers->header('X-Test', [23, 24], 'single line', [25, 26]);
is "$headers",
    "X-Test: 23\x0d\x0a 24\x0d\x0a"
  . "X-Test: single line\x0d\x0a"
  . "X-Test: 25\x0d\x0a 26", 'right format';
my @array = $headers->header('X-Test');
is_deeply \@array, [[23, 24], ['single line'], [25, 26]], 'right structure';
is_deeply $headers->to_hash(arrayref => 1),
  {'X-Test' => [[23, 24], ['single line'], [25, 26]]}, 'right structure';
is_deeply $headers->to_hash,
  {'X-Test' => [[23, 24], 'single line', [25, 26]]}, 'right structure';
my $string = $headers->header('X-Test');
is $string, "23, 24, single line, 25, 26", 'right format';

# Parse headers
$headers = Mojo::Headers->new;
is ref $headers->parse(<<'EOF'), 'Mojo::ByteStream', 'right return value';
Content-Type: text/plain
Expect: 100-continue

EOF
ok $headers->is_done,      'parser is done';
is $headers->content_type, 'text/plain', 'right value';
is $headers->expect,       '100-continue', 'right value';

# Set headers from hash
$headers = Mojo::Headers->new;
$headers->from_hash({Connection => 'close', 'Content-Type' => 'text/html'});
is_deeply $headers->to_hash,
  {Connection => 'close', 'Content-Type' => 'text/html'}, 'right structure';

# Remove all headers
$headers->from_hash({});
is_deeply $headers->to_hash, {}, 'right structure';

$headers = Mojo::Headers->new;
$headers->from_hash(
    {'X-Test' => [[23, 24], ['single line'], [25, 26]], 'X-Test2' => 'foo'});
$hash = $headers->to_hash;
is_deeply $hash->{'X-Test'}, [[23, 24], 'single line', [25, 26]],
  'right structure';
is_deeply $hash->{'X-Test2'}, 'foo', 'right structure';
$hash = $headers->to_hash(arrayref => 1);
is_deeply $hash->{'X-Test'}, [[23, 24], ['single line'], [25, 26]],
  'right structure';
is_deeply $hash->{'X-Test2'}, [['foo']], 'right structure';

# Headers in chunks
$headers = Mojo::Headers->new;
ok !defined($headers->parse(<<EOF)), 'right return value';
Content-Type: text/plain
EOF
ok !$headers->is_done, 'parser is not done';
ok !defined($headers->content_type), 'no value';
ok !defined($headers->parse(<<EOF)), 'right return value';
X-Bender: Bite my shiny
EOF
ok !$headers->is_done, 'parser is not done';
ok !defined($headers->connection), 'no value';
is ref $headers->parse(<<EOF), 'Mojo::ByteStream', 'right return value';
X-Bender: metal ass!

EOF
ok $headers->is_done, 'parser is done';
is $headers->content_type, 'text/plain', 'right value';
is $headers->header('X-Bender'), 'Bite my shiny, metal ass!', 'right value';
