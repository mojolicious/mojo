use Mojo::Base -strict;

use Test::More;
use Mojo::Cookie::Request;
use Mojo::Cookie::Response;

subtest 'Missing name' => sub {
  is(Mojo::Cookie::Request->new,  '', 'right format');
  is(Mojo::Cookie::Response->new, '', 'right format');
};

subtest 'Request cookie as string' => sub {
  my $cookie = Mojo::Cookie::Request->new;
  $cookie->name('0');
  $cookie->value('ba =r');
  is $cookie->to_string, '0="ba =r"', 'right format';
};

subtest 'Request cookie without value as string' => sub {
  my $cookie = Mojo::Cookie::Request->new;
  $cookie->name('foo');
  is $cookie->to_string, 'foo=', 'right format';
  $cookie = Mojo::Cookie::Request->new;
  $cookie->name('foo');
  $cookie->value('');
  is $cookie->to_string, 'foo=', 'right format';
};

subtest 'Empty request cookie' => sub {
  is_deeply(Mojo::Cookie::Request->parse, [], 'no cookies');
};

subtest 'Parse normal request cookie (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo=bar; $Path="/test"');
  is $cookies->[0]->name,  'foo', 'right name';
  is $cookies->[0]->value, 'bar', 'right value';
  is $cookies->[1],        undef, 'no more cookies';
};

subtest 'Parse request cookies from multiple header values (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo=bar; $Path="/test", $Version=0; baz=yada; $Path="/tset"');
  is $cookies->[0]->name,  'foo',  'right name';
  is $cookies->[0]->value, 'bar',  'right value';
  is $cookies->[1]->name,  'baz',  'right name';
  is $cookies->[1]->value, 'yada', 'right value';
  is $cookies->[2],        undef,  'no more cookies';
};

subtest 'Parse request cookie (Netscape)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('CUSTOMER=WILE_E_COYOTE');
  is $cookies->[0]->name,  'CUSTOMER',      'right name';
  is $cookies->[0]->value, 'WILE_E_COYOTE', 'right value';
  is $cookies->[1],        undef,           'no more cookies';
};

subtest 'Parse multiple request cookies (Netscape)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('CUSTOMER=WILE_E_COYOTE; PART_NUMBER=ROCKET_LAUNCHER_0001');
  is $cookies->[0]->name,  'CUSTOMER',             'right name';
  is $cookies->[0]->value, 'WILE_E_COYOTE',        'right value';
  is $cookies->[1]->name,  'PART_NUMBER',          'right name';
  is $cookies->[1]->value, 'ROCKET_LAUNCHER_0001', 'right value';
  is $cookies->[2],        undef,                  'no more cookies';
};

subtest 'Parse multiple request cookies from multiple header values (Netscape)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('CUSTOMER=WILE_E_COYOTE, PART_NUMBER=ROCKET_LAUNCHER_0001');
  is $cookies->[0]->name,  'CUSTOMER',             'right name';
  is $cookies->[0]->value, 'WILE_E_COYOTE',        'right value';
  is $cookies->[1]->name,  'PART_NUMBER',          'right name';
  is $cookies->[1]->value, 'ROCKET_LAUNCHER_0001', 'right value';
  is $cookies->[2],        undef,                  'no more cookies';
};

subtest 'Parse request cookie without value (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo=; $Path="/test"');
  is $cookies->[0]->name,  'foo', 'right name';
  is $cookies->[0]->value, '',    'no value';
  is $cookies->[1],        undef, 'no more cookies';
  $cookies = Mojo::Cookie::Request->parse('$Version=1; foo=""; $Path="/test"');
  is $cookies->[0]->name,  'foo', 'right name';
  is $cookies->[0]->value, '',    'no value';
  is $cookies->[1],        undef, 'no more cookies';
};

subtest 'Parse quoted request cookie (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo="b ,a\" r\"\\\\"; $Path="/test"');
  is $cookies->[0]->name,  'foo',        'right name';
  is $cookies->[0]->value, 'b ,a" r"\\', 'right value';
  is $cookies->[1],        undef,        'no more cookies';
};

subtest 'Parse quoted request cookie roundtrip (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo="b ,a\";= r\"\\\\"; $Path="/test"');
  is $cookies->[0]->name,  'foo',          'right name';
  is $cookies->[0]->value, 'b ,a";= r"\\', 'right value';
  is $cookies->[1],        undef,          'no more cookies';
  $cookies = Mojo::Cookie::Request->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,  'foo',          'right name';
  is $cookies->[0]->value, 'b ,a";= r"\\', 'right value';
  is $cookies->[1],        undef,          'no more cookies';
};

