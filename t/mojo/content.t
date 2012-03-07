use Mojo::Base -strict;

use Test::More tests => 17;

# "No matter how good you are at something,
#  there's always about a million people better than you."
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

# Tainted environment
$content = Mojo::Content::MultiPart->new;
"a" =~ /(.)/;
ok !$content->charset, 'no charset';
"a" =~ /(.)/;
ok !$content->boundary, 'no boundary';
