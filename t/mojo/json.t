package JSONTest;
use Mojo::Base -base;

has 'something' => sub { {} };

sub TO_JSON { shift->something }

package main;
use Mojo::Base -strict;

use Test::More;
use Mojo::ByteStream 'b';
use Mojo::JSON qw(decode_json encode_json from_json j to_json);
use Mojo::Util 'encode';
use Scalar::Util 'dualvar';

# Decode array
my $array = decode_json '[]';
is_deeply $array, [], 'decode []';
$array = decode_json '[ [ ]]';
is_deeply $array, [[]], 'decode [ [ ]]';

# Decode number
$array = decode_json '[0]';
is_deeply $array, [0], 'decode [0]';
$array = decode_json '[1]';
is_deeply $array, [1], 'decode [1]';
$array = decode_json '[ "-122.026020" ]';
is_deeply $array, ['-122.026020'], 'decode [ -122.026020 ]';
$array = decode_json '[ -122.026020 ]';
is_deeply $array, ['-122.02602'], 'decode [ -122.026020 ]';
$array = decode_json '[0.0]';
cmp_ok $array->[0], '==', 0, 'value is 0';
$array = decode_json '[0e0]';
cmp_ok $array->[0], '==', 0, 'value is 0';
$array = decode_json '[1,-2]';
is_deeply $array, [1, -2], 'decode [1,-2]';
$array = decode_json '["10e12" , [2 ]]';
is_deeply $array, ['10e12', [2]], 'decode ["10e12" , [2 ]]';
$array = decode_json '[10e12 , [2 ]]';
is_deeply $array, [10000000000000, [2]], 'decode [10e12 , [2 ]]';
$array = decode_json '[37.7668 , [ 20 ]] ';
is_deeply $array, [37.7668, [20]], 'decode [37.7668 , [ 20 ]] ';
$array = decode_json '[1e3]';
cmp_ok $array->[0], '==', 1e3, 'value is 1e3';
my $value = decode_json '0';
cmp_ok $value, '==', 0, 'decode 0';
$value = decode_json '23.3';
cmp_ok $value, '==', 23.3, 'decode 23.3';

# Decode name
$array = decode_json '[true]';
is_deeply $array, [Mojo::JSON->true], 'decode [true]';
$array = decode_json '[null]';
is_deeply $array, [undef], 'decode [null]';
$array = decode_json '[true, false]';
is_deeply $array, [Mojo::JSON->true, Mojo::JSON->false],
  'decode [true, false]';
$value = decode_json 'true';
is $value, Mojo::JSON->true, 'decode true';
$value = decode_json 'false';
is $value, Mojo::JSON->false, 'decode false';
$value = decode_json 'null';
is $value, undef, 'decode null';

# Decode string
$array = decode_json '[" "]';
is_deeply $array, [' '], 'decode [" "]';
$array = decode_json '["hello world!"]';
is_deeply $array, ['hello world!'], 'decode ["hello world!"]';
$array = decode_json '["hello\nworld!"]';
is_deeply $array, ["hello\nworld!"], 'decode ["hello\nworld!"]';
$array = decode_json '["hello\t\"world!"]';
is_deeply $array, ["hello\t\"world!"], 'decode ["hello\t\"world!"]';
$array = decode_json '["hello\u0152world\u0152!"]';
is_deeply $array, ["hello\x{0152}world\x{0152}!"],
  'decode ["hello\u0152world\u0152!"]';
$array = decode_json '["0."]';
is_deeply $array, ['0.'], 'decode ["0."]';
$array = decode_json '[" 0"]';
is_deeply $array, [' 0'], 'decode [" 0"]';
$array = decode_json '["1"]';
is_deeply $array, ['1'], 'decode ["1"]';
$array = decode_json '["\u0007\b\/\f\r"]';
is_deeply $array, ["\a\b/\f\r"], 'decode ["\u0007\b\/\f\r"]';
$value = decode_json '""';
is $value, '', 'decode ""';
$value = decode_json '"hell\no"';
is $value, "hell\no", 'decode "hell\no"';

# Decode object
my $hash = decode_json '{}';
is_deeply $hash, {}, 'decode {}';
$hash = decode_json '{"foo": "bar"}';
is_deeply $hash, {foo => 'bar'}, 'decode {"foo": "bar"}';
$hash = decode_json '{"foo": [23, "bar"]}';
is_deeply $hash, {foo => [qw(23 bar)]}, 'decode {"foo": [23, "bar"]}';