subtest 'Parse quoted request cookie roundtrip (RFC 2965, alternative)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo="b ,a\" r\"\\\\"; $Path="/test"');
  is $cookies->[0]->name,  'foo',        'right name';
  is $cookies->[0]->value, 'b ,a" r"\\', 'right value';
  is $cookies->[1],        undef,        'no more cookies';
  $cookies = Mojo::Cookie::Request->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,  'foo',        'right name';
  is $cookies->[0]->value, 'b ,a" r"\\', 'right value';
  is $cookies->[1],        undef,        'no more cookies';
};

subtest 'Parse quoted request cookie roundtrip (RFC 2965, another alternative)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo="b ;a\" r\"\\\\"; $Path="/test"');
  is $cookies->[0]->name,  'foo',        'right name';
  is $cookies->[0]->value, 'b ;a" r"\\', 'right value';
  is $cookies->[1],        undef,        'no more cookies';
  $cookies = Mojo::Cookie::Request->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,  'foo',        'right name';
  is $cookies->[0]->value, 'b ;a" r"\\', 'right value';
  is $cookies->[1],        undef,        'no more cookies';
};

subtest 'Parse quoted request cookie roundtrip (RFC 2965, yet another alternative)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo="\"b a\" r\""; $Path="/test"');
  is $cookies->[0]->name,  'foo',      'right name';
  is $cookies->[0]->value, '"b a" r"', 'right value';
  is $cookies->[1],        undef,      'no more cookies';
  $cookies = Mojo::Cookie::Request->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,  'foo',      'right name';
  is $cookies->[0]->value, '"b a" r"', 'right value';
  is $cookies->[1],        undef,      'no more cookies';
};

subtest 'Parse multiple cookie request (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Request->parse('$Version=1; foo=bar; $Path=/test; baz="la la"; $Path=/tset');
  is $cookies->[0]->name,  'foo',   'right name';
  is $cookies->[0]->value, 'bar',   'right value';
  is $cookies->[1]->name,  'baz',   'right name';
  is $cookies->[1]->value, 'la la', 'right value';
  is $cookies->[2],        undef,   'no more cookies';
};

subtest 'Response cookie as string' => sub {
  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->value('ba r');
  $cookie->path('/test');
  is $cookie->to_string, 'foo="ba r"; path=/test', 'right format';
};

subtest 'Response cookie without value as string' => sub {
  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->path('/test');
  is $cookie->to_string, 'foo=; path=/test', 'right format';
  $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->value('');
  $cookie->path('/test');
  is $cookie->to_string, 'foo=; path=/test', 'right format';
};

subtest 'Full response cookie as string' => sub {
  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('0');
  $cookie->value('ba r');
  $cookie->domain('example.com');
  $cookie->path('/test');
  $cookie->partitioned(1);
  $cookie->max_age(60);
  $cookie->expires(1218092879);
  $cookie->secure(1);
  $cookie->httponly(1);
  $cookie->samesite('Lax');
  is $cookie->to_string, '0="ba r"; expires=Thu, 07 Aug 2008 07:07:59 GMT; domain=example.com;'
    . ' path=/test; Partitioned; secure; HttpOnly; SameSite=Lax; Max-Age=60', 'right format';
};

subtest 'Empty response cookie' => sub {
  is_deeply(Mojo::Cookie::Response->parse, [], 'no cookies');
};

subtest 'Parse response cookie (Netscape)' => sub {
  my $cookies
    = Mojo::Cookie::Response->parse('CUSTOMER=WILE_E_COYOTE; path=/; expires=Tuesday, 09-Nov-1999 23:12:40 GMT');
  is $cookies->[0]->name,    'CUSTOMER',      'right name';
  is $cookies->[0]->value,   'WILE_E_COYOTE', 'right value';
  is $cookies->[0]->expires, 942189160,       'right expires value';
  is $cookies->[1],          undef,           'no more cookies';
};

subtest 'Parse multiple response cookies (Netscape)' => sub {
  my $cookies
    = Mojo::Cookie::Response->parse('CUSTOMER=WILE_E_COYOTE; expires=Tuesday, 09-Nov-1999 23:12:40 GMT; path=/'
      . ',SHIPPING=FEDEX; path=/; expires=Tuesday, 09-Nov-1999 23:12:41 GMT');
  is $cookies->[0]->name,    'CUSTOMER',      'right name';
  is $cookies->[0]->value,   'WILE_E_COYOTE', 'right value';
  is $cookies->[0]->expires, 942189160,       'right expires value';
  is $cookies->[1]->name,    'SHIPPING',      'right name';
  is $cookies->[1]->value,   'FEDEX',         'right value';
  is $cookies->[1]->expires, 942189161,       'right expires value';
  is $cookies->[2],          undef,           'no more cookies';
};

