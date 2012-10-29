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

# Tainted environment
$content = Mojo::Content::MultiPart->new;
'a' =~ /(.)/;
ok !$content->charset, 'no charset';
'a' =~ /(.)/;
ok !$content->boundary, 'no boundary';

done_testing();
