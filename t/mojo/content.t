use Mojo::Base -strict;

use Test::More;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;

# Single
my $content = Mojo::Content::Single->new;
$content->asset->add_chunk('foo');
ok !$content->body_contains('a'), 'content does not contain "a"';
ok $content->body_contains('f'),   'content contains "f"';
ok $content->body_contains('o'),   'content contains "o"';
ok $content->body_contains('foo'), 'content contains "foo"';

# Multipart
$content = Mojo::Content::MultiPart->new(parts => [$content]);
ok !$content->body_contains('a'), 'content does not contain "a"';
ok $content->body_contains('f'),   'content contains "f"';
ok $content->body_contains('o'),   'content contains "o"';
ok $content->body_contains('foo'), 'content contains "foo"';
push @{$content->parts}, Mojo::Content::Single->new;
$content->parts->[1]->asset->add_chunk('.*?foo+');
$content->parts->[1]->headers->header('X-Bender' => 'bar+');
ok !$content->body_contains('z'), 'content does not contain "z"';
ok $content->body_contains('f'),       'content contains "f"';
ok $content->body_contains('o'),       'content contains "o"';
ok $content->body_contains('foo'),     'content contains "foo"';
ok $content->body_contains('bar+'),    'content contains "bar+"';
ok $content->body_contains('.'),       'content contains "."';
ok $content->body_contains('.*?foo+'), 'content contains ".*?foo+"';
ok !$content->headers->content_type, 'no "Content-Type" header';
ok my $boundary = $content->build_boundary, 'boundary has been generated';
is $boundary, $content->boundary, 'same boundary';
is $content->headers->content_type, "multipart/mixed; boundary=$boundary",
  'right "Content-Type" header';

# Dynamic content
$content = Mojo::Content::Single->new;
$content->write('Hello ')->write('World!');
ok $content->is_dynamic, 'dynamic content';
ok !$content->is_chunked, 'no chunked content';
$content->write('');
ok $content->is_dynamic, 'dynamic content';
is $content->build_body, 'Hello World!', 'right content';

# Chunked content
$content = Mojo::Content::Single->new;
$content->write_chunk('Hello ')->write_chunk('World!');
ok $content->is_dynamic, 'dynamic content';
ok $content->is_chunked, 'chunked content';
$content->write_chunk('');
ok $content->is_dynamic, 'dynamic content';
is $content->build_body,
  "6\x0d\x0aHello \x0d\x0a6\x0d\x0aWorld!\x0d\x0a0\x0d\x0a\x0d\x0a",
  'right content';

# Multipart boundary detection
$content = Mojo::Content::MultiPart->new;
is $content->boundary, undef, 'no boundary';
$content->headers->content_type(
  'multipart/form-data; boundary  =  "azAZ09\'(),.:?-_+/"');
is $content->boundary, "azAZ09\'(),.:?-_+/", 'right boundary';
is $content->boundary, $content->build_boundary, 'same boundary';
$content->headers->content_type('multipart/form-data');
is $content->boundary, undef, 'no boundary';
$content->headers->content_type('multipart/form-data; boundary="foo bar baz"');
is $content->boundary, 'foo bar baz', 'right boundary';
is $content->boundary, $content->build_boundary, 'same boundary';
$content->headers->content_type('MultiPart/Form-Data; BounDaRy="foo 123"');
is $content->boundary, 'foo 123', 'right boundary';
is $content->boundary, $content->build_boundary, 'same boundary';

# Charset detection
$content = Mojo::Content::Single->new;
is $content->charset, undef, 'no charset';
$content->headers->content_type('text/plain; charset=UTF-8');
is $content->charset, 'UTF-8', 'right charset';
$content->headers->content_type('text/plain; charset="UTF-8"');
is $content->charset, 'UTF-8', 'right charset';
$content->headers->content_type('text/plain; charset  =  UTF-8');
is $content->charset, 'UTF-8', 'right charset';
$content->headers->content_type('text/plain; charset  =  "UTF-8"');
is $content->charset, 'UTF-8', 'right charset';

# Partial content with 128-bit content length
$content = Mojo::Content::Single->new;
$content->parse(
  "Content-Length: 18446744073709551616\x0d\x0a\x0d\x0aHello World!");
is $content->asset->size, 12, 'right size';

# Abstract methods
eval { Mojo::Content->body_contains };
like $@, qr/Method "body_contains" not implemented by subclass/, 'right error';
eval { Mojo::Content->body_size };
like $@, qr/Method "body_size" not implemented by subclass/, 'right error';
eval { Mojo::Content->get_body_chunk };
like $@, qr/Method "get_body_chunk" not implemented by subclass/,
  'right error';

done_testing();
