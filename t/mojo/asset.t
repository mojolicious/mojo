use Mojo::Base -strict;

use Test::More;
use File::Basename 'dirname';
use File::Path 'mkpath';
use File::Spec::Functions qw(catdir tmpdir);
use Mojo::Asset::File;
use Mojo::Asset::Memory;

# File asset
my $file = Mojo::Asset::File->new;
$file->add_chunk('abc');
is $file->contains('abc'), 0,  '"abc" at position 0';
is $file->contains('bc'),  1,  '"bc" at position 1';
is $file->contains('db'),  -1, 'does not contain "db"';

# Cleanup
my $path = $file->path;
ok -e $path, 'temporary file exists';
undef $file;
ok !-e $path, 'temporary file has been cleaned up';

# Memory asset
my $mem = Mojo::Asset::Memory->new;
$mem->add_chunk('abc');
is $mem->contains('abc'), 0,  '"abc" at position 0';
is $mem->contains('bc'),  1,  '"bc" at position 1';
is $mem->contains('db'),  -1, 'does not contain "db"';

# Empty file asset
$file = Mojo::Asset::File->new;
is $file->contains('a'), -1, 'does not contain "a"';

# Empty memory asset
$mem = Mojo::Asset::Memory->new;
ok !$mem->is_range, 'no range';
is $mem->contains('a'), -1, 'does not contain "a"';

# File asset range support (a[bcdef])
$file = Mojo::Asset::File->new(start_range => 1);
ok $file->is_range, 'has range';
$file->add_chunk('abcdef');
is $file->contains('bcdef'), 0,  '"bcdef" at position 0';
is $file->contains('cdef'),  1,  '"cdef" at position 1';
is $file->contains('db'),    -1, 'does not contain "db"';

# Memory asset range support (a[bcdef])
$mem = Mojo::Asset::Memory->new(start_range => 1);
ok $mem->is_range, 'has range';
$mem->add_chunk('abcdef');
is $mem->contains('bcdef'), 0,  '"bcdef" at position 0';
is $mem->contains('cdef'),  1,  '"cdef" at position 1';
is $mem->contains('db'),    -1, 'does not contain "db"';

# File asset range support (ab[cdefghi]jk)
$file = Mojo::Asset::File->new(start_range => 2, end_range => 8);
ok $file->is_range, 'has range';
$file->add_chunk('abcdefghijk');
is $file->contains('cdefghi'), 0,         '"cdefghi" at position 0';
is $file->contains('fghi'),    3,         '"fghi" at position 3';
is $file->contains('f'),       3,         '"f" at position 3';
is $file->contains('hi'),      5,         '"hi" at position 5';
is $mem->contains('ij'),       -1,        'does not contain "ij"';
is $file->contains('db'),      -1,        'does not contain "db"';
is $file->get_chunk(0),        'cdefghi', 'chunk from position 0';
is $file->get_chunk(1),        'defghi',  'chunk from position 1';
is $file->get_chunk(5),        'hi',      'chunk from position 5';
is $file->get_chunk(0, 2), 'cd',  'chunk from position 0 (2 bytes)';
is $file->get_chunk(1, 3), 'def', 'chunk from position 1 (3 bytes)';
is $file->get_chunk(5, 1), 'h',   'chunk from position 5 (1 byte)';
is $file->get_chunk(5, 3), 'hi',  'chunk from position 5 (2 byte)';

# Memory asset range support (ab[cdefghi]jk)
$mem = Mojo::Asset::Memory->new(start_range => 2, end_range => 8);
ok $mem->is_range, 'has range';
$mem->add_chunk('abcdefghijk');
is $mem->contains('cdefghi'), 0,         '"cdefghi" at position 0';
is $mem->contains('fghi'),    3,         '"fghi" at position 3';
is $mem->contains('f'),       3,         '"f" at position 3';
is $mem->contains('hi'),      5,         '"hi" at position 5';
is $mem->contains('ij'),      -1,        'does not contain "ij"';
is $mem->contains('db'),      -1,        'does not contain "db"';
is $mem->get_chunk(0),        'cdefghi', 'chunk from position 0';
is $mem->get_chunk(1),        'defghi',  'chunk from position 1';
is $mem->get_chunk(5),        'hi',      'chunk from position 5';
is $mem->get_chunk(0, 2), 'cd',  'chunk from position 0 (2 bytes)';
is $mem->get_chunk(1, 3), 'def', 'chunk from position 1 (3 bytes)';
is $mem->get_chunk(5, 1), 'h',   'chunk from position 5 (1 byte)';
is $mem->get_chunk(5, 3), 'hi',  'chunk from position 5 (2 byte)';

