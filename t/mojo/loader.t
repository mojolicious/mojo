use Mojo::Base -strict;

# Disable libev
BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More tests => 57;

use FindBin;
use lib "$FindBin::Bin/lib";

# "Bad bees. Get away from my sugar.
#  Ow. OW. Oh, they're defending themselves somehow."
use Mojo::Loader;

# Single character core module
my $loader = Mojo::Loader->new;
ok !$loader->load('B');
ok !!UNIVERSAL::can(B => 'svref_2object');

# Exception
my $e = $loader->load('Mojo::LoaderException');
isa_ok $e, 'Mojo::Exception', 'right object';
like $e->message, qr/Missing right curly/, 'right message';
is $e->lines_before->[0][0],   5,         'right line';
like $e->lines_before->[0][1], qr/Apu/,   'right value';
is $e->lines_before->[1][0],   6,         'right line';
like $e->lines_before->[1][1], qr/whizz/, 'right value';
is $e->lines_before->[2][0],   7,         'right line';
is $e->lines_before->[2][1],   '',        'right value';
is $e->lines_before->[3][0],   8,         'right line';
is $e->lines_before->[3][1],   'foo {',   'right value';
is $e->lines_before->[4][0],   9,         'right line';
is $e->lines_before->[4][1],   '',        'right value';
is $e->line->[0], 10,   'right line';
is $e->line->[1], "1;", 'right value';
like "$e", qr/Missing right curly/, 'right message';

# Complicated exception
$loader = Mojo::Loader->new;
$e      = $loader->load('Mojo::LoaderException2');
isa_ok $e, 'Mojo::Exception', 'right object';
like $e->message, qr/Exception/, 'right message';
is $e->lines_before->[0][0], 1,                                 'right line';
is $e->lines_before->[0][1], 'package Mojo::LoaderException2;', 'right value';
is $e->lines_before->[1][0], 2,                                 'right line';
is $e->lines_before->[1][1], 'use Mojo::Base -strict;',         'right value';
is $e->lines_before->[2][0], 3,                                 'right line';
is $e->lines_before->[2][1], '',                                'right value';
is $e->line->[0], 4, 'right line';
is $e->line->[1], 'Mojo::LoaderException2_2::throw_error();', 'right value';
is $e->lines_after->[0][0], 5,    'right line';
is $e->lines_after->[0][1], '',   'right value';
is $e->lines_after->[1][0], 6,    'right line';
is $e->lines_after->[1][1], '1;', 'right value';
like "$e", qr/Exception/, 'right message';

# Search
$loader = Mojo::Loader->new;
my @modules = sort @{$loader->search('Mojo::LoaderTest')};
is_deeply \@modules,
  [qw(Mojo::LoaderTest::A Mojo::LoaderTest::B Mojo::LoaderTest::C)],
  'found the right modules';
is_deeply [sort @{$loader->search("Mojo'LoaderTest")}],
  [qw(Mojo'LoaderTest::A Mojo'LoaderTest::B Mojo'LoaderTest::C)],
  'found the right modules';

# Load
ok !$loader->load("Mojo'LoaderTest::A"), 'loaded successfully';
ok !!Mojo::LoaderTest::A->can('new'), 'loaded successfully';
$loader->load($_) for @modules;
ok !!Mojo::LoaderTest::B->can('new'), 'loaded successfully';
ok !!Mojo::LoaderTest::C->can('new'), 'loaded successfully';

# Class does not exist
is $loader->load('Mojo::LoaderTest'), 1, 'nothing to load';

# Invalid class
is $loader->load('Mojolicious/Lite'),      1,     'nothing to load';
is $loader->load('Mojolicious/Lite.pm'),   1,     'nothing to load';
is $loader->load('Mojolicious\Lite'),      1,     'nothing to load';
is $loader->load('Mojolicious\Lite.pm'),   1,     'nothing to load';
is $loader->load('::Mojolicious::Lite'),   1,     'nothing to load';
is $loader->load('Mojolicious::Lite::'),   1,     'nothing to load';
is $loader->load('::Mojolicious::Lite::'), 1,     'nothing to load';
is $loader->load('Mojolicious::Lite'),     undef, 'loaded successfully';

# UNIX DATA templates
my $unix = "@@ template1\nFirst Template\n@@ template2\r\nSecond Template\n";
open my $data, '<', \$unix;
no strict 'refs';
*{"Example::Package::UNIX::DATA"} = $data;
is $loader->data('Example::Package::UNIX', 'template1'), "First Template\n",
  'right template';
is $loader->data('Example::Package::UNIX', 'template2'), "Second Template\n",
  'right template';
is_deeply [sort keys %{$loader->data('Example::Package::UNIX')}],
  [qw(template1 template2)], 'right DATA files';
close $data;

# Windows DATA templates
my $windows
  = "@@ template3\r\nThird Template\r\n@@ template4\r\nFourth Template\r\n";
open $data, '<', \$windows;
no strict 'refs';
*{"Example::Package::Windows::DATA"} = $data;
is $loader->data('Example::Package::Windows', 'template3'),
  "Third Template\r\n", 'right template';
is $loader->data('Example::Package::Windows', 'template4'),
  "Fourth Template\r\n", 'right template';
is_deeply [sort keys %{$loader->data('Example::Package::Windows')}],
  [qw(template3 template4)], 'right DATA files';
close $data;

# Mixed whitespace
my $mixed = "@\@template5\n5\n\n@@  template6\n6\n@@     template7\n7";
open $data, '<', \$mixed;
no strict 'refs';
*{"Example::Package::Mixed::DATA"} = $data;
is $loader->data('Example::Package::Mixed', 'template5'), "5\n\n",
  'right template';
is $loader->data('Example::Package::Mixed', 'template6'), "6\n",
  'right template';
is $loader->data('Example::Package::Mixed', 'template7'), '7',
  'right template';
is_deeply [sort keys %{$loader->data('Example::Package::Mixed')}],
  [qw(template5 template6 template7)], 'right DATA files';
close $data;
