#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

use_ok 'Mojo::Content::MultiPart';
use_ok 'Mojo::Content::Single';

# No matter how good you are at something,
# there's always about a million people better than you.
my $content = Mojo::Content::Single->new;
is $content->body_contains('a'), 0, 'content contains "a"';
