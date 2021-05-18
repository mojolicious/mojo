use Mojo::Base -strict;

use Test::More;
use Carp qw(croak);
use Config qw(%Config);
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::File qw(path tempdir);

subtest 'File asset' => sub {
  my $file = Mojo::Asset::File->new;
  is $file->size, 0, 'file is empty';
  is $file->mtime, (stat $file->handle)[9], 'right mtime';
  is $file->slurp, '', 'file is empty';
  $file->add_chunk('abc');
  is $file->contains('abc'), 0,  '"abc" at position 0';
  is $file->contains('bc'),  1,  '"bc" at position 1';
  is $file->contains('db'),  -1, 'does not contain "db"';
  is $file->size, 3, 'right size';
  is $file->mtime, (stat $file->handle)[9], 'right mtime';
  is $file->to_file, $file, 'same object';

  my $path = $file->path;
  ok -e $path, 'temporary file exists';
  undef $file;
  ok !-e $path, 'temporary file has been cleaned up';
};

subtest 'Memory asset' => sub {
  my $mem = Mojo::Asset::Memory->new;
  $mem->add_chunk('abc');
  is $mem->contains('abc'), 0,  '"abc" at position 0';
  is $mem->contains('bc'),  1,  '"bc" at position 1';
  is $mem->contains('db'),  -1, 'does not contain "db"';
  is $mem->size,  3, 'right size';
  is $mem->mtime, $^T, 'right mtime';
  is $mem->mtime, Mojo::Asset::Memory->new->mtime, 'same mtime';
  my $mtime = $mem->mtime;
  is $mem->mtime($mtime + 23)->mtime, $mtime + 23, 'right mtime';
};

subtest 'Asset upgrade from memory to file' => sub {
  my $mem = Mojo::Asset::Memory->new;
  $mem->add_chunk('abcdef');
  isa_ok $mem->to_file, 'Mojo::Asset::File', 'right class';
  is $mem->to_file->slurp, $mem->slurp, 'same content';
  my $file = $mem->to_file;
  my $path = $file->path;
  ok -e $path, 'file exists';
  undef $file;
  ok !-e $path, 'file has been cleaned up';
};

subtest 'Empty file asset' => sub {
  my $file = Mojo::Asset::File->new;
  is $file->size, 0, 'asset is empty';
  is $file->get_chunk(0), '', 'no content';
  is $file->slurp, '', 'no content';
  is $file->contains('a'), -1, 'does not contain "a"';
};

subtest 'Empty memory asset' => sub {
  my $mem = Mojo::Asset::Memory->new;
  is $mem->size, 0, 'asset is empty';
  is $mem->get_chunk(0), '', 'no content';
  is $mem->slurp, '', 'no content';
  ok !$mem->is_range, 'no range';
  is $mem->contains('a'), -1, 'does not contain "a"';
};

subtest 'File asset range support (a[bcdefabc])' => sub {
  my $file = Mojo::Asset::File->new(start_range => 1);
  ok $file->is_range, 'has range';
  $file->add_chunk('abcdefabc');
  is $file->contains('bcdef'), 0,  '"bcdef" at position 0';
  is $file->contains('cdef'),  1,  '"cdef" at position 1';
  is $file->contains('abc'),   5,  '"abc" at position 5';
  is $file->contains('db'),    -1, 'does not contain "db"';
};

subtest 'Memory asset range support (a[bcdefabc])' => sub {
  my $mem = Mojo::Asset::Memory->new(start_range => 1);
  ok $mem->is_range, 'has range';
  $mem->add_chunk('abcdefabc');
  is $mem->contains('bcdef'), 0,  '"bcdef" at position 0';
  is $mem->contains('cdef'),  1,  '"cdef" at position 1';
  is $mem->contains('abc'),   5,  '"abc" at position 5';
  is $mem->contains('db'),    -1, 'does not contain "db"';
};

