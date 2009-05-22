#!perl

use strict;
use warnings;

use Test::More tests => 2;

use_ok('Mojo');

my $logger = Mojo::Log->new;
my $app = Mojo->new({log => $logger});
is($app->log, $logger)
