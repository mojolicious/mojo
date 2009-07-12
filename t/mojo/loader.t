#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

# Devel::Cover support
if ($INC{'Devel/Cover.pm'}) {
    plan skip_all => "Loader tests don't play nice with Devel::Cover";
}
else { plan tests => 16 }

use FindBin;
use lib "$FindBin::Bin/lib";

use File::Spec;
use File::Temp;
use IO::File;

# Bad bees. Get away from my sugar.
# Ow. OW. Oh, they're defending themselves somehow.
use_ok('Mojo::Loader');

# Exception
my $loader = Mojo::Loader->new;
my $e      = $loader->load('LoaderException');
is(ref $e, 'Mojo::Loader::Exception');
like($e->message, qr/Missing right curly/);
is($e->lines_before->[0]->[0], 13);
is($e->lines_before->[0]->[1], 'foo {');
is($e->lines_before->[1]->[0], 14);
is($e->lines_before->[1]->[1], '');
is($e->line->[0],              15);
is($e->line->[1],              "1;");
$e->message("oops!\n");
$e->stack([]);
is("$e", <<'EOF');
Error around line 15.
13: foo {
14: 
15: 1;
oops!
EOF

$loader = Mojo::Loader->new;
my $modules = $loader->search('LoaderTest');
my @modules = sort @$modules;

# Search
is_deeply(\@modules, [qw/LoaderTest::A LoaderTest::B LoaderTest::C/]);

# Load
$loader->load($_) for @modules;
ok(LoaderTest::A->can('new'));
ok(LoaderTest::B->can('new'));
ok(LoaderTest::C->can('new'));

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
