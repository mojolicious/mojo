use Mojo::Base -strict;

use Test::More;
use Mojo::Path;
use Mojo::Util qw(encode url_escape);

subtest 'Basic functionality' => sub {
  my $path = Mojo::Path->new;
  is $path->parse('/path')->to_string, '/path', 'right path';
  is $path->to_dir,                    '/',     'right directory';
  is_deeply $path->parts, ['path'], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is $path->parse('path/')->to_string, 'path/',  'right path';
  is $path->to_dir,                    'path/',  'right directory';
  is $path->to_dir->to_abs_string,     '/path/', 'right directory';
  is_deeply $path->parts, ['path'], 'right structure';
  ok !$path->leading_slash, 'no leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  $path = Mojo::Path->new;
  is $path->to_string,     '',  'no path';
  is $path->to_abs_string, '/', 'right absolute path';
  is $path->to_route,      '/', 'right route';
};

subtest 'Advanced' => sub {
  my $path = Mojo::Path->new('/AZaz09-._~!$&\'()*+,;=:@');
  is $path->[0], 'AZaz09-._~!$&\'()*+,;=:@', 'right part';
  is $path->[1], undef,                      'no part';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is "$path", '/AZaz09-._~!$&\'()*+,;=:@', 'right path';
  push @$path, 'f/oo';
  is "$path", '/AZaz09-._~!$&\'()*+,;=:@/f%2Foo', 'right path';
};

