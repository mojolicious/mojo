use Mojo::Base -strict;

use Test::More;
use Mojo::Transaction::WebSocket;
use Mojo::WebSocket qw(WS_BINARY WS_CLOSE WS_CONTINUATION WS_PING WS_PONG WS_TEXT), qw(build_frame parse_frame);

subtest 'Simple text frame roundtrip' => sub {
  my $bytes = build_frame 0, 1, 0, 0, 0, WS_TEXT, 'whatever';
  is $bytes, "\x81\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               1,          'fin flag is set';
  is $frame->[1],                               0,          'rsv1 flag is not set';
  is $frame->[2],                               0,          'rsv2 flag is not set';
  is $frame->[3],                               0,          'rsv3 flag is not set';
  is $frame->[4],                               1,          'text frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 1, 0, 0, 0, 1, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple ping frame roundtrip' => sub {
  my $bytes = build_frame 0, 1, 0, 0, 0, WS_PING, 'whatever';
  is $bytes, "\x89\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               1,          'fin flag is set';
  is $frame->[1],                               0,          'rsv1 flag is not set';
  is $frame->[2],                               0,          'rsv2 flag is not set';
  is $frame->[3],                               0,          'rsv3 flag is not set';
  is $frame->[4],                               9,          'ping frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 1, 0, 0, 0, 9, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple pong frame roundtrip' => sub {
  my $bytes = build_frame 0, 1, 0, 0, 0, WS_PONG, 'whatever';
  is $bytes, "\x8a\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                                1,          'fin flag is set';
  is $frame->[1],                                0,          'rsv1 flag is not set';
  is $frame->[2],                                0,          'rsv2 flag is not set';
  is $frame->[3],                                0,          'rsv3 flag is not set';
  is $frame->[4],                                10,         'pong frame';
  is $frame->[5],                                'whatever', 'right payload';
  is build_frame(0, 1, 0, 0, 0, 10, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple text frame roundtrip with all flags set' => sub {
  my $bytes = build_frame 0, 1, 1, 1, 1, 1, 'whatever';
  is $bytes, "\xf1\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               1,          'fin flag is set';
  is $frame->[1],                               1,          'rsv1 flag is set';
  is $frame->[2],                               1,          'rsv2 flag is set';
  is $frame->[3],                               1,          'rsv3 flag is set';
  is $frame->[4],                               1,          'text frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 1, 1, 1, 1, 1, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple text frame roundtrip without FIN bit' => sub {
  my $bytes = build_frame 0, 0, 0, 0, 0, 1, 'whatever';
  is $bytes, "\x01\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               0,          'fin flag is not set';
  is $frame->[1],                               0,          'rsv1 flag is not set';
  is $frame->[2],                               0,          'rsv2 flag is not set';
  is $frame->[3],                               0,          'rsv3 flag is not set';
  is $frame->[4],                               1,          'text frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 0, 0, 0, 0, 1, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple text frame roundtrip with RSV1 flags set' => sub {
  my $bytes = build_frame(0, 1, 1, 0, 0, 1, 'whatever');
  is $bytes, "\xc1\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               1,          'fin flag is set';
  is $frame->[1],                               1,          'rsv1 flag is set';
  is $frame->[2],                               0,          'rsv2 flag is not set';
  is $frame->[3],                               0,          'rsv3 flag is not set';
  is $frame->[4],                               1,          'text frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 1, 1, 0, 0, 1, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple continuation frame roundtrip with RSV2 flags set' => sub {
  my $bytes = build_frame(0, 1, 0, 1, 0, WS_CONTINUATION, 'whatever');
  is $bytes, "\xa0\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               1,          'fin flag is set';
  is $frame->[1],                               0,          'rsv1 flag is not set';
  is $frame->[2],                               1,          'rsv2 flag is set';
  is $frame->[3],                               0,          'rsv3 flag is not set';
  is $frame->[4],                               0,          'continuation frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 1, 0, 1, 0, 0, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple text frame roundtrip with RSV3 flags set' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 1, 1, 'whatever');
  is $bytes, "\x91\x08\x77\x68\x61\x74\x65\x76\x65\x72", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                               1,          'fin flag is set';
  is $frame->[1],                               0,          'rsv1 flag is not set';
  is $frame->[2],                               0,          'rsv2 flag is not set';
  is $frame->[3],                               1,          'rsv3 flag is set';
  is $frame->[4],                               1,          'text frame';
  is $frame->[5],                               'whatever', 'right payload';
  is build_frame(0, 1, 0, 0, 1, 1, 'whatever'), $bytes,     'frames are equal';
};

subtest 'Simple binary frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, WS_BINARY, 'works');
  is $bytes, "\x82\x05\x77\x6f\x72\x6b\x73", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                                     1,       'fin flag is set';
  is $frame->[1],                                     0,       'rsv1 flag is not set';
  is $frame->[2],                                     0,       'rsv2 flag is not set';
  is $frame->[3],                                     0,       'rsv3 flag is not set';
  is $frame->[4],                                     2,       'binary frame';
  is $frame->[5],                                     'works', 'right payload';
  is $bytes = build_frame(0, 1, 0, 0, 0, 2, 'works'), $bytes,  'frames are equal';
};

subtest 'Masked text frame roundtrip' => sub {
  my $bytes = build_frame 1, 1, 0, 0, 0, 1, 'also works';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0], 1,            'fin flag is set';
  is $frame->[1], 0,            'rsv1 flag is not set';
  is $frame->[2], 0,            'rsv2 flag is not set';
  is $frame->[3], 0,            'rsv3 flag is not set';
  is $frame->[4], 1,            'text frame';
  is $frame->[5], 'also works', 'right payload';
  isnt(build_frame(0, 1, 0, 0, 0, 2, 'also works'), $bytes, 'frames are not equal');
};

subtest 'Masked binary frame roundtrip' => sub {
  my $bytes = build_frame(1, 1, 0, 0, 0, 2, 'just works');
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0], 1,            'fin flag is set';
  is $frame->[1], 0,            'rsv1 flag is not set';
  is $frame->[2], 0,            'rsv2 flag is not set';
  is $frame->[3], 0,            'rsv3 flag is not set';
  is $frame->[4], 2,            'binary frame';
  is $frame->[5], 'just works', 'right payload';
  isnt(build_frame(0, 1, 0, 0, 0, 2, 'just works'), $bytes, 'frames are not equal');
};

subtest 'One-character text frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, 1, 'a');
  is $bytes, "\x81\x01\x61", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                        1,      'fin flag is set';
  is $frame->[1],                        0,      'rsv1 flag is not set';
  is $frame->[2],                        0,      'rsv2 flag is not set';
  is $frame->[3],                        0,      'rsv3 flag is not set';
  is $frame->[4],                        1,      'text frame';
  is $frame->[5],                        'a',    'right payload';
  is build_frame(0, 1, 0, 0, 0, 1, 'a'), $bytes, 'frames are equal';
};

subtest 'One-byte binary frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, 2, 'a');
  is $bytes, "\x82\x01\x61", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                                 1,      'fin flag is set';
  is $frame->[1],                                 0,      'rsv1 flag is not set';
  is $frame->[2],                                 0,      'rsv2 flag is not set';
  is $frame->[3],                                 0,      'rsv3 flag is not set';
  is $frame->[4],                                 2,      'binary frame';
  is $frame->[5],                                 'a',    'right payload';
  is $bytes = build_frame(0, 1, 0, 0, 0, 2, 'a'), $bytes, 'frames are equal';
};