subtest 'File asset range support (ab[cdefghi]jk)' => sub {
  my $file = Mojo::Asset::File->new(start_range => 2, end_range => 8);
  ok $file->is_range, 'has range';
  $file->add_chunk('abcdefghijk');
  is $file->contains('cdefghi'), 0,         '"cdefghi" at position 0';
  is $file->contains('fghi'),    3,         '"fghi" at position 3';
  is $file->contains('f'),       3,         '"f" at position 3';
  is $file->contains('hi'),      5,         '"hi" at position 5';
  is $file->contains('db'),      -1,        'does not contain "db"';
  is $file->get_chunk(0),        'cdefghi', 'chunk from position 0';
  is $file->get_chunk(1),        'defghi',  'chunk from position 1';
  is $file->get_chunk(5),        'hi',      'chunk from position 5';
  is $file->get_chunk(0, 2), 'cd',  'chunk from position 0 (2 bytes)';
  is $file->get_chunk(1, 3), 'def', 'chunk from position 1 (3 bytes)';
  is $file->get_chunk(5, 1), 'h',   'chunk from position 5 (1 byte)';
  is $file->get_chunk(5, 3), 'hi',  'chunk from position 5 (2 byte)';
};

subtest 'Memory asset range support (ab[cdefghi]jk)' => sub {
  my $mem = Mojo::Asset::Memory->new(start_range => 2, end_range => 8);
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
};

subtest 'Huge file asset' => sub {
  my $file = Mojo::Asset::File->new;
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
  is $file->contains('b' . ('c' x 131072) . "ddd"), 131072, '"b" . ("c" x 131072) . "ddd" at position 131072';
};

subtest 'Huge file asset with range' => sub {
  my $file = Mojo::Asset::File->new(start_range => 1, end_range => 262146);
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
  is $file->contains('b' . ('c' x 131072) . 'ddd'), -1, 'does not contain "b" . ("c" x 131072) . "ddd"';
};

subtest 'Move memory asset to file' => sub {
  my $mem  = Mojo::Asset::Memory->new->add_chunk('abc');
  my $tmp  = Mojo::Asset::File->new->add_chunk('x');
  my $path = $tmp->path;
  ok -e $path, 'file exists';
  undef $tmp;
  ok !-e $path, 'file has been cleaned up';
  is $mem->move_to($path)->slurp, 'abc', 'right content';
  ok -e $path, 'file exists';
  ok unlink($path), 'unlinked file';
  ok !-e $path, 'file has been cleaned up';
  is(Mojo::Asset::Memory->new->move_to($path)->slurp, '', 'no content');
  ok -e $path, 'file exists';
  ok unlink($path), 'unlinked file';
  ok !-e $path, 'file has been cleaned up';
};

subtest 'Move file asset to file' => sub {
  my $file = Mojo::Asset::File->new;
  $file->add_chunk('bcd');
  my $tmp = Mojo::Asset::File->new;
  $tmp->add_chunk('x');
  isnt $file->path, $tmp->path, 'different paths';
  my $path = $tmp->path;
  ok -e $path, 'file exists';
  undef $tmp;
  ok !-e $path, 'file has been cleaned up';
  is $file->move_to($path)->slurp, 'bcd', 'right content';
  undef $file;
  ok -e $path, 'file exists';
  ok unlink($path), 'unlinked file';
  ok !-e $path, 'file has been cleaned up';
  is(Mojo::Asset::File->new->move_to($path)->slurp, '', 'no content');
  ok -e $path, 'file exists';
  ok unlink($path), 'unlinked file';
  ok !-e $path, 'file has been cleaned up';
};

subtest 'Upgrade' => sub {
  my $asset = Mojo::Asset::Memory->new(max_memory_size => 5, auto_upgrade => 1);
  my $upgrade;
  $asset->on(upgrade => sub { $upgrade++ });
  $asset = $asset->add_chunk('lala');
  ok !$upgrade, 'upgrade event has not been emitted';
  ok !$asset->is_file, 'stored in memory';
  $asset = $asset->add_chunk('lala');
  is $upgrade, 1, 'upgrade event has been emitted once';
  ok $asset->is_file, 'stored in file';
  $asset = $asset->add_chunk('lala');
  is $upgrade, 1, 'upgrade event was not emitted again';
  ok $asset->is_file, 'stored in file';
  is $asset->slurp,   'lalalalalala', 'right content';
  ok $asset->cleanup, 'file will be cleaned up';
  $asset = Mojo::Asset::Memory->new(max_memory_size => 5);
  $asset = $asset->add_chunk('lala');
  ok !$asset->is_file, 'stored in memory';
  $asset = $asset->add_chunk('lala');
  ok !$asset->is_file, 'stored in memory';
};

