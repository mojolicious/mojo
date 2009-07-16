#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 3;

# This is the greatest case of false advertising I’ve seen since I sued the
# movie “The Never Ending Story.”
use_ok('Mojo::Path');

my $path = Mojo::Path->new;
is($path->parse('/path')->to_string,   '/path');
is($path->parse('/path/0')->to_string, '/path/0');
