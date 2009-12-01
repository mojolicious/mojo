#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 2;

use_ok('Mojo::Content::Single');

my $content = Mojo::Content::Single->new;
is($content->body_contains('a'), 0);