subtest 'Change temporary directory during upgrade' => sub {
  my $tmpdir = tempdir;
  my $mem    = Mojo::Asset::Memory->new(auto_upgrade => 1, max_memory_size => 10);
  $mem->on(
    upgrade => sub {
      my ($mem, $file) = @_;
      $file->tmpdir($tmpdir);
    }
  );
  my $file = $mem->add_chunk('aaaaaaaaaaa');
  ok $file->is_file, 'stored in file';
  is $file->slurp, 'aaaaaaaaaaa', 'right content';
  is path($file->path)->dirname, $tmpdir, 'right directory';
};

subtest 'Temporary directory' => sub {
  local $ENV{MOJO_TMPDIR} = my $tmpdir = tempdir;
  my $file = Mojo::Asset::File->new;
  is($file->tmpdir, $tmpdir, 'same directory');
  $file->add_chunk('works!');
  is $file->slurp, 'works!', 'right content';
  is path($file->path)->dirname, $tmpdir, 'same directory';
};

subtest 'Custom temporary file' => sub {
  my $tmpdir = tempdir;
  my $path   = $tmpdir->child('test.file');
  ok !-e $path, 'file does not exist';
  my $file = Mojo::Asset::File->new(path => $path);
  is $file->path, $path, 'right path';
  ok !-e $path, 'file still does not exist';
  $file->add_chunk('works!');
  ok -e $path, 'file exists';
  is $file->slurp, 'works!', 'right content';
  undef $file;
  ok !-e $path, 'file has been cleaned up';
};

subtest 'Temporary file without cleanup' => sub {
  my $file = Mojo::Asset::File->new(cleanup => 0)->add_chunk('test');
  ok $file->is_file, 'stored in file';
  is $file->slurp,   'test', 'right content';
  is $file->size,    4,      'right size';
  is $file->mtime, (stat $file->handle)[9], 'right mtime';
  is $file->contains('es'), 1, '"es" at position 1';
  my $path = $file->path;
  undef $file;
  ok -e $path, 'file exists';
  ok unlink($path), 'unlinked file';
  ok !-e $path, 'file has been cleaned up';
};

subtest 'Incomplete write' => sub {
  no warnings 'redefine';
  local *IO::Handle::syswrite = sub { $! = 0; 2 };
  eval { Mojo::Asset::File->new->add_chunk('test') };
  like $@, qr/Can't write to asset: .*/, 'right error';
};

subtest 'Forked process' => sub {
  plan skip_all => 'Real fork is required!' if $Config{d_pseudofork};
  my $file = Mojo::Asset::File->new->add_chunk('Fork test!');
  my $path = $file->path;
  ok -e $path, 'file exists';
  is $file->slurp, 'Fork test!', 'right content';
  croak "Can't fork: $!" unless defined(my $pid = fork);
  exit 0                 unless $pid;
  waitpid $pid, 0 if $pid;
  ok -e $path, 'file still exists';
  is $file->slurp, 'Fork test!', 'right content';
  undef $file;
  ok !-e $path, 'file has been cleaned up';
};

subtest 'Abstract methods' => sub {
  eval { Mojo::Asset->add_chunk };
  like $@, qr/Method "add_chunk" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->contains };
  like $@, qr/Method "contains" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->get_chunk };
  like $@, qr/Method "get_chunk" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->move_to };
  like $@, qr/Method "move_to" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->mtime };
  like $@, qr/Method "mtime" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->size };
  like $@, qr/Method "size" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->slurp };
  like $@, qr/Method "slurp" not implemented by subclass/, 'right error';
  eval { Mojo::Asset->to_file };
  like $@, qr/Method "to_file" not implemented by subclass/, 'right error';
};

done_testing();