subtest '16-bit text frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, 1, 'hi' x 10000);
  is $bytes, "\x81\x7e\x4e\x20" . ("\x68\x69" x 10000), 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                                 1,            'fin flag is set';
  is $frame->[1],                                 0,            'rsv1 flag is not set';
  is $frame->[2],                                 0,            'rsv2 flag is not set';
  is $frame->[3],                                 0,            'rsv3 flag is not set';
  is $frame->[4],                                 1,            'text frame';
  is $frame->[5],                                 'hi' x 10000, 'right payload';
  is build_frame(0, 1, 0, 0, 0, 1, 'hi' x 10000), $bytes,       'frames are equal';
};

subtest '64-bit text frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, 1, 'hi' x 200000);
  is $bytes, "\x81\x7f\x00\x00\x00\x00\x00\x06\x1a\x80" . ("\x68\x69" x 200000), 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 500000;
  is $frame->[0],                                  1,             'fin flag is set';
  is $frame->[1],                                  0,             'rsv1 flag is not set';
  is $frame->[2],                                  0,             'rsv2 flag is not set';
  is $frame->[3],                                  0,             'rsv3 flag is not set';
  is $frame->[4],                                  1,             'text frame';
  is $frame->[5],                                  'hi' x 200000, 'right payload';
  is build_frame(0, 1, 0, 0, 0, 1, 'hi' x 200000), $bytes,        'frames are equal';
};

subtest 'Empty text frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, 1, '');
  is $bytes, "\x81\x00", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                       1,      'fin flag is set';
  is $frame->[1],                       0,      'rsv1 flag is not set';
  is $frame->[2],                       0,      'rsv2 flag is not set';
  is $frame->[3],                       0,      'rsv3 flag is not set';
  is $frame->[4],                       1,      'text frame';
  is $frame->[5],                       '',     'no payload';
  is build_frame(0, 1, 0, 0, 0, 1, ''), $bytes, 'frames are equal';
};