# Decode full spec example
$hash = decode_json <<EOF;
{
   "Image": {
       "Width":  800,
       "Height": 600,
       "Title":  "View from 15th Floor",
       "Thumbnail": {
           "Url":    "http://www.example.com/image/481989943",
           "Height": 125,
           "Width":  "100"
       },
       "IDs": [116, 943, 234, 38793]
    }
}
EOF
is $hash->{Image}{Width},  800,                    'right value';
is $hash->{Image}{Height}, 600,                    'right value';
is $hash->{Image}{Title},  'View from 15th Floor', 'right value';
is $hash->{Image}{Thumbnail}{Url}, 'http://www.example.com/image/481989943',
  'right value';
is $hash->{Image}{Thumbnail}{Height}, 125, 'right value';
is $hash->{Image}{Thumbnail}{Width},  100, 'right value';
is $hash->{Image}{IDs}[0], 116,   'right value';
is $hash->{Image}{IDs}[1], 943,   'right value';
is $hash->{Image}{IDs}[2], 234,   'right value';
is $hash->{Image}{IDs}[3], 38793, 'right value';

# Encode array
my $bytes = encode_json [];
is $bytes, '[]', 'encode []';
$bytes = encode_json [[]];
is $bytes, '[[]]', 'encode [[]]';
$bytes = encode_json [[], []];
is $bytes, '[[],[]]', 'encode [[], []]';
$bytes = encode_json [[], [[]], []];
is $bytes, '[[],[[]],[]]', 'encode [[], [[]], []]';

# Encode string
$bytes = encode_json ['foo'];
is $bytes, '["foo"]', 'encode [\'foo\']';
$bytes = encode_json ["hello\nworld!"];
is $bytes, '["hello\nworld!"]', 'encode ["hello\nworld!"]';
$bytes = encode_json ["hello\t\"world!"];
is $bytes, '["hello\t\"world!"]', 'encode ["hello\t\"world!"]';
$bytes = encode_json ["hello\x{0003}\x{0152}world\x{0152}!"];
is b($bytes)->decode('UTF-8'), "[\"hello\\u0003\x{0152}world\x{0152}!\"]",
  'encode ["hello\x{0003}\x{0152}world\x{0152}!"]';
$bytes = encode_json ["123abc"];
is $bytes, '["123abc"]', 'encode ["123abc"]';
$bytes = encode_json ["\x00\x1f \a\b/\f\r"];
is $bytes, '["\\u0000\\u001F \\u0007\\b/\f\r"]',
  'encode ["\x00\x1f \a\b/\f\r"]';
$bytes = encode_json '';
is $bytes, '""', 'encode ""';
$bytes = encode_json "hell\no";
is $bytes, '"hell\no"', 'encode "hell\no"';

# Encode object
$bytes = encode_json {};
is $bytes, '{}', 'encode {}';
$bytes = encode_json {foo => {}};
is $bytes, '{"foo":{}}', 'encode {foo => {}}';
$bytes = encode_json {foo => 'bar'};
is $bytes, '{"foo":"bar"}', 'encode {foo => \'bar\'}';
$bytes = encode_json {foo => []};
is $bytes, '{"foo":[]}', 'encode {foo => []}';
$bytes = encode_json {foo => ['bar']};
is $bytes, '{"foo":["bar"]}', 'encode {foo => [\'bar\']}';

# Encode name
$bytes = encode_json [Mojo::JSON->true];
is $bytes, '[true]', 'encode [Mojo::JSON->true]';
$bytes = encode_json [undef];
is $bytes, '[null]', 'encode [undef]';
$bytes = encode_json [Mojo::JSON->true, Mojo::JSON->false];
is $bytes, '[true,false]', 'encode [Mojo::JSON->true, Mojo::JSON->false]';
$bytes = encode_json(Mojo::JSON->true);
is $bytes, 'true', 'encode Mojo::JSON->true';
$bytes = encode_json(Mojo::JSON->false);
is $bytes, 'false', 'encode Mojo::JSON->false';
$bytes = encode_json undef;
is $bytes, 'null', 'encode undef';

# Encode number
$bytes = encode_json [1];
is $bytes, '[1]', 'encode [1]';
$bytes = encode_json ["1"];
is $bytes, '["1"]', 'encode ["1"]';
$bytes = encode_json ['-122.026020'];
is $bytes, '["-122.026020"]', 'encode [\'-122.026020\']';
$bytes = encode_json [-122.026020];
is $bytes, '[-122.02602]', 'encode [-122.026020]';
$bytes = encode_json [1, -2];
is $bytes, '[1,-2]', 'encode [1, -2]';
$bytes = encode_json ['10e12', [2]];
is $bytes, '["10e12",[2]]', 'encode [\'10e12\', [2]]';
$bytes = encode_json [10e12, [2]];
is $bytes, '[10000000000000,[2]]', 'encode [10e12, [2]]';
$bytes = encode_json [37.7668, [20]];
is $bytes, '[37.7668,[20]]', 'encode [37.7668, [20]]';
$bytes = encode_json 0;
is $bytes, '0', 'encode 0';
$bytes = encode_json 23.3;
is $bytes, '23.3', 'encode 23.3';

