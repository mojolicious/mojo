use Mojo::Base -strict;

use Test::More tests => 190;

use Mojo::Cookie::Request;
use Mojo::Cookie::Response;

# Request cookie as string
my $cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
$cookie->value('ba =r');
is $cookie->to_string, 'foo=ba =r', 'right format';

# Request cookie without value as string
$cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
is $cookie->to_string, 'foo=', 'right format';
$cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
$cookie->value('');
is $cookie->to_string, 'foo=', 'right format';

# Empty cookie
$cookie = Mojo::Cookie::Request->new;
my $cookies = $cookie->parse();

# Parse normal request cookie (RFC 2965)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=bar; $Path="/test"');
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, 'bar', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse request cookies from multiple header values (RFC 2965)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse(
  '$Version=1; foo=bar; $Path="/test", $Version=0; baz=yada; $Path="/tset"');
is $cookies->[0]->name,  'foo',  'right name';
is $cookies->[0]->value, 'bar',  'right value';
is $cookies->[1]->name,  'baz',  'right name';
is $cookies->[1]->value, 'yada', 'right value';
is $cookies->[2], undef, 'no more cookies';

# Parse request cookie (Netscape)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('CUSTOMER=WILE_E_COYOTE');
is $cookies->[0]->name,  'CUSTOMER',      'right name';
is $cookies->[0]->value, 'WILE_E_COYOTE', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse multiple request cookies (Netscape)
$cookie = Mojo::Cookie::Request->new;
$cookies
  = $cookie->parse('CUSTOMER=WILE_E_COYOTE; PART_NUMBER=ROCKET_LAUNCHER_0001');
is $cookies->[0]->name,  'CUSTOMER',             'right name';
is $cookies->[0]->value, 'WILE_E_COYOTE',        'right value';
is $cookies->[1]->name,  'PART_NUMBER',          'right name';
is $cookies->[1]->value, 'ROCKET_LAUNCHER_0001', 'right value';
is $cookies->[2], undef, 'no more cookies';

# Parse multiple request cookies from multiple header values (Netscape)
$cookie = Mojo::Cookie::Request->new;
$cookies
  = $cookie->parse('CUSTOMER=WILE_E_COYOTE, PART_NUMBER=ROCKET_LAUNCHER_0001');
is $cookies->[0]->name,  'CUSTOMER',             'right name';
is $cookies->[0]->value, 'WILE_E_COYOTE',        'right value';
is $cookies->[1]->name,  'PART_NUMBER',          'right name';
is $cookies->[1]->value, 'ROCKET_LAUNCHER_0001', 'right value';
is $cookies->[2], undef, 'no more cookies';

# Parse request cookie without value (RFC 2965)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=; $Path="/test"');
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, '',    'no value';
is $cookies->[1], undef, 'no more cookies';
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=""; $Path="/test"');
is $cookies->[0]->name,  'foo', 'right name';
is $cookies->[0]->value, '',    'no value';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted request cookie (RFC 2965)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ,a\" r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,  'foo',        'right name';
is $cookies->[0]->value, 'b ,a" r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted request cookie roundtrip (RFC 2965)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ,a\";= r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,  'foo',          'right name';
is $cookies->[0]->value, 'b ,a";= r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string);
is $cookies->[0]->name,  'foo',          'right name';
is $cookies->[0]->value, 'b ,a";= r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted request cookie roundtrip (RFC 2965, alternative)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ,a\" r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,  'foo',        'right name';
is $cookies->[0]->value, 'b ,a" r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string);
is $cookies->[0]->name,  'foo',        'right name';
is $cookies->[0]->value, 'b ,a" r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted request cookie roundtrip (RFC 2965, another alternative)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ;a\" r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,  'foo',        'right name';
is $cookies->[0]->value, 'b ;a" r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string);
is $cookies->[0]->name,  'foo',        'right name';
is $cookies->[0]->value, 'b ;a" r"\\', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted request cookie roundtrip (RFC 2965, yet another alternative)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="\"b a\" r\""; $Path="/test"');
is $cookies->[0]->name,  'foo',      'right name';
is $cookies->[0]->value, '"b a" r"', 'right value';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string);
is $cookies->[0]->name,  'foo',      'right name';
is $cookies->[0]->value, '"b a" r"', 'right value';
is $cookies->[1], undef, 'no more cookies';

