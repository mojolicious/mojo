use Mojo::Base -strict;

use Test::More;
use Mojo::Path;

# Basic functionality
my $path = Mojo::Path->new;
is $path->parse('/path')->to_string, '/path', 'right path';
is $path->parts->[0], 'path', 'right part';
is $path->parts->[1], undef,  'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
is $path->parse('path/')->to_string, 'path/', 'right path';
is $path->parts->[0], 'path', 'right part';
is $path->parts->[1], undef,  'no part';
ok !$path->leading_slash, 'no leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new;
is $path->to_string,     '',  'right result';
is $path->to_abs_string, '/', 'right result';

# Advanced
$path = Mojo::Path->new('/AZaz09-._~!$&\'()*+,;=:@');
is $path->parts->[0], 'AZaz09-._~!$&\'()*+,;=:@', 'right part';
is $path->parts->[1], undef, 'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
is "$path", '/AZaz09-._~!$&\'()*+,;=:@', 'right result';

# Unicode
is $path->parse('/foo/♥/bar')->to_string, '/foo/%E2%99%A5/bar', 'right path';
is $path->parts->[0], 'foo', 'right part';
is $path->parts->[1], '♥', 'right part';
is $path->parts->[2], 'bar', 'right part';
is $path->parts->[3], undef, 'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
is $path->parse('/foo/%E2%99%A5/~b@a:r+')->to_string,
  '/foo/%E2%99%A5/~b@a:r+', 'right path';
is $path->parts->[0], 'foo',     'right part';
is $path->parts->[1], '♥',     'right part';
is $path->parts->[2], '~b@a:r+', 'right part';
is $path->parts->[3], undef,     'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';

# Zero in path
is $path->parse('/path/0')->to_string, '/path/0', 'right path';
is $path->parts->[0], 'path', 'right part';
is $path->parts->[1], '0',    'right part';
is $path->parts->[2], undef,  'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
$path = Mojo::Path->new('0');
is $path->parts->[0], '0',   'right part';
is $path->parts->[1], undef, 'no part';
is $path->to_string,     '0',  'right result';
is $path->to_abs_string, '/0', 'right result';

# Canonicalizing
$path = Mojo::Path->new(
  '/%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd');
is "$path", '//../../../../../../../../../../etc/passwd', 'right result';
is $path->parts->[0],  '',       'right part';
is $path->parts->[1],  '..',     'right part';
is $path->parts->[2],  '..',     'right part';
is $path->parts->[3],  '..',     'right part';
is $path->parts->[4],  '..',     'right part';
is $path->parts->[5],  '..',     'right part';
is $path->parts->[6],  '..',     'right part';
is $path->parts->[7],  '..',     'right part';
is $path->parts->[8],  '..',     'right part';
is $path->parts->[9],  '..',     'right part';
is $path->parts->[10], '..',     'right part';
is $path->parts->[11], 'etc',    'right part';
is $path->parts->[12], 'passwd', 'right part';
is $path->parts->[13], undef,    'no part';
is $path->canonicalize, '/../../../../../../../../../../etc/passwd',
  'right result';
is $path->parts->[0],  '..',     'right part';
is $path->parts->[1],  '..',     'right part';
is $path->parts->[2],  '..',     'right part';
is $path->parts->[3],  '..',     'right part';
is $path->parts->[4],  '..',     'right part';
is $path->parts->[5],  '..',     'right part';
is $path->parts->[6],  '..',     'right part';
is $path->parts->[7],  '..',     'right part';
is $path->parts->[8],  '..',     'right part';
is $path->parts->[9],  '..',     'right part';
is $path->parts->[10], 'etc',    'right part';
is $path->parts->[11], 'passwd', 'right part';
is $path->parts->[12], undef,    'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';

# Canonicalizing (alternative)
$path = Mojo::Path->new(
  '%2ftest%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd');
is "$path", '/test/../../../../../../../../../etc/passwd', 'right result';
is $path->parts->[0],  'test',   'right part';
is $path->parts->[1],  '..',     'right part';
is $path->parts->[2],  '..',     'right part';
is $path->parts->[3],  '..',     'right part';
is $path->parts->[4],  '..',     'right part';
is $path->parts->[5],  '..',     'right part';
is $path->parts->[6],  '..',     'right part';
is $path->parts->[7],  '..',     'right part';
is $path->parts->[8],  '..',     'right part';
is $path->parts->[9],  '..',     'right part';
is $path->parts->[10], 'etc',    'right part';
is $path->parts->[11], 'passwd', 'right part';
is $path->parts->[12], undef,    'no part';
is $path->canonicalize, '/../../../../../../../../etc/passwd', 'right result';
is $path->parts->[0],  '..',     'right part';
is $path->parts->[1],  '..',     'right part';
is $path->parts->[2],  '..',     'right part';
is $path->parts->[3],  '..',     'right part';
is $path->parts->[4],  '..',     'right part';
is $path->parts->[5],  '..',     'right part';
is $path->parts->[6],  '..',     'right part';
is $path->parts->[7],  '..',     'right part';
is $path->parts->[8],  'etc',    'right part';
is $path->parts->[9],  'passwd', 'right part';
is $path->parts->[10], undef,    'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';

