use Mojo::Base -strict;

use Test::More;
use Mojo::JSON qw(decode_json encode_json false from_json j to_json true);
use Mojo::Util qw(decode encode);

BEGIN {
  plan skip_all => 'Cpanel::JSON::XS 4.04+ required for this test!'
    unless Mojo::JSON->JSON_XS;
}

# Basics
my $array = decode_json '[]';
is_deeply $array, [], 'decode_jsom';
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

done_testing();
