use Mojo::Base -strict;

use Test::More;
use Mojo::Headers;

# Basic functionality
my $headers = Mojo::Headers->new;
$headers->add(Connection => 'close');
$headers->add(Connection => 'keep-alive');
is $headers->header('Connection'), 'close, keep-alive', 'right value';
$headers->remove('Connection');
is $headers->header('Connection'), undef, 'no value';
$headers->content_type('text/html');
$headers->content_type('text/html');
$headers->expect('continue-100');
$headers->connection('close');
is $headers->content_type, 'text/html', 'right value';
like $headers->to_string, qr/.*\x0d\x0a.*\x0d\x0a.*/, 'right format';
my $hash = $headers->to_hash;
is $hash->{Connection}, 'close',        'right value';
is $hash->{Expect},     'continue-100', 'right value';
is $hash->{'Content-Type'}, 'text/html', 'right value';
$hash = $headers->to_hash(1);
is_deeply $hash->{Connection},     ['close'],        'right structure';
is_deeply $hash->{Expect},         ['continue-100'], 'right structure';
is_deeply $hash->{'Content-Type'}, ['text/html'],    'right structure';
is_deeply [sort @{$headers->names}], [qw(Connection Content-Type Expect)],
  'right structure';
$headers->expires('Thu, 01 Dec 1994 16:00:00 GMT');
$headers->cache_control('public');
is $headers->expires, 'Thu, 01 Dec 1994 16:00:00 GMT', 'right value';
is $headers->cache_control, 'public', 'right value';
$headers->etag('abc321');
is $headers->etag, 'abc321', 'right value';
is $headers->header('ETag'), $headers->etag, 'values are equal';
$headers->status('200 OK');
is $headers->status, '200 OK', 'right value';
is $headers->header('Status'), $headers->status, 'values are equal';

# Mixed case
is $headers->header('content-type' => 'text/plain')->content_type,
  'text/plain', 'right value';
is $headers->header('Content-Type' => 'text/html')->content_type, 'text/html',
  'right value';

# Common headers
$headers = Mojo::Headers->new;
is $headers->accept('foo')->accept,                   'foo', 'right value';
is $headers->accept_charset('foo')->accept_charset,   'foo', 'right value';
is $headers->accept_encoding('foo')->accept_encoding, 'foo', 'right value';
is $headers->accept_language('foo')->accept_language, 'foo', 'right value';
is $headers->accept_ranges('foo')->accept_ranges,     'foo', 'right value';
is $headers->access_control_allow_origin('foo')->access_control_allow_origin,
  'foo', 'right value';
is $headers->allow('foo')->allow,                 'foo', 'right value';
is $headers->authorization('foo')->authorization, 'foo', 'right value';
is $headers->connection('foo')->connection,       'foo', 'right value';
is $headers->cache_control('foo')->cache_control, 'foo', 'right value';
is $headers->content_disposition('foo')->content_disposition, 'foo',
  'right value';
is $headers->content_encoding('foo')->content_encoding,   'foo', 'right value';
is $headers->content_language('foo')->content_language,   'foo', 'right value';
is $headers->content_length('foo')->content_length,       'foo', 'right value';
is $headers->content_location('foo')->content_location,   'foo', 'right value';
is $headers->content_range('foo')->content_range,         'foo', 'right value';
is $headers->content_type('foo')->content_type,           'foo', 'right value';
is $headers->cookie('foo')->cookie,                       'foo', 'right value';
is $headers->dnt('foo')->dnt,                             'foo', 'right value';
is $headers->date('foo')->date,                           'foo', 'right value';
is $headers->etag('foo')->etag,                           'foo', 'right value';
is $headers->expect('foo')->expect,                       'foo', 'right value';
is $headers->expires('foo')->expires,                     'foo', 'right value';
is $headers->host('foo')->host,                           'foo', 'right value';
is $headers->if_modified_since('foo')->if_modified_since, 'foo', 'right value';
is $headers->last_modified('foo')->last_modified,         'foo', 'right value';
is $headers->link('foo')->link,                           'foo', 'right value';
is $headers->location('foo')->location,                   'foo', 'right value';
is $headers->origin('foo')->origin,                       'foo', 'right value';
is $headers->proxy_authenticate('foo')->proxy_authenticate, 'foo',
  'right value';
is $headers->proxy_authorization('foo')->proxy_authorization, 'foo',
  'right value';
is $headers->range('foo')->range, 'foo', 'right value';
is $headers->sec_websocket_accept('foo')->sec_websocket_accept, 'foo',
  'right value';
is $headers->sec_websocket_extensions('foo')->sec_websocket_extensions, 'foo',
  'right value';
is $headers->sec_websocket_key('foo')->sec_websocket_key, 'foo', 'right value';
is $headers->sec_websocket_protocol('foo')->sec_websocket_protocol, 'foo',
  'right value';
is $headers->sec_websocket_version('foo')->sec_websocket_version, 'foo',
  'right value';
is $headers->server('foo')->server,         'foo', 'right value';
is $headers->set_cookie('foo')->set_cookie, 'foo', 'right value';
is $headers->status('foo')->status,         'foo', 'right value';
is $headers->strict_transport_security('foo')->strict_transport_security,
  'foo', 'right value';
is $headers->te('foo')->te,                               'foo', 'right value';
is $headers->trailer('foo')->trailer,                     'foo', 'right value';
is $headers->transfer_encoding('foo')->transfer_encoding, 'foo', 'right value';
is $headers->upgrade('foo')->upgrade,                     'foo', 'right value';
is $headers->user_agent('foo')->user_agent,               'foo', 'right value';
is $headers->vary('foo')->vary,                           'foo', 'right value';
is $headers->www_authenticate('foo')->www_authenticate,   'foo', 'right value';

