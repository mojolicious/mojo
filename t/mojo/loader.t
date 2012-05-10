use Mojo::Base -strict;

use Test::More tests => 45;

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
my $e = $loader->load('LoaderException');
isa_ok $e, 'Mojo::Exception', 'right object';
like $e->message, qr/Missing right curly/, 'right message';
is $e->lines_before->[0]->[0],   5,         'right line';
like $e->lines_before->[0]->[1], qr/Apu/,   'right value';
is $e->lines_before->[1]->[0],   6,         'right line';
like $e->lines_before->[1]->[1], qr/whizz/, 'right value';
is $e->lines_before->[2]->[0],   7,         'right line';
is $e->lines_before->[2]->[1],   '',        'right value';
is $e->lines_before->[3]->[0],   8,         'right line';
is $e->lines_before->[3]->[1],   'foo {',   'right value';
is $e->lines_before->[4]->[0],   9,         'right line';
is $e->lines_before->[4]->[1],   '',        'right value';
is $e->line->[0], 10,   'right line';
is $e->line->[1], "1;", 'right value';
like "$e", qr/Missing right curly/, 'right message';

# Complicated exception
$loader = Mojo::Loader->new;
$e      = $loader->load('LoaderException2');
isa_ok $e, 'Mojo::Exception', 'right object';
like $e->message, qr/Exception/, 'right message';
is $e->lines_before->[0]->[0], 1,                           'right line';
is $e->lines_before->[0]->[1], 'package LoaderException2;', 'right value';
is $e->lines_before->[1]->[0], 2,                           'right line';
is $e->lines_before->[1]->[1], 'use Mojo::Base -strict;',   'right value';
is $e->lines_before->[2]->[0], 3,                           'right line';
is $e->lines_before->[2]->[1], '',                          'right value';
is $e->line->[0], 4, 'right line';
is $e->line->[1], 'LoaderException2_2::throw_error();', 'right value';
is $e->lines_after->[0]->[0], 5,    'right line';
is $e->lines_after->[0]->[1], '',   'right value';
is $e->lines_after->[1]->[0], 6,    'right line';
is $e->lines_after->[1]->[1], '1;', 'right value';
like "$e", qr/Exception/, 'right message';

$loader = Mojo::Loader->new;
my $modules = $loader->search('LoaderTest');
my @modules = sort @$modules;

# Search
is_deeply \@modules, [qw(LoaderTest::A LoaderTest::B LoaderTest::C)],
  'found the right modules';

# Load
$loader->load($_) for @modules;
ok !!LoaderTest::A->can('new'), 'loaded successfully';
ok !!LoaderTest::B->can('new'), 'loaded successfully';
ok !!LoaderTest::C->can('new'), 'loaded successfully';

# Class does not exist
is $loader->load('LoaderTest'), 1, 'nothing to load';

# Invalid class
is $loader->load('Mojolicious/Lite'),      1,     'nothing to load';
is $loader->load('Mojolicious/Lite.pm'),   1,     'nothing to load';
is $loader->load('Mojolicious\Lite'),      1,     'nothing to load';
is $loader->load('Mojolicious\Lite.pm'),   1,     'nothing to load';
is $loader->load('::Mojolicious::Lite'),   1,     'nothing to load';
is $loader->load('Mojolicious::Lite::'),   1,     'nothing to load';
is $loader->load('::Mojolicious::Lite::'), 1,     'nothing to load';
is $loader->load('Mojolicious::Lite'),     undef, 'loaded successfully';