# Parse multiple cookie request (RFC 2965)
$cookies = Mojo::Cookie::Request->parse(
  '$Version=1; foo=bar; $Path=/test; baz=la la; $Path=/tset');
is $cookies->[0]->name,  'foo',   'right name';
is $cookies->[0]->value, 'bar',   'right value';
is $cookies->[1]->name,  'baz',   'right name';
is $cookies->[1]->value, 'la la', 'right value';
is $cookies->[2], undef, 'no more cookies';

# Response cookie as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('ba r');
$cookie->path('/test');
is $cookie->to_string, 'foo=ba r; path=/test', 'right format';

# Response cookie without value as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->path('/test');
is $cookie->to_string, 'foo=; path=/test', 'right format';
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('');
$cookie->path('/test');
is $cookie->to_string, 'foo=; path=/test', 'right format';

# Full response cookie as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('ba r');
$cookie->domain('kraih.com');
$cookie->path('/test');
$cookie->max_age(60);
$cookie->expires(1218092879);
$cookie->secure(1);
$cookie->httponly(1);
is $cookie->to_string,
  'foo=ba r; expires=Thu, 07 Aug 2008 07:07:59 GMT; domain=kraih.com;'
  . ' path=/test; secure; Max-Age=60; HttpOnly', 'right format';

# Parse response cookie (RFC 6265)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo=ba r; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure;');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'ba r',      'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse response cookie with invalid flag (RFC 6265)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo=ba r; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; InSecure;');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'ba r',      'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, undef, 'no secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie (RFC 6265)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo="b a\" r\"\\\\"; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'b a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie (RFC 6265, alternative)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo="b a\" ;r\"\\\\"; domain=kraih.com; path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; secure');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b a" ;r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie roundtrip (RFC 6265)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo="b ,a\";= r\"\\\\"; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
is $cookies->[0]->name,    'foo',          'right name';
is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',    'right domain';
is $cookies->[0]->path,    '/test',        'right path';
is $cookies->[0]->max_age, 60,             'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',          'right name';
is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',    'right domain';
is $cookies->[0]->path,    '/test',        'right path';
is $cookies->[0]->max_age, 60,             'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie roundtrip (RFC 6265, alternative)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo="b ,a\" r\"\\\\"; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie roundtrip (RFC 6265, another alternative)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo="b ;a\" r\"\\\\"; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT;  Secure');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ;a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ;a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie roundtrip (RFC 6265, yet another alternative)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo="\"b a\" r\""; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '"b a" r"',  'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '"b a" r"',  'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';

# Parse response cookie without value (RFC 2965)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo=""; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '',          'no value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[0]->to_string,
  'foo=; expires=Thu, 07 Aug 2008 07:07:59 GMT; domain=kraih.com;'
  . ' path=/test; secure; Max-Age=60', 'right result';
is $cookies->[1], undef, 'no more cookies';
$cookies
  = Mojo::Cookie::Response->parse(
      'foo=; Version=1; domain=kraih.com; path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; secure');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '',          'no value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[0]->to_string,
  'foo=; expires=Thu, 07 Aug 2008 07:07:59 GMT; domain=kraih.com;'
  . ' path=/test; secure; Max-Age=60', 'right result';
is $cookies->[1], undef, 'no more cookies';

# Response cookie with Max-Age 0 and Expires 0
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('bar');
$cookie->path('/');
$cookie->max_age(0);
$cookie->expires(0);
is $cookie->to_string,
  'foo=bar; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/; Max-Age=0',
  'right format';

# Parse response cookie with Max-Age 0 and Expires 0 (RFC 6265)
$cookies
  = Mojo::Cookie::Response->parse(
      'foo=bar; Domain=kraih.com; Path=/; Max-Age=0;'
    . ' Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'bar',       'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/',         'right path';
is $cookies->[0]->max_age, 0,           'right max age value';
is $cookies->[0]->expires, 'Thu, 01 Jan 1970 00:00:00 GMT',
  'right expires value';
is $cookies->[0]->expires->epoch, 0, 'right expires epoch value';
is $cookies->[0]->secure, '1', 'right secure flag';
is $cookies->[1], undef, 'no more cookies';