subtest 'Unicode' => sub {
  my $path = Mojo::Path->new;
  is $path->parse('/foo/♥/bar')->to_string, '/foo/%E2%99%A5/bar', 'right path';
  is $path->to_dir,                         '/foo/%E2%99%A5/',    'right directory';
  is_deeply $path->parts, [qw(foo ♥ bar)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is $path->to_route,                                   '/foo/♥/bar',             'right route';
  is $path->parse('/foo/%E2%99%A5/~b@a:r+')->to_string, '/foo/%E2%99%A5/~b@a:r+', 'right path';
  is_deeply $path->parts, [qw(foo ♥ ~b@a:r+)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is $path->to_route, '/foo/♥/~b@a:r+', 'right route';
};

subtest 'Zero in path' => sub {
  my $path = Mojo::Path->new;
  is $path->parse('/path/0')->to_string, '/path/0', 'right path';
  is_deeply $path->parts, [qw(path 0)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  $path = Mojo::Path->new('0');
  is_deeply $path->parts, [0], 'right structure';
  is $path->to_string,     '0',  'right path';
  is $path->to_abs_string, '/0', 'right absolute path';
  is $path->to_route,      '/0', 'right route';
};

subtest 'Canonicalizing' => sub {
  my $path = Mojo::Path->new('/%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd');
  is "$path", '/%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd', 'same path';
  is_deeply $path->parts, ['', qw(.. .. .. .. .. .. .. .. .. .. etc passwd)], 'right structure';
  is "$path",             '//../../../../../../../../../../etc/passwd', 'normalized path';
  is $path->canonicalize, '/../../../../../../../../../../etc/passwd',  'canonicalized path';
  is_deeply $path->parts, [qw(.. .. .. .. .. .. .. .. .. .. etc passwd)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
};

subtest 'Canonicalizing (alternative)' => sub {
  my $path = Mojo::Path->new('%2ftest%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd');
  is "$path", '%2ftest%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd', 'same path';
  is_deeply $path->parts, [qw(test .. .. .. .. .. .. .. .. .. etc passwd)], 'right structure';
  is "$path",             '/test/../../../../../../../../../etc/passwd', 'normalized path';
  is $path->canonicalize, '/../../../../../../../../etc/passwd',         'canonicalized path';
  is_deeply $path->parts, [qw(.. .. .. .. .. .. .. .. etc passwd)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
};

subtest 'Canonicalize (triple dot)' => sub {
  my $path = Mojo::Path->new('/foo/.../.../windows/win.ini');
  is "$path", '/foo/.../.../windows/win.ini', 'same path';
  is_deeply $path->parts, [qw(foo ... ... windows win.ini)], 'right structure';
  is $path->canonicalize, '/foo/windows/win.ini', 'canonicalized path';
  is_deeply $path->parts, [qw(foo windows win.ini)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
};

subtest 'Canonicalizing (with escaped "%")' => sub {
  my $path = Mojo::Path->new('%2ftest%2f..%252f..%2f..%2f..%2f..%2fetc%2fpasswd');
  is "$path", '%2ftest%2f..%252f..%2f..%2f..%2f..%2fetc%2fpasswd', 'same path';
  is_deeply $path->parts, [qw(test ..%2f.. .. .. .. etc passwd)], 'right structure';
  is "$path",             '/test/..%252f../../../../etc/passwd', 'normalized path';
  is $path->canonicalize, '/../etc/passwd',                      'canonicalized path';
  is_deeply $path->parts, [qw(.. etc passwd)], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
};

subtest 'Contains' => sub {
  my $path = Mojo::Path->new('/foo/bar');
  ok $path->contains('/'),             'contains path';
  ok $path->contains('/foo'),          'contains path';
  ok $path->contains('/foo/bar'),      'contains path';
  ok !$path->contains('/foobar'),      'does not contain path';
  ok !$path->contains('/foo/b'),       'does not contain path';
  ok !$path->contains('/foo/bar/baz'), 'does not contain path';
  $path = Mojo::Path->new('/♥/bar');
  ok $path->contains('/♥'),     'contains path';
  ok $path->contains('/♥/bar'), 'contains path';
  ok !$path->contains('/♥foo'), 'does not contain path';
  ok !$path->contains('/foo♥'), 'does not contain path';
  $path = Mojo::Path->new('/');
  ok $path->contains('/'),     'contains path';
  ok !$path->contains('/foo'), 'does not contain path';
  $path = Mojo::Path->new('/0');
  ok $path->contains('/'),     'contains path';
  ok $path->contains('/0'),    'contains path';
  ok !$path->contains('/0/0'), 'does not contain path';
  $path = Mojo::Path->new('/0/♥.html');
  ok $path->contains('/'),          'contains path';
  ok $path->contains('/0'),         'contains path';
  ok $path->contains('/0/♥.html'),  'contains path';
  ok !$path->contains('/0/♥'),      'does not contain path';
  ok !$path->contains('/0/0.html'), 'does not contain path';
  ok !$path->contains('/0.html'),   'does not contain path';
  ok !$path->contains('/♥.html'),   'does not contain path';
};

subtest 'Merge' => sub {
  my $path = Mojo::Path->new('/foo');
  $path->merge('bar/baz');
  is "$path", '/bar/baz', 'right path';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  $path = Mojo::Path->new('/foo/');
  $path->merge('bar/baz');
  is "$path", '/foo/bar/baz', 'right path';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  $path = Mojo::Path->new('/foo/');
  $path->merge('bar/baz/');
  is "$path", '/foo/bar/baz/', 'right path';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  $path = Mojo::Path->new('/foo/');
  $path->merge('/bar/baz');
  is "$path", '/bar/baz', 'right path';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is $path->to_route, '/bar/baz', 'right route';
  $path = Mojo::Path->new('/foo/bar');
  $path->merge('/bar/baz/');
  is "$path", '/bar/baz/', 'right path';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  is $path->to_route, '/bar/baz/', 'right route';
  $path = Mojo::Path->new('foo/bar');
  $path->merge('baz/yada');
  is "$path", 'foo/baz/yada', 'right path';
  ok !$path->leading_slash,  'no leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is $path->to_route, '/foo/baz/yada', 'right route';
};

subtest 'Merge path object' => sub {
  my $charset    = 'ISO-8859-15';
  my $part       = 'b€r';
  my $part_enc   = url_escape(encode($charset, $part));
  my $parse_path = sub { Mojo::Path->new->charset($charset)->parse(@_) };

  for my $has_trailing_slash (!!0, !!1) {
    my $trailing_slash      = $has_trailing_slash ? '/' : '';
    my $trailing_slash_diag = 'has'.($has_trailing_slash ? '' : ' no').' trailing slash';
    my $path = $parse_path->("/$part_enc/");
    $path->merge($parse_path->($part_enc.$trailing_slash));
    is_deeply $path->parts, [($part) x 2],              'right structure';
    is "$path", "/$part_enc/$part_enc".$trailing_slash, 'right path';
    ok $path->leading_slash,                            'has leading slash';
    is $path->trailing_slash, $has_trailing_slash,      $trailing_slash_diag;
    is $path->to_route, "/$part/$part".$trailing_slash, 'right route';
    $path = $parse_path->("/foo/")->merge($parse_path->("/$part_enc".$trailing_slash));
    is_deeply $path->parts, [$part],                    'right structure';
    is "$path", "/$part_enc".$trailing_slash,           'right path';
    ok $path->leading_slash,                            'has leading slash';
    is $path->trailing_slash, $has_trailing_slash,      $trailing_slash_diag;
    is $path->to_route, "/$part".$trailing_slash,       'right route';
  }
};

subtest 'Empty path elements' => sub {
  my $path = Mojo::Path->new('//');
  is "$path", '//', 'right path';
  is_deeply $path->parts, [], 'no parts';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  is "$path", '//', 'right normalized path';
  $path = Mojo::Path->new('%2F%2f');
  is "$path", '%2F%2f', 'right path';
  is_deeply $path->parts, [], 'no parts';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  is "$path", '//', 'right normalized path';
  $path = Mojo::Path->new('/foo//bar/23/');
  is "$path", '/foo//bar/23/', 'right path';
  is_deeply $path->parts, ['foo', '', 'bar', 23], 'right structure';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  $path = Mojo::Path->new('//foo/bar/23/');
  is "$path", '//foo/bar/23/', 'right path';
  is_deeply $path->parts, ['', 'foo', 'bar', 23], 'right structure';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  $path = Mojo::Path->new('/foo///bar/23/');
  is "$path", '/foo///bar/23/', 'right path';
  is_deeply $path->parts, ['foo', '', '', 'bar', 23], 'right structure';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  $path = Mojo::Path->new('///foo/bar/23/');
  is "$path", '///foo/bar/23/', 'right path';
  is_deeply $path->parts, ['', '', 'foo', 'bar', 23], 'right structure';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
  $path = Mojo::Path->new('///foo///bar/23///');
  is "$path", '///foo///bar/23///', 'right path';
  is_deeply $path->parts, ['', '', 'foo', '', '', 'bar', 23, '', ''], 'right structure';
  ok $path->leading_slash,  'has leading slash';
  ok $path->trailing_slash, 'has trailing slash';
};

subtest 'Escaped slash' => sub {
  my $path = Mojo::Path->new->parts(['foo/bar']);
  is_deeply $path->parts, ['foo/bar'], 'right structure';
  is "$path",              'foo%2Fbar',  'right path';
  is $path->to_string,     'foo%2Fbar',  'right path';
  is $path->to_abs_string, '/foo%2Fbar', 'right absolute path';
  is $path->to_route,      '/foo/bar',   'right route';
};

subtest 'Unchanged path' => sub {
  my $path = Mojo::Path->new('/foob%E4r/-._~!$&\'()*+,;=:@');
  is_deeply $path->clone->parts, ["foob\xe4r", '-._~!$&\'()*+,;=:@'], 'right structure';
  ok $path->contains("/foob\xe4r"),                     'contains path';
  ok $path->contains("/foob\xe4r/-._~!\$&'()*+,;=:@"),  'contains path';
  ok !$path->contains("/foob\xe4r/-._~!\$&'()*+,;=:."), 'does not contain path';
  is $path->to_string,            '/foob%E4r/-._~!$&\'()*+,;=:@',  'right path';
  is $path->to_abs_string,        '/foob%E4r/-._~!$&\'()*+,;=:@',  'right absolute path';
  is $path->to_route,             "/foob\xe4r/-._~!\$&'()*+,;=:@", 'right route';
  is $path->clone->to_string,     '/foob%E4r/-._~!$&\'()*+,;=:@',  'right path';
  is $path->clone->to_abs_string, '/foob%E4r/-._~!$&\'()*+,;=:@',  'right absolute path';
  is $path->clone->to_route,      "/foob\xe4r/-._~!\$&'()*+,;=:@", 'right route';
};

subtest 'Reuse path' => sub {
  my $path = Mojo::Path->new('/foob%E4r');
  is $path->to_string, '/foob%E4r', 'right path';
  is_deeply $path->parts, ["foob\xe4r"], 'right structure';
  $path->parse('/foob%E4r');
  is $path->to_string, '/foob%E4r', 'right path';
  is_deeply $path->parts, ["foob\xe4r"], 'right structure';
};

subtest 'Latin-1' => sub {
  my $path = Mojo::Path->new->charset('Latin-1')->parse('/foob%E4r');
  is_deeply $path->parts, ['foobär'], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is "$path",                 '/foob%E4r', 'right path';
  is $path->to_string,        '/foob%E4r', 'right path';
  is $path->to_abs_string,    '/foob%E4r', 'right absolute path';
  is $path->to_route,         '/foobär',   'right route';
  is $path->clone->to_string, '/foob%E4r', 'right path';
};

subtest 'No charset' => sub {
  my $path = Mojo::Path->new->charset(undef)->parse('/%E4');
  is_deeply $path->parts, ["\xe4"], 'right structure';
  ok $path->leading_slash,   'has leading slash';
  ok !$path->trailing_slash, 'no trailing slash';
  is "$path",                 '/%E4',  'right path';
  is $path->to_route,         "/\xe4", 'right route';
  is $path->clone->to_string, '/%E4',  'right path';
};

done_testing();
