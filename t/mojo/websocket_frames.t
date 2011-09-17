#!/usr/bin/env perl
use Mojo::Base -strict;

# "Being eaten by crocodile is just like going to sleep...
#  in a giant blender."
use Test::More tests => 17;

use_ok 'Mojo::Transaction::WebSocket';

# Simple text frame roundtrip
my $ws    = Mojo::Transaction::WebSocket->new;
my $bytes = $ws->build_frame(1, 1, 'whatever');
my $frame = $ws->parse_frame(\(my $dummy = $bytes));
is $frame->[0], 1,          'fin flag is set';
is $frame->[1], 1,          'text frame';
is $frame->[2], 'whatever', 'right payload';
is $ws->build_frame(1, 1, 'whatever'), $bytes, 'frames are equal';

# Simple binary frame roundtrip
$ws    = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 2, 'works');
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,       'fin flag is set';
is $frame->[1], 2,       'binary frame';
is $frame->[2], 'works', 'right payload';
is $bytes = $ws->build_frame(1, 2, 'works'), $bytes, 'frames are equal';

# Masked text frame roundtrip
$ws = Mojo::Transaction::WebSocket->new(masked => 1);
$bytes = $ws->build_frame(1, 1, 'also works');
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,            'fin flag is set';
is $frame->[1], 1,            'text frame';
is $frame->[2], 'also works', 'right payload';
isnt Mojo::Transaction::WebSocket->new->build_frame(1, 2, 'also works'),
  $bytes, 'frames are not equal';

# Masked binary frame roundtrip
$ws = Mojo::Transaction::WebSocket->new(masked => 1);
$bytes = $ws->build_frame(1, 2, 'just works');
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,            'fin flag is set';
is $frame->[1], 2,            'binary frame';
is $frame->[2], 'just works', 'right payload';
isnt Mojo::Transaction::WebSocket->new->build_frame(1, 2, 'just works'),
  $bytes, 'frames are not equal';
