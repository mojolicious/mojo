#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More 'no_plan';

use_ok('Mojo::Asset::File');

my $asset_file = Mojo::Asset::File->new;
$asset_file->add_chunk('abc');
is($asset_file->contains(''), 0, 'contains empty string');
is($asset_file->contains('abc'), 0, 'contains all string');
is($asset_file->contains('bc'), 1, 'contains partial string');
ok(!$asset_file->contains('db'), 'contains not match');

$asset_file = Mojo::Asset::File->new;
is($asset_file->contains(''), 0, 'contains empty string search empty content');
