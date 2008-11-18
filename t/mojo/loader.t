#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 12;

use FindBin;
use lib "$FindBin::Bin/lib";

use File::Spec;
use File::Temp;
use IO::File;

# Bad bees. Get away from my sugar.
# Ow. OW. Oh, they're defending themselves somehow.
use_ok('Mojo::Loader');

my $loader  = Mojo::Loader->new;
my $modules = $loader->search('LoaderTest')->modules;
my @modules = sort @$modules;

# Search
is_deeply(\@modules, [qw/LoaderTest::A LoaderTest::B LoaderTest::C/]);

# Load
$loader->load;
ok(LoaderTest::A->can('new'));
ok(LoaderTest::B->can('new'));
ok(LoaderTest::C->can('new'));

# Instantiate
my $instances = $loader->build;
my @instances = sort { ref $a cmp ref $b } @$instances;
is(ref $instances[0], 'LoaderTest::A');
is(ref $instances[1], 'LoaderTest::B');
is(ref $instances[2], 'LoaderTest::C');

# Lazy
is(ref Mojo::Loader->load_build('LoaderTest::B'), 'LoaderTest::B');

# Base
$loader->base('LoaderTestBase');
my $instance = $loader->build->[0];
is(ref $instance, 'LoaderTest::B');

# Reload
my $file = IO::File->new;
my $dir  = File::Temp::tempdir();
my $path = File::Spec->catfile($dir, 'MojoTestReloader.pm');
$file->open("> $path");
$file->syswrite("package MojoTestReloader;\nsub test { 23 }\n1;");
$file->close;
push @INC, $dir;
require MojoTestReloader;
is(MojoTestReloader::test(), 23);
sleep 2;
$file->open("> $path");
$file->syswrite("package MojoTestReloader;\nsub test { 26 }\n1;");
$file->close;
Mojo::Loader->reload;
is(MojoTestReloader::test(), 26);