subtest 'Parse response cookie (RFC 6265)' => sub {
  my $cookies = Mojo::Cookie::Response->parse(
    'foo="ba r"; Domain=example.com; Path=/test; Max-Age=60;' . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure;');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'ba r',        'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Partitioned cookie (RFC 6265 CHIPS)' => sub {
  my $cookies
    = Mojo::Cookie::Response->parse(
    'foo="bar"; Domain=example.com; Partitioned; Path=/test; Max-Age=60; Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure;'
    );
  is $cookies->[0]->partitioned, 1, 'right partitioned value';

  $cookies = Mojo::Cookie::Response->parse(
    'foo="bar"; Domain=example.com; Path=/test; Max-Age=60; Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure;');
  is $cookies->[0]->partitioned, undef, 'no partitioned value';
};

subtest 'Parse response cookie with invalid flag (RFC 6265)' => sub {
  my $cookies = Mojo::Cookie::Response->parse(
    'foo="ba r"; Domain=.example.com; Path=/test; Max-Age=60;' . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; InSecure;');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'ba r',        'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  undef,         'no secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse quoted response cookie (RFC 6265)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="b a\" r\"\\\\"; Domain=example.com; Path=/test; Max-Age=60;'
      . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'b a" r"\\',   'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse quoted response cookie (RFC 6265, alternative)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="b a\" ;r\"\\\\" ; domain=example.com ; path=/test ; Max-Age=60'
      . ' ; expires=Thu, 07 Aug 2008 07:07:59 GMT ; secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'b a" ;r"\\',  'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse quoted response cookie roundtrip (RFC 6265)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="b ,a\";= r\"\\\\"; Domain=example.com; Path=/test; Max-Age=60;'
      . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
  is $cookies->[0]->name,    'foo',          'right name';
  is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
  is $cookies->[0]->domain,  'example.com',  'right domain';
  is $cookies->[0]->path,    '/test',        'right path';
  is $cookies->[0]->max_age, 60,             'right max age value';
  is $cookies->[0]->expires, 1218092879,     'right expires value';
  is $cookies->[0]->secure,  1,              'right secure flag';
  is $cookies->[1],          undef,          'no more cookies';
  $cookies = Mojo::Cookie::Response->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,    'foo',          'right name';
  is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
  is $cookies->[0]->domain,  'example.com',  'right domain';
  is $cookies->[0]->path,    '/test',        'right path';
  is $cookies->[0]->max_age, 60,             'right max age value';
  is $cookies->[0]->expires, 1218092879,     'right expires value';
  is $cookies->[0]->secure,  1,              'right secure flag';
  is $cookies->[1],          undef,          'no more cookies';
};

subtest 'Parse quoted response cookie roundtrip (RFC 6265, alternative)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="b ,a\" r\"\\\\"; Domain=example.com; Path=/test; Max-Age=60;'
      . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'b ,a" r"\\',  'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
  $cookies = Mojo::Cookie::Response->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'b ,a" r"\\',  'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse quoted response cookie roundtrip (RFC 6265, another alternative)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="b ;a\" r\"\\\\"; Domain=example.com; Path=/test; Max-Age=60;'
      . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT;  Secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'b ;a" r"\\',  'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
  $cookies = Mojo::Cookie::Response->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'b ;a" r"\\',  'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse quoted response cookie roundtrip (RFC 6265, yet another alternative)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="\"b a\" r\""; Domain=example.com; Path=/test; Max-Age=60;'
      . ' Expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   '"b a" r"',    'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
  $cookies = Mojo::Cookie::Response->parse($cookies->[0]->to_string);
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   '"b a" r"',    'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse response cookie without value (RFC 2965)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo=""; Version=1; Domain=example.com; Path=/test; Max-Age=60;'
      . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   '',            'no value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[0]->to_string,
    'foo=; expires=Thu, 07 Aug 2008 07:07:59 GMT; domain=example.com;' . ' path=/test; secure; Max-Age=60',
    'right result';
  is $cookies->[1], undef, 'no more cookies';
  $cookies = Mojo::Cookie::Response->parse(
    'foo=; Version=1; domain=example.com; path=/test; Max-Age=60;' . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   '',            'no value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/test',       'right path';
  is $cookies->[0]->max_age, 60,            'right max age value';
  is $cookies->[0]->expires, 1218092879,    'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[0]->to_string,
    'foo=; expires=Thu, 07 Aug 2008 07:07:59 GMT; domain=example.com;' . ' path=/test; secure; Max-Age=60',
    'right result';
  is $cookies->[1], undef, 'no more cookies';
};

subtest 'Parse response cookie with SameSite value' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo=bar; Path=/; Expires=Tuesday, 09-Nov-99 23:12:40 GMT; SameSite=Lax');
  is $cookies->[0]->name,     'foo',     'right name';
  is $cookies->[0]->value,    'bar',     'right value';
  is $cookies->[0]->domain,   undef,     'no domain';
  is $cookies->[0]->path,     '/',       'right path';
  is $cookies->[0]->max_age,  undef,     'no max age value';
  is $cookies->[0]->expires,  942189160, 'right expires value';
  is $cookies->[0]->samesite, 'Lax',     'right samesite value';
  is $cookies->[1],           undef,     'no more cookies';
};

subtest 'Parse response cookie with broken Expires and Domain values' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo="ba r"; Expires=Th');
  is $cookies->[0]->name,    'foo',  'right name';
  is $cookies->[0]->value,   'ba r', 'right value';
  is $cookies->[0]->expires, undef,  'no expires value';
  is $cookies->[0]->domain,  undef,  'no domain value';
  is $cookies->[1],          undef,  'no more cookies';
  $cookies = Mojo::Cookie::Response->parse('foo="ba r"; Expires=Th; Domain=; Path=/test');
  is $cookies->[0]->name,    'foo',  'right name';
  is $cookies->[0]->value,   'ba r', 'right value';
  is $cookies->[0]->expires, undef,  'no expires value';
  is $cookies->[0]->domain,  '',     'no domain value';
  is $cookies->[1],          undef,  'no more cookies';
  $cookies = Mojo::Cookie::Response->parse('foo="ba r"; Expires; Domain; Path=/test');
  is $cookies->[0]->name,    'foo',  'right name';
  is $cookies->[0]->value,   'ba r', 'right value';
  is $cookies->[0]->expires, undef,  'no expires value';
  is $cookies->[0]->domain,  undef,  'no domain value';
  is $cookies->[1],          undef,  'no more cookies';
};