subtest 'Empty close frame roundtrip' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, WS_CLOSE, '');
  is $bytes, "\x88\x00", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0],                       1,      'fin flag is set';
  is $frame->[1],                       0,      'rsv1 flag is not set';
  is $frame->[2],                       0,      'rsv2 flag is not set';
  is $frame->[3],                       0,      'rsv3 flag is not set';
  is $frame->[4],                       8,      'close frame';
  is $frame->[5],                       '',     'no payload';
  is build_frame(0, 1, 0, 0, 0, 8, ''), $bytes, 'frames are equal';
};

subtest 'Masked empty binary frame roundtrip' => sub {
  my $bytes = build_frame(1, 1, 0, 0, 0, 2, '');
  my $frame = parse_frame \(my $dummy = $bytes), 262144;
  is $frame->[0], 1,  'fin flag is set';
  is $frame->[1], 0,  'rsv1 flag is not set';
  is $frame->[2], 0,  'rsv2 flag is not set';
  is $frame->[3], 0,  'rsv3 flag is not set';
  is $frame->[4], 2,  'binary frame';
  is $frame->[5], '', 'no payload';
  isnt(build_frame(0, 1, 0, 0, 0, 2, ''), $bytes, 'frames are not equal');
};

subtest 'Size limit' => sub {
  my $bytes = build_frame(0, 1, 0, 0, 0, WS_BINARY, 'works');
  is $bytes, "\x82\x05\x77\x6f\x72\x6b\x73", 'right frame';
  my $frame = parse_frame \(my $dummy = $bytes), 4;
  ok $frame,      'true';
  ok !ref $frame, 'not a reference';
};

subtest 'Incomplete frame' => sub {
  is parse_frame(\(my $dummy = "\x82\x05\x77\x6f\x72\x6b"), 262144), undef, 'incomplete frame';
};

subtest 'Fragmented message' => sub {
  my $fragmented = Mojo::Transaction::WebSocket->new;
  my $text;
  $fragmented->on(text => sub { $text = pop });
  $fragmented->parse_message([0, 0, 0, 0, WS_TEXT, 'wo']);
  ok !$text, 'text event has not been emitted yet';
  $fragmented->parse_message([0, 0, 0, 0, WS_CONTINUATION, 'r']);
  ok !$text, 'text event has not been emitted yet';
  $fragmented->parse_message([1, 0, 0, 0, WS_CONTINUATION, 'ks!']);
  is $text, 'works!', 'right payload';
};

subtest 'Compressed binary message' => sub {
  my $compressed = Mojo::Transaction::WebSocket->new({compressed => 1});
  my $frame      = $compressed->build_message({binary => 'just works'});
  is $frame->[0], 1,         'fin flag is set';
  is $frame->[1], 1,         'rsv1 flag is set';
  is $frame->[2], 0,         'rsv2 flag is not set';
  is $frame->[3], 0,         'rsv3 flag is not set';
  is $frame->[4], WS_BINARY, 'binary frame';
  ok $frame->[5], 'has payload';
  my $payload = $compressed->build_message({binary => 'just works'})->[5];
  isnt $frame->[5], $payload, 'different payload';
  ok length $frame->[5] > length $payload, 'payload is smaller';
  my $uncompressed = Mojo::Transaction::WebSocket->new;
  my $frame2       = $uncompressed->build_message({binary => 'just works'});
  is $frame2->[0], 1,         'fin flag is set';
  is $frame2->[1], 0,         'rsv1 flag is not set';
  is $frame2->[2], 0,         'rsv2 flag is not set';
  is $frame2->[3], 0,         'rsv3 flag is not set';
  is $frame2->[4], WS_BINARY, 'binary frame';
  ok $frame2->[5], 'has payload';
  isnt $frame->[5], $frame2->[5],                                                'different payload';
  is $frame2->[5],  $uncompressed->build_message({binary => 'just works'})->[5], 'same payload';
};

subtest 'Compressed fragmented message' => sub {
  my $fragmented_compressed = Mojo::Transaction::WebSocket->new({compressed => 1});
  my $text                  = undef;
  $fragmented_compressed->on(message => sub { $text = pop });
  my $compressed_payload = $fragmented_compressed->build_message({text => 'just works'})->[5];
  ok !$text, 'message event has not been emitted yet';
  $fragmented_compressed->parse_message([0, 1, 0, 0, WS_TEXT, substr($compressed_payload, 0, 3)]);
  ok !$text, 'message event has not been emitted yet';
  $fragmented_compressed->parse_message([0, 0, 0, 0, WS_CONTINUATION, substr($compressed_payload, 3, 3)]);
  ok !$text, 'message event has not been emitted yet';
  $fragmented_compressed->parse_message([1, 0, 0, 0, WS_CONTINUATION, substr($compressed_payload, 6)]);
  is $text, 'just works', 'decoded correctly';
};

done_testing();
