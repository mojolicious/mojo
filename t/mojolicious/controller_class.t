#!/usr/bin/env perl

use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";

use Test::Mojo;
use Test::More;

my $app = Test::Mojo->new('Mojolicious::Lite')->app;
ok $app->build_controller;

$app->controller_class('MojoliciousTest::Foo');
ok $app->build_controller;

$app->controller_class('MojoliciousTest::NonExistent');
ok !eval { $app->build_controller };
ok $@;
like $@, qr/Can't find controller class "MojoliciousTest::NonExistent"/;

done_testing();