use Mojo::Base -strict;

use Test::More;
use Mojo::Transaction::WebSocket;

# Simple text frame roundtrip
my $ws = Mojo::Transaction::WebSocket->new;
my $bytes = $ws->build_frame(1, 0, 0, 0, 1, 'whatever');
is $bytes, "\x81\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
my $frame = $ws->parse_frame(\(my $dummy = $bytes));
is $frame->[0], 1,          'fin flag is set';
is $frame->[1], 0,          'rsv1 flag is not set';
is $frame->[2], 0,          'rsv2 flag is not set';
is $frame->[3], 0,          'rsv3 flag is not set';
is $frame->[4], 1,          'text frame';
is $frame->[5], 'whatever', 'right payload';
is $ws->build_frame(1, 0, 0, 0, 1, 'whatever'), $bytes, 'frames are equal';

# Simple text frame roundtrip with all flags set
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 1, 1, 1, 1, 'whatever');
is $bytes, "\xf1\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,          'fin flag is set';
is $frame->[1], 1,          'rsv1 flag is set';
is $frame->[2], 1,          'rsv2 flag is set';
is $frame->[3], 1,          'rsv3 flag is set';
is $frame->[4], 1,          'text frame';
is $frame->[5], 'whatever', 'right payload';
is $ws->build_frame(1, 1, 1, 1, 1, 'whatever'), $bytes, 'frames are equal';

# Simple text frame roundtrip without FIN bit
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(0, 0, 0, 0, 1, 'whatever');
is $bytes, "\x01\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 0,          'fin flag is not set';
is $frame->[1], 0,          'rsv1 flag is not set';
is $frame->[2], 0,          'rsv2 flag is not set';
is $frame->[3], 0,          'rsv3 flag is not set';
is $frame->[4], 1,          'text frame';
is $frame->[5], 'whatever', 'right payload';
is $ws->build_frame(0, 0, 0, 0, 1, 'whatever'), $bytes, 'frames are equal';

# Simple text frame roundtrip with RSV1 flags set
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 1, 0, 0, 1, 'whatever');
is $bytes, "\xc1\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,          'fin flag is set';
is $frame->[1], 1,          'rsv1 flag is set';
is $frame->[2], 0,          'rsv2 flag is not set';
is $frame->[3], 0,          'rsv3 flag is not set';
is $frame->[4], 1,          'text frame';
is $frame->[5], 'whatever', 'right payload';
is $ws->build_frame(1, 1, 0, 0, 1, 'whatever'), $bytes, 'frames are equal';

# Simple text frame roundtrip with RSV2 flags set
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 1, 0, 1, 'whatever');
is $bytes, "\xa1\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,          'fin flag is set';
is $frame->[1], 0,          'rsv1 flag is not set';
is $frame->[2], 1,          'rsv2 flag is set';
is $frame->[3], 0,          'rsv3 flag is not set';
is $frame->[4], 1,          'text frame';
is $frame->[5], 'whatever', 'right payload';
is $ws->build_frame(1, 0, 1, 0, 1, 'whatever'), $bytes, 'frames are equal';

# Simple text frame roundtrip with RSV3 flags set
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 1, 1, 'whatever');
is $bytes, "\x91\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,          'fin flag is set';
is $frame->[1], 0,          'rsv1 flag is not set';
is $frame->[2], 0,          'rsv2 flag is not set';
is $frame->[3], 1,          'rsv3 flag is set';
is $frame->[4], 1,          'text frame';
is $frame->[5], 'whatever', 'right payload';
is $ws->build_frame(1, 0, 0, 1, 1, 'whatever'), $bytes, 'frames are equal';

# Simple binary frame roundtrip
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 0, 2, 'works');
is $bytes, "\x82\x05\x77\x6f\x72\x6b\x73", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,       'fin flag is set';
is $frame->[1], 0,       'rsv1 flag is not set';
is $frame->[2], 0,       'rsv2 flag is not set';
is $frame->[3], 0,       'rsv3 flag is not set';
is $frame->[4], 2,       'binary frame';
is $frame->[5], 'works', 'right payload';
is $bytes = $ws->build_frame(1, 0, 0, 0, 2, 'works'), $bytes,
  'frames are equal';

# Masked text frame roundtrip
$ws = Mojo::Transaction::WebSocket->new(masked => 1);
$bytes = $ws->build_frame(1, 0, 0, 0, 1, 'also works');
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,            'fin flag is set';
is $frame->[1], 0,            'rsv1 flag is not set';
is $frame->[2], 0,            'rsv2 flag is not set';
is $frame->[3], 0,            'rsv3 flag is not set';
is $frame->[4], 1,            'text frame';
is $frame->[5], 'also works', 'right payload';
isnt(
  Mojo::Transaction::WebSocket->new->build_frame(1, 0, 0, 0, 2, 'also works'),
  $bytes,
  'frames are not equal'
);

# Masked binary frame roundtrip
$ws = Mojo::Transaction::WebSocket->new(masked => 1);
$bytes = $ws->build_frame(1, 0, 0, 0, 2, 'just works');
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,            'fin flag is set';
is $frame->[1], 0,            'rsv1 flag is not set';
is $frame->[2], 0,            'rsv2 flag is not set';
is $frame->[3], 0,            'rsv3 flag is not set';
is $frame->[4], 2,            'binary frame';
is $frame->[5], 'just works', 'right payload';
isnt(
  Mojo::Transaction::WebSocket->new->build_frame(1, 0, 0, 0, 2, 'just works'),
  $bytes,
  'frames are not equal'
);

