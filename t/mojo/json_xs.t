use Mojo::Base -strict;

use Test::More;
use Mojo::JSON qw(decode_json encode_json false from_json j to_json true);

BEGIN {
  plan skip_all => 'Cpanel::JSON::XS 4.09+ required for this test!'
    unless Mojo::JSON->JSON_XS;
}

package JSONTest;
use Mojo::Base -base;

has 'something' => sub { {} };

sub TO_JSON { shift->something }

package main;

use Mojo::ByteStream;
use Mojo::Util qw(decode encode);

# Basics
my $array = decode_json '[]';
is_deeply $array, [], 'decode_json';
my $bytes = encode_json [];
is $bytes, '[]', 'encode_json';
$array = from_json '[]';
is_deeply $array, [], 'from_json';
my $chars = to_json [];
is $chars, '[]', 'to_json';
$array = j('[]');
is_deeply $array, [], 'j() decode';
$bytes = j([]);
is $bytes, '[]', 'j() encode';
is encode_json([true]),  '[true]',  'true';
is encode_json([false]), '[false]', 'false';

# "utf8"
is_deeply decode_json(encode('UTF-8', '["♥"]')), ['♥'], 'bytes decoded';
is encode_json(['♥']), encode('UTF-8', '["♥"]'), 'bytes encoded';
is_deeply from_json('["♥"]'), ['♥'], 'characters decoded';
is to_json(['♥']), '["♥"]', 'characters encoded';

# "canonical"
is_deeply encode_json({a => 1, b => 2, c => 3}), '{"a":1,"b":2,"c":3}',
  'canonical object';

# "allow_nonref"
is_deeply encode_json(true), 'true', 'bare true';

# "allow_unknown"
is_deeply encode_json(sub { }), 'null', 'unknown reference';

# "allow_blessed"
is_deeply encode_json(Mojo::ByteStream->new('test')), '"test"',
  'blessed reference';

# "convert_blessed"
$bytes = encode_json(JSONTest->new);
is_deeply decode_json($bytes), {}, 'successful roundtrip';
$bytes = encode_json(JSONTest->new(
  something => {just => 'works'}, else => {not => 'working'}));
is_deeply decode_json($bytes), {just => 'works'}, 'successful roundtrip';

# "stringify_infnan"
like encode_json({test => 9**9**9}), qr/^{"test":".*"}$/,
  'encode "inf" as string';
like encode_json({test => -sin(9**9**9)}), qr/^{"test":".*"}$/,
  'encode "nan" as string';

# "escape_slash"
is_deeply encode_json('/test/123'), '"\/test\/123"', 'escaped slash';

# "allow_dupkeys"
is_deeply decode_json('{"test":1,"test":2}'), {test => 2},
  'no duplicate keys error';

done_testing();