# Huge file asset
$file = Mojo::Asset::File->new;
ok !$file->is_range, 'no range';
$file->add_chunk('a' x 131072);
$file->add_chunk('b');
$file->add_chunk('c' x 131072);
$file->add_chunk('ddd');
is $file->contains('a'),    0,      '"a" at position 0';
is $file->contains('b'),    131072, '"b" at position 131072';
is $file->contains('c'),    131073, '"c" at position 131073';
is $file->contains('abc'),  131071, '"abc" at position 131071';
is $file->contains('ccdd'), 262143, '"ccdd" at position 262143';
is $file->contains('dd'),   262145, '"dd" at position 262145';
is $file->contains('ddd'),  262145, '"ddd" at position 262145';
is $file->contains('e'),    -1,     'does not contain "e"';
is $file->contains('a' x 131072), 0,      '"a" x 131072 at position 0';
is $file->contains('c' x 131072), 131073, '"c" x 131072 at position 131073';
is $file->contains('b' . ('c' x 131072) . "ddd"), 131072,
  '"b" . ("c" x 131072) . "ddd" at position 131072';

# Huge file asset with range
$file = Mojo::Asset::File->new(start_range => 1, end_range => 262146);
$file->add_chunk('a' x 131072);
$file->add_chunk('b');
$file->add_chunk('c' x 131072);
$file->add_chunk('ddd');
is $file->contains('a'),    0,      '"a" at position 0';
is $file->contains('b'),    131071, '"b" at position 131071';
is $file->contains('c'),    131072, '"c" at position 131072';
is $file->contains('abc'),  131070, '"abc" at position 131070';
is $file->contains('ccdd'), 262142, '"ccdd" at position 262142';
is $file->contains('dd'),   262144, '"dd" at position 262144';
is $file->contains('ddd'),  -1,     'does not contain "ddd"';
is $file->contains('b' . ('c' x 131072) . 'ddd'), -1,
  'does not contain "b" . ("c" x 131072) . "ddd"';

# Move memory asset to file
$mem = Mojo::Asset::Memory->new->add_chunk('abc');
my $tmp = Mojo::Asset::File->new->add_chunk('x');
$path = $tmp->path;
ok -e $path, 'file exists';
undef $tmp;
ok !-e $path, 'file has been cleaned up';
is $mem->move_to($path)->slurp, 'abc', 'right content';
ok -e $path, 'file exists';
unlink $path;
ok !-e $path, 'file has been cleaned up';
is(Mojo::Asset::Memory->new->move_to($path)->slurp, '', 'no content');
ok -e $path, 'file exists';
unlink $path;
ok !-e $path, 'file has been cleaned up';

# Move file asset to file
$file = Mojo::Asset::File->new;
$file->add_chunk('bcd');
$tmp = Mojo::Asset::File->new;
$tmp->add_chunk('x');
$path = $tmp->path;
ok -e $path, 'file exists';
undef $tmp;
ok !-e $path, 'file has been cleaned up';
is $file->move_to($path)->slurp, 'bcd', 'right content';
undef $file;
ok -e $path, 'file exists';
unlink $path;
ok !-e $path, 'file has been cleaned up';
is(Mojo::Asset::File->new->move_to($path)->slurp, '', 'no content');
ok -e $path, 'file exists';
unlink $path;
ok !-e $path, 'file has been cleaned up';

# Upgrade
my $asset = Mojo::Asset::Memory->new(max_memory_size => 5, auto_upgrade => 1);
$asset = $asset->add_chunk('lala');
ok !$asset->is_file, 'stored in memory';
$asset = $asset->add_chunk('lala');
ok $asset->is_file, 'stored in file';
$asset = Mojo::Asset::Memory->new(max_memory_size => 5);
$asset = $asset->add_chunk('lala');
ok !$asset->is_file, 'stored in memory';
$asset = $asset->add_chunk('lala');
ok !$asset->is_file, 'stored in memory';

# Temporary directory
{
  mkpath my $tmpdir = catdir tmpdir, 'test';
  local $ENV{MOJO_TMPDIR} = $tmpdir;
  $file = Mojo::Asset::File->new;
  is($file->tmpdir, $tmpdir, 'same directory');
  $file->add_chunk('works!');
  is $file->slurp, 'works!', 'right content';
  is dirname($file->path), $tmpdir, 'same directory';
}

# Temporary file without cleanup
$file = Mojo::Asset::File->new(cleanup => 0)->add_chunk('test');
ok $file->is_file, 'stored in file';
is $file->slurp,   'test', 'right content';
is $file->size,    4, 'right size';
is $file->contains('es'), 1, '"es" at position 1';
$path = $file->path;
undef $file;
ok -e $path, 'file exists';
unlink $path;
ok !-e $path, 'file has been cleaned up';

done_testing();