# Canonicalizing (with escaped "%")
$path = Mojo::Path->new('%2ftest%2f..%252f..%2f..%2f..%2f..%2fetc%2fpasswd');
is "$path", '/test/..%252f../../../../etc/passwd', 'right result';
is $path->parts->[0], 'test',    'right part';
is $path->parts->[1], '..%2f..', 'right part';
is $path->parts->[2], '..',      'right part';
is $path->parts->[3], '..',      'right part';
is $path->parts->[4], '..',      'right part';
is $path->parts->[5], 'etc',     'right part';
is $path->parts->[6], 'passwd',  'right part';
is $path->parts->[7], undef,     'no part';
is $path->canonicalize, '/../etc/passwd', 'right result';
is $path->parts->[0], '..',     'right part';
is $path->parts->[1], 'etc',    'right part';
is $path->parts->[2], 'passwd', 'right part';
is $path->parts->[3], undef,    'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';

# Contains
$path = Mojo::Path->new('/foo/bar');
ok $path->contains('/'),        'contains path';
ok $path->contains('/foo'),     'contains path';
ok $path->contains('/foo/bar'), 'contains path';
ok !$path->contains('/foobar'),      'does not contain path';
ok !$path->contains('/foo/b'),       'does not contain path';
ok !$path->contains('/foo/bar/baz'), 'does not contain path';
$path = Mojo::Path->new('/♥/bar');
ok $path->contains('/♥'),     'contains path';
ok $path->contains('/♥/bar'), 'contains path';
ok !$path->contains('/♥foo'), 'does not contain path';
ok !$path->contains('/foo♥'), 'does not contain path';
$path = Mojo::Path->new('/');
ok $path->contains('/'), 'contains path';
ok !$path->contains('/foo'), 'does not contain path';
$path = Mojo::Path->new('/0');
ok $path->contains('/'),  'contains path';
ok $path->contains('/0'), 'contains path';
ok !$path->contains('/0/0'), 'does not contain path';
$path = Mojo::Path->new('/0/♥.html');
ok $path->contains('/'),           'contains path';
ok $path->contains('/0'),          'contains path';
ok $path->contains('/0/♥.html'), 'contains path';
ok !$path->contains('/0/♥'),    'does not contain path';
ok !$path->contains('/0/0.html'), 'does not contain path';
ok !$path->contains('/0.html'),   'does not contain path';
ok !$path->contains('/♥.html'), 'does not contain path';

# Like
my $opt_qr = qr!^/(?:foo|bar|baz)!;
$path = Mojo::Path->new('/foo/bar');
ok $path->like($opt_qr), 'like path';
$path = Mojo::Path->new('/bar/baz');
ok $path->like($opt_qr), 'like path';
$path = Mojo::Path->new('/baz/foo/');
ok $path->like($opt_qr), 'like path';
$path = Mojo::Path->new('/moo/bar');
ok !$path->like($opt_qr), 'not like path';
$path = Mojo::Path->new('/foo/bar');
ok $path->like(qr(^/)),         'like path';
ok $path->like(qr(^/foo)),      'like path';
ok $path->like(qr(^/foo/)),     'like path';
ok $path->like(qr(^/foo/bar)),  'like path';
ok $path->like(qr(^/foo/bar$)), 'like path';
ok $path->like(qr(/foo/bar$)),  'like path';
ok $path->like(qr(/foo/bar)),   'like path';
ok $path->like(qr(/foo)),       'like path';
ok $path->like(qr(/bar)),       'like path';
ok $path->like(qr(/)),          'like path';
ok $path->like(qr(^/\w+)),      'like path';
ok !$path->like(qr(^/$)),       'not like path';
$path = Mojo::Path->new('/bar/baz/');
ok $path->like(qr(bar)),    'like path';
ok $path->like(qr(/bar)),   'like path';
ok $path->like(qr(/bar/)),  'like path';
ok $path->like(qr(bar/)),   'like path';
ok $path->like(qr(/baz)),   'like path';
ok $path->like(qr(/baz/)),  'like path';
ok $path->like(qr(/baz/$)), 'like path';
ok $path->like(qr(baz/$)),  'like path';
ok $path->like(qr(/$)),     'like path';
ok !$path->like(qr(^/$)),   'not like path';
$path = Mojo::Path->new('/0/♥.html');
ok $path->like(qr(♥)),    'like path';
ok !$path->like(qr(^/$)), 'not like path';