subtest 'Response cookie with Max-Age 0 and Expires 0' => sub {
  my $cookie = Mojo::Cookie::Response->new;
  $cookie->name('foo');
  $cookie->value('bar');
  $cookie->path('/');
  $cookie->max_age(0);
  $cookie->expires(0);
  is $cookie->to_string, 'foo=bar; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/; Max-Age=0', 'right format';
};

subtest 'Parse response cookie with Max-Age 0 and Expires 0 (RFC 6265)' => sub {
  my $cookies = Mojo::Cookie::Response->parse(
    'foo=bar; Domain=example.com; Path=/; Max-Age=0;' . ' Expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure');
  is $cookies->[0]->name,    'foo',         'right name';
  is $cookies->[0]->value,   'bar',         'right value';
  is $cookies->[0]->domain,  'example.com', 'right domain';
  is $cookies->[0]->path,    '/',           'right path';
  is $cookies->[0]->max_age, 0,             'right max age value';
  is $cookies->[0]->expires, 0,             'right expires value';
  is $cookies->[0]->secure,  1,             'right secure flag';
  is $cookies->[1],          undef,         'no more cookies';
};

subtest 'Parse response cookie with two digit year (RFC 6265)' => sub {
  my $cookies = Mojo::Cookie::Response->parse('foo=bar; Path=/; Expires=Saturday, 09-Nov-19 23:12:40 GMT; Secure');
  is $cookies->[0]->name,    'foo',      'right name';
  is $cookies->[0]->value,   'bar',      'right value';
  is $cookies->[0]->path,    '/',        'right path';
  is $cookies->[0]->expires, 1573341160, 'right expires value';
  is $cookies->[0]->secure,  1,          'right secure flag';
  is $cookies->[1],          undef,      'no more cookies';
  $cookies = Mojo::Cookie::Response->parse('foo=bar; Path=/; Expires=Tuesday, 09-Nov-99 23:12:40 GMT; Secure');
  is $cookies->[0]->name,    'foo',     'right name';
  is $cookies->[0]->value,   'bar',     'right value';
  is $cookies->[0]->path,    '/',       'right path';
  is $cookies->[0]->expires, 942189160, 'right expires value';
  is $cookies->[0]->secure,  1,         'right secure flag';
  is $cookies->[1],          undef,     'no more cookies';
};

subtest 'Abstract methods' => sub {
  eval { Mojo::Cookie->parse };
  like $@, qr/Method "parse" not implemented by subclass/, 'right error';
  eval { Mojo::Cookie->to_string };
  like $@, qr/Method "to_string" not implemented by subclass/, 'right error';
};

done_testing();
