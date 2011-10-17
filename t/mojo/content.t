#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 17;

# "No matter how good you are at something,
#  there's always about a million people better than you."
use_ok 'Mojo::Content::MultiPart';
use_ok 'Mojo::Content::Single';

# Single
my $content = Mojo::Content::Single->new;
$content->asset->add_chunk('foo');
is $content->body_contains('a'),   undef, 'content does not contain "a"';
is $content->body_contains('f'),   1,     'content contains "f"';
is $content->body_contains('o'),   1,     'content contains "o"';
is $content->body_contains('foo'), 1,     'content contains "foo"';

# Multipart
$content = Mojo::Content::MultiPart->new(parts => [$content]);
is $content->body_contains('a'),   undef, 'content does not contain "a"';
is $content->body_contains('f'),   1,     'content contains "f"';
is $content->body_contains('o'),   1,     'content contains "o"';
is $content->body_contains('foo'), 1,     'content contains "foo"';
push @{$content->parts}, Mojo::Content::Single->new;
$content->parts->[1]->asset->add_chunk('.*?foo+');
$content->parts->[1]->headers->header('X-Bender' => 'bar+');
is $content->body_contains('z'),       undef, 'content does not contain "z"';
is $content->body_contains('f'),       1,     'content contains "f"';
is $content->body_contains('o'),       1,     'content contains "o"';
is $content->body_contains('foo'),     1,     'content contains "foo"';
is $content->body_contains('bar+'),    1,     'content contains "bar+"';
is $content->body_contains('.'),       1,     'content contains "."';
is $content->body_contains('.*?foo+'), 1,     'content contains ".*?foo+"';
