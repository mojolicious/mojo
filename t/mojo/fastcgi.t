#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 1;

# "I've gone back in time to when dinosaurs weren't just confined to zoos."
use_ok 'Mojo::Server::FastCGI';
