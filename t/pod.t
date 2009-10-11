#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

eval "use Test::Pod 1.14";
plan skip_all => 'Test::Pod 1.14 required' if $@;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# Marge, it takes two to lie. One to lie and one to listen.
all_pod_files_ok();