# Faihu roundtrip
$bytes = j(["\x{10346}"]);
is b($bytes)->decode('UTF-8'), "[\"\x{10346}\"]", 'encode ["\x{10346}"]';
$array = j($bytes);
is_deeply $array, ["\x{10346}"], 'successful roundtrip';

# Decode faihu surrogate pair
$array = decode_json '["\\ud800\\udf46"]';
is_deeply $array, ["\x{10346}"], 'decode [\"\\ud800\\udf46\"]';

# Decode object with duplicate keys
$hash = decode_json '{"foo": 1, "foo": 2}';
is_deeply $hash, {foo => 2}, 'decode {"foo": 1, "foo": 2}';

# Complicated roudtrips
$bytes = '{"":""}';
$hash  = decode_json $bytes;
is_deeply $hash, {'' => ''}, 'decode {"":""}';
is encode_json($hash), $bytes, 're-encode';
$bytes = '[null,false,true,"",0,1]';
$array = decode_json $bytes;
is_deeply $array, [undef, Mojo::JSON->false, Mojo::JSON->true, '', 0, 1],
  'decode [null,false,true,"",0,1]';
is encode_json($array), $bytes, 're-encode';
$array = [undef, 0, 1, '', Mojo::JSON->true, Mojo::JSON->false];
$bytes = encode_json($array);
ok $bytes, 'defined value';
is_deeply decode_json($bytes), $array, 'successful roundtrip';

# Real world roundtrip
$bytes = encode_json({foo => 'c:\progra~1\mozill~1\firefox.exe'});
is $bytes, '{"foo":"c:\\\\progra~1\\\\mozill~1\\\\firefox.exe"}',
  'encode {foo => \'c:\progra~1\mozill~1\firefox.exe\'}';
$hash = decode_json $bytes;
is_deeply $hash, {foo => 'c:\progra~1\mozill~1\firefox.exe'},
  'successful roundtrip';

# Huge string
$bytes = encode_json(['a' x 32768]);
is_deeply decode_json($bytes), ['a' x 32768], 'successful roundtrip';

# u2028 and u2029
$bytes = encode_json ["\x{2028}test\x{2029}123"];
is index($bytes, b("\x{2028}")->encode), -1, 'properly escaped';
is index($bytes, b("\x{2029}")->encode), -1, 'properly escaped';
is_deeply decode_json($bytes), ["\x{2028}test\x{2029}123"],
  'successful roundtrip';

# JSON without UTF-8 encoding
is_deeply from_json('["♥"]'), ['♥'], 'characters decoded';
is to_json(['♥']), '["♥"]', 'characters encoded';
is_deeply from_json(to_json(["\xe9"])), ["\xe9"], 'successful roundtrip';

# Blessed reference
$bytes = encode_json [b('test')];
is_deeply decode_json($bytes), ['test'], 'successful roundtrip';

# Blessed reference with TO_JSON method
$bytes = encode_json(JSONTest->new);
is_deeply decode_json($bytes), {}, 'successful roundtrip';
$bytes = encode_json(
  JSONTest->new(something => {just => 'works'}, else => {not => 'working'}));
is_deeply decode_json($bytes), {just => 'works'}, 'successful roundtrip';

# Boolean shortcut
is encode_json({true  => \1}), '{"true":true}',   'encode {true => \1}';
is encode_json({false => \0}), '{"false":false}', 'encode {false => \0}';
$bytes = 'some true value';
is encode_json({true => \!!$bytes}), '{"true":true}',
  'encode true boolean from double negated reference';
is encode_json({true => \$bytes}), '{"true":true}',
  'encode true boolean from reference';
$bytes = '';
is encode_json({false => \!!$bytes}), '{"false":false}',
  'encode false boolean from double negated reference';
is encode_json({false => \$bytes}), '{"false":false}',
  'encode false boolean from reference';

# Stringify booleans
is(Mojo::JSON->true,  1, 'right value');
is(Mojo::JSON->false, 0, 'right value');

# Upgraded numbers
my $num = 3;
my $str = "$num";
is encode_json({test => [$num, $str]}), '{"test":[3,"3"]}',
  'upgraded number detected';
