use Mojo::Base -strict;

use Test::More tests => 267;

# "What good is money if it can't inspire terror in your fellow man?"
use_ok 'Mojo::Cookie::Request';
use_ok 'Mojo::Cookie::Response';

# Request cookie as string
my $cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
$cookie->value('ba =r');
$cookie->path('/test');
$cookie->version(1);
is $cookie->to_string, 'foo=ba =r; $Path=/test', 'right format';
is $cookie->to_string_with_prefix, '$Version=1; foo=ba =r; $Path=/test',
  'right format';

# Request cookie without value as string
$cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
$cookie->path('/test');
$cookie->version(1);
is $cookie->to_string, 'foo=; $Path=/test', 'right format';
is $cookie->to_string_with_prefix, '$Version=1; foo=; $Path=/test',
  'right format';
$cookie = Mojo::Cookie::Request->new;
$cookie->name('foo');
$cookie->value('');
$cookie->path('/test');
$cookie->version(1);
is $cookie->to_string, 'foo=; $Path=/test', 'right format';
is $cookie->to_string_with_prefix, '$Version=1; foo=; $Path=/test',
  'right format';

# Empty cookie
$cookie = Mojo::Cookie::Request->new;
my $cookies = $cookie->parse();

# Parse normal request cookie
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=bar; $Path="/test"');
is $cookies->[0]->name,    'foo',   'right name';
is $cookies->[0]->value,   'bar',   'right value';
is $cookies->[0]->path,    '/test', 'right path';
is $cookies->[0]->version, '1',     'right version';
is $cookies->[1], undef, 'no more cookies';

# Parse request cookies from multiple header values
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse(
  '$Version=1; foo=bar; $Path="/test", $Version=0; baz=yada; $Path="/tset"');
is $cookies->[0]->name,    'foo',   'right name';
is $cookies->[0]->value,   'bar',   'right value';
is $cookies->[0]->path,    '/test', 'right path';
is $cookies->[0]->version, '1',     'right version';
is $cookies->[1]->name,    'baz',   'right name';
is $cookies->[1]->value,   'yada',  'right value';
is $cookies->[1]->path,    '/tset', 'right path';
is $cookies->[1]->version, '0',     'right version';
is $cookies->[2], undef, 'no more cookies';

# Parse request cookie (Netscape)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('CUSTOMER=WILE_E_COYOTE');
is $cookies->[0]->name,    'CUSTOMER',      'right name';
is $cookies->[0]->value,   'WILE_E_COYOTE', 'right value';
is $cookies->[0]->version, '0',             'right version';
is $cookies->[1], undef, 'no more cookies';

# Parse multiple request cookies (Netscape)
$cookie = Mojo::Cookie::Request->new;
$cookies =
  $cookie->parse('CUSTOMER=WILE_E_COYOTE; PART_NUMBER=ROCKET_LAUNCHER_0001');
is $cookies->[0]->name,    'CUSTOMER',             'right name';
is $cookies->[0]->value,   'WILE_E_COYOTE',        'right value';
is $cookies->[0]->version, '0',                    'right version';
is $cookies->[1]->name,    'PART_NUMBER',          'right name';
is $cookies->[1]->value,   'ROCKET_LAUNCHER_0001', 'right value';
is $cookies->[1]->version, '0',                    'right version';
is $cookies->[2], undef, 'no more cookies';

# Parse multiple request cookies from multiple header values (Netscape)
$cookie = Mojo::Cookie::Request->new;
$cookies =
  $cookie->parse('CUSTOMER=WILE_E_COYOTE, PART_NUMBER=ROCKET_LAUNCHER_0001');
is $cookies->[0]->name,    'CUSTOMER',             'right name';
is $cookies->[0]->value,   'WILE_E_COYOTE',        'right value';
is $cookies->[0]->version, '0',                    'right version';
is $cookies->[1]->name,    'PART_NUMBER',          'right name';
is $cookies->[1]->value,   'ROCKET_LAUNCHER_0001', 'right value';
is $cookies->[1]->version, '0',                    'right version';
is $cookies->[2], undef, 'no more cookies';