# Clone
$headers = Mojo::Headers->new;
$headers->add(Connection => 'close');
$headers->add(Connection => 'keep-alive');
is $headers->header('Connection'), 'close, keep-alive', 'right value';
my $clone = $headers->clone;
$headers->connection('nothing');
is $headers->header('Connection'), 'nothing',           'right value';
is $clone->header('Connection'),   'close, keep-alive', 'right value';
$headers = Mojo::Headers->new;
$headers->expect('100-continue');
is $headers->expect, '100-continue', 'right value';
$clone = $headers->clone;
$clone->expect('nothing');
is $headers->expect, '100-continue', 'right value';
is $clone->expect,   'nothing',      'right value';
$clone = Mojo::Headers->new->add(Foo => [qw(bar baz)])->clone;
is_deeply $clone->to_hash(1)->{Foo}, [[qw(bar baz)]], 'right structure';

# Parse headers
$headers = Mojo::Headers->new;
isa_ok $headers->parse(<<'EOF'), 'Mojo::Headers', 'right return value';
Content-Type: text/plain
o: x
Expect: 100-continue
Cache-control: public
Expires: Thu, 01 Dec 1994 16:00:00 GMT

EOF
ok $headers->is_finished,   'parser is finished';
is $headers->content_type,  'text/plain', 'right value';
is $headers->expect,        '100-continue', 'right value';
is $headers->cache_control, 'public', 'right value';
is $headers->expires,       'Thu, 01 Dec 1994 16:00:00 GMT', 'right value';
is $headers->header('o'), 'x', 'right value';

# Parse multiline headers
$headers = Mojo::Headers->new;
$headers->parse(<<'EOF');
Foo: first
 second
 third
Content-Type: text/plain
Foo Bar: baz
Foo: first again
  second ":again"

EOF
ok $headers->is_finished, 'parser is finished';
$hash = {
  'Content-Type' => ['text/plain'],
  Foo            => ['first second third', 'first again second ":again"'],
  'Foo Bar'      => ['baz']
};
is_deeply $headers->to_hash(1), $hash, 'right structure';
is $headers->header('Foo'), 'first second third, first again second ":again"',
  'right value';
$headers = Mojo::Headers->new->parse($headers->to_string . "\x0d\x0a\x0d\x0a");
ok $headers->is_finished, 'parser is finished';
is_deeply $headers->to_hash(1), $hash, 'successful roundtrip';
$hash = {
  'Content-Type' => 'text/plain',
  Foo            => 'first second third, first again second ":again"',
  'Foo Bar'      => 'baz'
};
is_deeply $headers->to_hash, $hash, 'right structure';

# Set headers from hash
$headers = Mojo::Headers->new;
$headers->from_hash({Connection => 'close', 'Content-Type' => 'text/html'});
is_deeply $headers->to_hash,
  {Connection => 'close', 'Content-Type' => 'text/html'}, 'right structure';

# Remove all headers
$headers->from_hash({});
is_deeply $headers->to_hash, {}, 'right structure';

# Append values
$headers = Mojo::Headers->new;
$headers->vary('Accept');
$headers->append(Vary => 'Accept-Encoding');
is $headers->vary, 'Accept, Accept-Encoding', 'right value';
$headers = Mojo::Headers->new;
$headers->append(Vary => 'Accept');
is $headers->vary, 'Accept', 'right value';
$headers->append(Vary => 'Accept-Encoding');
is $headers->vary, 'Accept, Accept-Encoding', 'right value';
$headers = Mojo::Headers->new;
$headers->add(Vary => 'Accept', 'Accept-Encoding');
is_deeply $headers->to_hash(1), {Vary => ['Accept', 'Accept-Encoding']},
  'right structure';
$headers->append(Vary => 'Accept-Language');
is_deeply $headers->to_hash(1),
  {Vary => ['Accept, Accept-Encoding, Accept-Language']}, 'right structure';

# Multiple headers with the same name
$headers = Mojo::Headers->new;
$headers->from_hash({'X-Test' => [23, 24], 'X-Test2' => 'foo'});
$hash = $headers->to_hash;
is $hash->{'X-Test'},  '23, 24', 'right value';
is $hash->{'X-Test2'}, 'foo',    'right value';
$hash = $headers->to_hash(1);
is_deeply $hash->{'X-Test'}, [23, 24], 'right structure';
is_deeply $hash->{'X-Test2'}, ['foo'], 'right structure';
$headers = Mojo::Headers->new->parse($headers->to_string . "\x0d\x0a\x0d\x0a");
is_deeply $headers->to_hash(1), {'X-Test' => [23, 24], 'X-Test2' => ['foo']},
  'right structure';

# Headers in chunks
$headers = Mojo::Headers->new;
isa_ok $headers->parse(<<EOF), 'Mojo::Headers', 'right return value';
Content-Type: text/plain
EOF
ok !$headers->is_finished, 'parser is not finished';
ok !defined($headers->content_type), 'no value';
isa_ok $headers->parse(<<EOF), 'Mojo::Headers', 'right return value';
X-Bender: Bite my shiny
EOF
ok !$headers->is_finished, 'parser is not finished';
ok !defined($headers->connection), 'no value';
isa_ok $headers->parse(<<EOF), 'Mojo::Headers', 'right return value';
X-Bender: metal ass!

EOF
ok $headers->is_finished, 'parser is finished';
is $headers->content_type, 'text/plain', 'right value';
is $headers->header('X-Bender'), 'Bite my shiny, metal ass!', 'right value';

done_testing();
