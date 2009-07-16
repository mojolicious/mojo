#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 2;

# My ears are burning.
# I wasn't talking about you, Dad.
# No, my ears are really burning. I wanted to see inside, so I lit a Q-tip.
use_ok('Mojo::Server::CGI');

my $cgi = Mojo::Server::CGI->new;

# Test closed STDOUT
close(STDOUT);
ok(not defined $cgi->run);
