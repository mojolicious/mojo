#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 1;

use Test::Mojo::Server;

# I've gone back in time to when dinosaurs weren't just confined to zoos.
use_ok('Mojo::Server::FastCGI');