# Merge
$path = Mojo::Path->new('/foo');
$path->merge('bar/baz');
is "$path", '/bar/baz', 'right path';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
$path = Mojo::Path->new('/foo/');
$path->merge('bar/baz');
is "$path", '/foo/bar/baz', 'right path';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
$path = Mojo::Path->new('/foo/');
$path->merge('bar/baz/');
is "$path", '/foo/bar/baz/', 'right path';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('/foo/');
$path->merge('/bar/baz');
is "$path", '/bar/baz', 'right path';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
$path = Mojo::Path->new('/foo/bar');
$path->merge('/bar/baz/');
is "$path", '/bar/baz/', 'right path';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('foo/bar');
$path->merge('baz/yada');
is "$path", 'foo/baz/yada', 'right path';
ok !$path->leading_slash,  'no leading slash';
ok !$path->trailing_slash, 'no trailing slash';

# Empty path elements
$path = Mojo::Path->new('//');
is "$path", '//', 'right result';
is $path->parts->[0], undef, 'no part';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('/foo//bar/23/');
is "$path", '/foo//bar/23/', 'right result';
is $path->parts->[0], 'foo', 'right part';
is $path->parts->[1], '',    'right part';
is $path->parts->[2], 'bar', 'right part';
is $path->parts->[3], '23',  'right part';
is $path->parts->[4], undef, 'no part';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('//foo/bar/23/');
is "$path", '//foo/bar/23/', 'right result';
is $path->parts->[0], '',    'right part';
is $path->parts->[1], 'foo', 'right part';
is $path->parts->[2], 'bar', 'right part';
is $path->parts->[3], '23',  'right part';
is $path->parts->[4], undef, 'no part';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('/foo///bar/23/');
is "$path", '/foo///bar/23/', 'right result';
is $path->parts->[0], 'foo', 'right part';
is $path->parts->[1], '',    'right part';
is $path->parts->[2], '',    'right part';
is $path->parts->[3], 'bar', 'right part';
is $path->parts->[4], '23',  'right part';
is $path->parts->[5], undef, 'no part';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('///foo/bar/23/');
is "$path", '///foo/bar/23/', 'right result';
is $path->parts->[0], '',    'right part';
is $path->parts->[1], '',    'right part';
is $path->parts->[2], 'foo', 'right part';
is $path->parts->[3], 'bar', 'right part';
is $path->parts->[4], '23',  'right part';
is $path->parts->[5], undef, 'no part';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';
$path = Mojo::Path->new('///foo///bar/23///');
is "$path", '///foo///bar/23///', 'right result';
is $path->parts->[0], '',    'right part';
is $path->parts->[1], '',    'right part';
is $path->parts->[2], 'foo', 'right part';
is $path->parts->[3], '',    'right part';
is $path->parts->[4], '',    'right part';
is $path->parts->[5], 'bar', 'right part';
is $path->parts->[6], '23',  'right part';
is $path->parts->[7], '',    'right part';
is $path->parts->[8], '',    'right part';
is $path->parts->[9], undef, 'no part';
ok $path->leading_slash,  'has leading slash';
ok $path->trailing_slash, 'has trailing slash';

# Escaped slash
$path = Mojo::Path->new->parts(['foo/bar']);
is $path->parts->[0], 'foo/bar', 'right part';
is $path->parts->[1], undef,     'no part';
is "$path", 'foo%2Fbar', 'right result';
is $path->to_string,     'foo%2Fbar',  'right result';
is $path->to_abs_string, '/foo%2Fbar', 'right result';

# Latin-1
$path = Mojo::Path->new->charset('Latin-1')->parse('/foob%E4r');
is $path->parts->[0], 'foobär', 'right part';
is $path->parts->[1], undef,     'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
is "$path", '/foob%E4r', 'right result';
is $path->to_string,     '/foob%E4r', 'right result';
is $path->to_abs_string, '/foob%E4r', 'right result';
is $path->clone->to_string, '/foob%E4r', 'right result';

# No charset
$path = Mojo::Path->new->charset(undef)->parse('/%E4');
is $path->parts->[0], "\xe4", 'right part';
is $path->parts->[1], undef,  'no part';
ok $path->leading_slash, 'has leading slash';
ok !$path->trailing_slash, 'no trailing slash';
is "$path", '/%E4', 'right result';
is $path->clone->to_string, '/%E4', 'right result';

done_testing();