$num = 3.21;
$str = "$num";
is encode_json({test => [$num, $str]}), '{"test":[3.21,"3.21"]}',
  'upgraded number detected';
$str = '0 but true';
$num = 1 + $str;
is encode_json({test => [$num, $str]}), '{"test":[1,"0 but true"]}',
  'upgraded number detected';

# Upgraded string
$str = "bar";
{ no warnings 'numeric'; $num = 23 + $str }
is encode_json({test => [$num, $str]}), '{"test":[23,"bar"]}',
  'upgraded string detected';

# dualvar
my $dual = dualvar 23, 'twenty three';
is encode_json([$dual]), '["twenty three"]', 'dualvar stringified';

# Ensure numbers and strings are not upgraded
my $mixed = [3, 'three', '3', 0, "0"];
is encode_json($mixed), '[3,"three","3",0,"0"]',
  'all have been detected correctly';
is encode_json($mixed), '[3,"three","3",0,"0"]',
  'all have been detected correctly again';

# "inf" and "nan"
like encode_json({test => 9**9**9}), qr/^{"test":".*"}$/,
  'encode "inf" as string';
like encode_json({test => -sin(9**9**9)}), qr/^{"test":".*"}$/,
  'encode "nan" as string';

# "null"
my $json = Mojo::JSON->new;
is $json->decode('null'), undef, 'decode null';
ok !$json->error, 'no error';
is j('null'), undef, 'decode null';

# Errors
is $json->decode('test'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected string, array, object, number,'
  . ' boolean or null at line 0, offset 0', 'right error';
is $json->decode(b('["\\ud800"]')->encode), undef, 'syntax error';
is $json->error, 'Malformed JSON: Missing low-surrogate at line 1, offset 8',
  'right error';
is $json->decode(b('["\\udf46"]')->encode), undef, 'syntax error';
is $json->error, 'Malformed JSON: Missing high-surrogate at line 1, offset 8',
  'right error';
is $json->decode('[[]'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected comma or right square bracket while'
  . ' parsing array at line 1, offset 3', 'right error';
is $json->decode('{{}'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected string while'
  . ' parsing object at line 1, offset 1', 'right error';
is $json->decode("[\"foo\x00]"), undef, 'syntax error';
is $json->error, 'Malformed JSON: Unexpected character or invalid escape while'
  . ' parsing string at line 1, offset 5', 'right error';
is $json->decode('{"foo":"bar"{'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected comma or right curly bracket while'
  . ' parsing object at line 1, offset 12', 'right error';
is $json->decode('{"foo""bar"}'), undef, 'syntax error';
is $json->error,
  'Malformed JSON: Expected colon while parsing object at line 1, offset 6',
  'right error';
is $json->decode('[[]...'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected comma or right square bracket while'
  . ' parsing array at line 1, offset 3', 'right error';
is $json->decode('{{}...'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected string while'
  . ' parsing object at line 1, offset 1', 'right error';
is $json->decode('[nan]'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Expected string, array, object, number,'
  . ' boolean or null at line 1, offset 1', 'right error';
is $json->decode('["foo]'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Unterminated string at line 1, offset 6',
  'right error';
is $json->decode('{"foo":"bar"}lala'), undef, 'syntax error';
is $json->error, 'Malformed JSON: Unexpected data at line 1, offset 13',
  'right error';
is $json->decode(''), undef, 'missing input';
is $json->error, 'Missing or empty input', 'right error';
is $json->decode("[\"foo\",\n\"bar\"]lala"), undef, 'syntax error';
is $json->error, 'Malformed JSON: Unexpected data at line 2, offset 6',
  'right error';
is $json->decode("[\"foo\",\n\"bar\",\n\"bazra\"]lalala"), undef,
  'syntax error';
is $json->error, 'Malformed JSON: Unexpected data at line 3, offset 8',
  'right error';
is $json->decode('["♥"]'), undef, 'wide character in input';
is $json->error, 'Input is not UTF-8 encoded', 'right error';
is $json->decode(encode('Shift_JIS', 'やった')), undef, 'invalid encoding';
is $json->error, 'Input is not UTF-8 encoded', 'right error';
is j('{'), undef, 'syntax error';
eval { decode_json("[\"foo\",\n\"bar\",\n\"bazra\"]lalala") };
like $@, qr/JSON: Unexpected data at line 3, offset 8 at.*json\.t/,
  'right error';
eval { from_json("[\"foo\",\n\"bar\",\n\"bazra\"]lalala") };
like $@, qr/JSON: Unexpected data at line 3, offset 8 at.*json\.t/,
  'right error';

done_testing();