# Parse request cookie without value
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=; $Path="/test"');
is $cookies->[0]->name,    'foo',   'right name';
is $cookies->[0]->value,   '',      'no value';
is $cookies->[0]->path,    '/test', 'right path';
is $cookies->[0]->version, '1',     'right version';
is $cookies->[0]->to_string_with_prefix, '$Version=1; foo=; $Path=/test',
  'right result';
is $cookies->[1], undef, 'no more cookies';
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo=""; $Path="/test"');
is $cookies->[0]->name,    'foo',   'right name';
is $cookies->[0]->value,   '',      'no value';
is $cookies->[0]->path,    '/test', 'right path';
is $cookies->[0]->version, '1',     'right version';
is $cookies->[0]->to_string_with_prefix, '$Version=1; foo=; $Path=/test',
  'right result';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted request cookie
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ,a\" r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->version, '1',          'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted request cookie roundtrip
$cookie = Mojo::Cookie::Request->new;
$cookies =
  $cookie->parse('$Version=1; foo="b ,a\";= r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,    'foo',          'right name';
is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
is $cookies->[0]->path,    '/test',        'right path';
is $cookies->[0]->version, '1',            'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string_with_prefix);
is $cookies->[0]->name,    'foo',          'right name';
is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
is $cookies->[0]->path,    '/test',        'right path';
is $cookies->[0]->version, '1',            'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted request cookie roundtrip (alternative)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ,a\" r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->version, '1',          'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string_with_prefix);
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->version, '1',          'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted request cookie roundtrip (another alternative)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="b ;a\" r\"\\\\"; $Path="/test"');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ;a" r"\\', 'right value';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->version, '1',          'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string_with_prefix);
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ;a" r"\\', 'right value';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->version, '1',          'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted request cookie roundtrip (yet another alternative)
$cookie  = Mojo::Cookie::Request->new;
$cookies = $cookie->parse('$Version=1; foo="\"b a\" r\""; $Path="/test"');
is $cookies->[0]->name,    'foo',      'right name';
is $cookies->[0]->value,   '"b a" r"', 'right value';
is $cookies->[0]->path,    '/test',    'right path';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = $cookie->parse($cookies->[0]->to_string_with_prefix);
is $cookies->[0]->name,    'foo',      'right name';
is $cookies->[0]->value,   '"b a" r"', 'right value';
is $cookies->[0]->path,    '/test',    'right path';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Parse multiple cookie request
$cookies = Mojo::Cookie::Request->parse(
  '$Version=1; foo=bar; $Path=/test; baz=la la; $Path=/tset');
is $cookies->[0]->name,    'foo',   'right name';
is $cookies->[0]->value,   'bar',   'right value';
is $cookies->[0]->path,    '/test', 'right path';
is $cookies->[0]->version, '1',     'right version';
is $cookies->[1]->name,    'baz',   'right name';
is $cookies->[1]->value,   'la la', 'right value';
is $cookies->[1]->path,    '/tset', 'right path';
is $cookies->[1]->version, '1',     'right version';
is $cookies->[2], undef, 'no more cookies';

# Response cookie as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('ba r');
$cookie->path('/test');
$cookie->version(1);
is $cookie->to_string, 'foo=ba r; Version=1; Path=/test', 'right format';

# Response cookie without value as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->path('/test');
$cookie->version(1);
is $cookie->to_string, 'foo=; Version=1; Path=/test', 'right format';
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('');
$cookie->path('/test');
$cookie->version(1);
is $cookie->to_string, 'foo=; Version=1; Path=/test', 'right format';

# Full response cookie as string
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('ba r');
$cookie->domain('kraih.com');
$cookie->path('/test');
$cookie->max_age(60);
$cookie->expires(1218092879);
$cookie->port('80 8080');
$cookie->secure(1);
$cookie->httponly(1);
$cookie->comment('lalalala');
$cookie->version(1);
is $cookie->to_string,
    'foo=ba r; Version=1; Domain=kraih.com; Path=/test;'
  . ' Max-Age=60; expires=Thu, 07 Aug 2008 07:07:59 GMT;'
  . ' Port="80 8080"; Secure; HttpOnly; Comment=lalalala', 'right format';