# One-character text frame roundtrip
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 0, 1, 'a');
is $bytes, "\x81\x01\x61", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,   'fin flag is set';
is $frame->[1], 0,   'rsv1 flag is not set';
is $frame->[2], 0,   'rsv2 flag is not set';
is $frame->[3], 0,   'rsv3 flag is not set';
is $frame->[4], 1,   'text frame';
is $frame->[5], 'a', 'right payload';
is $ws->build_frame(1, 0, 0, 0, 1, 'a'), $bytes, 'frames are equal';

# One-byte binary frame roundtrip
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 0, 2, 'a');
is $bytes, "\x82\x01\x61", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,   'fin flag is set';
is $frame->[1], 0,   'rsv1 flag is not set';
is $frame->[2], 0,   'rsv2 flag is not set';
is $frame->[3], 0,   'rsv3 flag is not set';
is $frame->[4], 2,   'binary frame';
is $frame->[5], 'a', 'right payload';
is $bytes = $ws->build_frame(1, 0, 0, 0, 2, 'a'), $bytes, 'frames are equal';

# 16-bit text frame roundtrip
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 0, 1, 'hi' x 10000);
is $bytes, "\x81\x7e\x4e\x20" . ("\x68\x69" x 10000), 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1, 'fin flag is set';
is $frame->[1], 0, 'rsv1 flag is not set';
is $frame->[2], 0, 'rsv2 flag is not set';
is $frame->[3], 0, 'rsv3 flag is not set';
is $frame->[4], 1, 'text frame';
is $frame->[5], 'hi' x 10000, 'right payload';
is $ws->build_frame(1, 0, 0, 0, 1, 'hi' x 10000), $bytes, 'frames are equal';

# 64-bit text frame roundtrip
$ws = Mojo::Transaction::WebSocket->new(max_websocket_size => 500000);
$bytes = $ws->build_frame(1, 0, 0, 0, 1, 'hi' x 200000);
is $bytes, "\x81\x7f\x00\x00\x00\x00\x00\x06\x1a\x80" . ("\x68\x69" x 200000),
  'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1, 'fin flag is set';
is $frame->[1], 0, 'rsv1 flag is not set';
is $frame->[2], 0, 'rsv2 flag is not set';
is $frame->[3], 0, 'rsv3 flag is not set';
is $frame->[4], 1, 'text frame';
is $frame->[5], 'hi' x 200000, 'right payload';
is $ws->build_frame(1, 0, 0, 0, 1, 'hi' x 200000), $bytes, 'frames are equal';

# Empty text frame roundtrip
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 0, 1, '');
is $bytes, "\x81\x00", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,  'fin flag is set';
is $frame->[1], 0,  'rsv1 flag is not set';
is $frame->[2], 0,  'rsv2 flag is not set';
is $frame->[3], 0,  'rsv3 flag is not set';
is $frame->[4], 1,  'text frame';
is $frame->[5], '', 'no payload';
is $ws->build_frame(1, 0, 0, 0, 1, ''), $bytes, 'frames are equal';

# Empty close frame roundtrip
$ws = Mojo::Transaction::WebSocket->new;
$bytes = $ws->build_frame(1, 0, 0, 0, 8, '');
is $bytes, "\x88\x00", 'right frame';
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,  'fin flag is set';
is $frame->[1], 0,  'rsv1 flag is not set';
is $frame->[2], 0,  'rsv2 flag is not set';
is $frame->[3], 0,  'rsv3 flag is not set';
is $frame->[4], 8,  'close frame';
is $frame->[5], '', 'no payload';
is $ws->build_frame(1, 0, 0, 0, 8, ''), $bytes, 'frames are equal';

# Masked empty binary frame roundtrip
$ws = Mojo::Transaction::WebSocket->new(masked => 1);
$bytes = $ws->build_frame(1, 0, 0, 0, 2, '');
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1,  'fin flag is set';
is $frame->[1], 0,  'rsv1 flag is not set';
is $frame->[2], 0,  'rsv2 flag is not set';
is $frame->[3], 0,  'rsv3 flag is not set';
is $frame->[4], 2,  'binary frame';
is $frame->[5], '', 'no payload';
isnt(Mojo::Transaction::WebSocket->new->build_frame(1, 0, 0, 0, 2, ''),
  $bytes, 'frames are not equal');

# Compressed binary message roundtrip
$ws = Mojo::Transaction::WebSocket->new(compressed => 1);
$bytes = $ws->build_message({binary => 'just works'});
$frame = $ws->parse_frame(\($dummy = $bytes));
is $frame->[0], 1, 'fin flag is set';
is $frame->[1], 1, 'rsv1 flag is set';
is $frame->[2], 0, 'rsv2 flag is not set';
is $frame->[3], 0, 'rsv3 flag is not set';
is $frame->[4], 2, 'binary frame';
ok $frame->[5], 'has payload';
isnt(
  Mojo::Transaction::WebSocket->new->build_message({binary => 'just works'}),
  $bytes, 'messages are not equal');

done_testing();
