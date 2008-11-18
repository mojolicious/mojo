#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

# Would you kindly shut your noise-hole?
use Test::More tests => 5;

package Mojo::TestServerViaEnv;
use base 'Mojo';

package Mojo::TestServerViaApp;
use base 'Mojo';

package main;

use_ok('Mojo::Server');

my $server = Mojo::Server->new;
isa_ok($server, 'Mojo::Server');

# Test the default
my $app = $server->new->app;
isa_ok($app, 'Mojo::HelloWorld');

# Test an explicit class name
$app = $server->new(app_class => 'Mojo::TestServerViaApp')->app;
isa_ok($app, 'Mojo::TestServerViaApp');

# Test setting the class name through the environment
my $backup = $ENV{MOJO_APP} || '';
$ENV{MOJO_APP} = 'Mojo::TestServerViaEnv';
$app = $server->new->app;
isa_ok($app, 'Mojo::TestServerViaEnv');
$ENV{MOJO_APP} = $backup;