# Parse response cookie
$cookies = Mojo::Cookie::Response->parse(
      'foo=ba r; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'ba r',      'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie
$cookies = Mojo::Cookie::Response->parse(
  'foo="b a\" r\"\\\\"; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'b a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Parse quoted response cookie (alternative)
$cookies = Mojo::Cookie::Response->parse(
  'foo="b a\" ;r\"\\\\"; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b a" ;r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted response cookie roundtrip
$cookies = Mojo::Cookie::Response->parse(
  'foo="b ,a\";= r\"\\\\"; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',          'right name';
is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',    'right domain';
is $cookies->[0]->path,    '/test',        'right path';
is $cookies->[0]->max_age, 60,             'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',          'right name';
is $cookies->[0]->value,   'b ,a";= r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',    'right domain';
is $cookies->[0]->path,    '/test',        'right path';
is $cookies->[0]->max_age, 60,             'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted response cookie roundtrip (alternative)
$cookies = Mojo::Cookie::Response->parse(
  'foo="b ,a\" r\"\\\\"; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ,a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted response cookie roundtrip (another alternative)
$cookies = Mojo::Cookie::Response->parse(
  'foo="b ;a\" r\"\\\\"; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ;a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',        'right name';
is $cookies->[0]->value,   'b ;a" r"\\', 'right value';
is $cookies->[0]->domain,  'kraih.com',  'right domain';
is $cookies->[0]->path,    '/test',      'right path';
is $cookies->[0]->max_age, 60,           'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Quoted response cookie roundtrip (yet another alternative)
$cookies = Mojo::Cookie::Response->parse(
  'foo="\"b a\" r\""; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '"b a" r"',  'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse($cookies->[0]);
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '"b a" r"',  'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';

# Parse response cookie without value
$cookies = Mojo::Cookie::Response->parse(
      'foo=""; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '',          'no value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[0]->to_string,
    'foo=; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
  . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
  . ' Comment=lalalala', 'right result';
is $cookies->[1], undef, 'no more cookies';
$cookies = Mojo::Cookie::Response->parse(
      'foo=; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
    . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
    . ' Comment=lalalala');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   '',          'no value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/test',     'right path';
is $cookies->[0]->max_age, 60,          'right max age value';
is $cookies->[0]->expires, 'Thu, 07 Aug 2008 07:07:59 GMT',
  'right expires value';
is $cookies->[0]->port,    '80 8080',  'right port';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[0]->to_string,
    'foo=; Version=1; Domain=kraih.com; Path=/test; Max-Age=60;'
  . ' expires=Thu, 07 Aug 2008 07:07:59 GMT; Port="80 8080"; Secure;'
  . ' Comment=lalalala', 'right result';
is $cookies->[1], undef, 'no more cookies';

# Cookie with Max-Age 0 and expires 0
$cookie = Mojo::Cookie::Response->new;
$cookie->name('foo');
$cookie->value('bar');
$cookie->path('/');
$cookie->max_age(0);
$cookie->expires(0);
$cookie->version(1);
is $cookie->to_string, 'foo=bar; Version=1; Path=/; Max-Age=0;'
  . ' expires=Thu, 01 Jan 1970 00:00:00 GMT', 'right format';

# Parse response cookie with Max-Age 0 and expires 0
$cookies = Mojo::Cookie::Response->parse(
      'foo=bar; Version=1; Domain=kraih.com; Path=/; Max-Age=0;'
    . ' expires=Thu, 01 Jan 1970 00:00:00 GMT; Secure; Comment=lalalala');
is $cookies->[0]->name,    'foo',       'right name';
is $cookies->[0]->value,   'bar',       'right value';
is $cookies->[0]->domain,  'kraih.com', 'right domain';
is $cookies->[0]->path,    '/',         'right path';
is $cookies->[0]->max_age, 0,           'right max age value';
is $cookies->[0]->expires, 'Thu, 01 Jan 1970 00:00:00 GMT',
  'right expires value';
is $cookies->[0]->expires->epoch, 0, 'right expires epoch value';
is $cookies->[0]->secure,  '1',        'right secure flag';
is $cookies->[0]->comment, 'lalalala', 'right comment';
is $cookies->[0]->version, '1',        'right version';
is $cookies->[1], undef, 'no more cookies';
