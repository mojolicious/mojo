use Mojo::Base -strict;

use Test::More;
use Cwd qw(getcwd realpath);
use Fcntl 'O_RDONLY';
use File::Basename qw(basename dirname);
use File::Spec::Functions qw(abs2rel canonpath catfile rel2abs splitdir);
use File::Temp;
use Mojo::File qw(path tempdir tempfile);
use Mojo::Util 'encode';

# Constructor
is(Mojo::File->new, canonpath(getcwd), 'same path');
is path(), canonpath(getcwd), 'same path';
is path()->to_string, canonpath(getcwd), 'same path';
is path('/foo/bar'), '/foo/bar', 'same path';
is path('foo', 'bar', 'baz'), catfile('foo', 'bar', 'baz'), 'same path';

# Tap into method chain
is path('/home')->tap(sub { $$_ .= '/sri' })->to_string, '/home/sri',
  'same path';

# Children
is path('foo', 'bar')->child('baz', 'yada'),
  catfile(catfile('foo', 'bar'), 'baz', 'yada'), 'same path';

# Siblings
is path('foo', 'bar')->sibling('baz', 'yada'),
  catfile(scalar dirname(catfile('foo', 'bar')), 'baz', 'yada'), 'same path';

# Array
is_deeply path('foo', 'bar')->to_array, [splitdir catfile('foo', 'bar')],
  'same structure';
is_deeply [@{path('foo', 'bar')}], [splitdir catfile('foo', 'bar')],
  'same structure';

# Absolute
is path('file.t')->to_abs, rel2abs('file.t'), 'same path';

# Relative
is path('test.txt')->to_abs->to_rel(getcwd),
  abs2rel(rel2abs('test.txt'), getcwd), 'same path';

# Resolved
is path('.')->realpath, realpath('.'), 'same path';

# Basename
is path('file.t')->to_abs->basename, basename(rel2abs 'file.t'), 'same path';
is path('file.t')->to_abs->basename('.t'), basename(rel2abs('file.t'), '.t'),
  'same path';
is path('file.t')->basename('.t'), basename('file.t', '.t'), 'same path';

# Dirname
is path('file.t')->to_abs->dirname, scalar dirname(rel2abs 'file.t'),
  'same path';

# Checks
ok path(__FILE__)->to_abs->is_abs, 'path is absolute';
ok !path('file.t')->is_abs, 'path is not absolute';

# Temporary directory
my $dir  = tempdir;
my $path = "$dir";
ok -d $path, 'directory exists';
undef $dir;
ok !-d $path, 'directory does not exist anymore';
$dir = tempdir 'mytestXXXXX';
ok -d $dir, 'directory exists';
like $dir->basename, qr/mytest.{5}$/, 'right format';

# Temporary diectory (separate object)
$dir  = Mojo::File->new(File::Temp->newdir);
$path = "$dir";
ok -d $path, 'directory exists';
undef $dir;
ok !-d $path, 'directory does not exist anymore';

# Temporary file
$dir = tempdir;
my $file = tempfile(DIR => $dir);
$path = "$file";
ok -f $path, 'file exists';
is $file->dirname, $dir, 'same directory';
is $file->spurt('test')->slurp, 'test', 'right result';
undef $file;
ok !-f $path, 'file does not exist anymore';

# Open
$file = tempfile;
$file->spurt("test\n123\n");
my $handle = $file->open('<');
is_deeply [<$handle>], ["test\n", "123\n"], 'right structure';
$handle = $file->open('r');
is_deeply [<$handle>], ["test\n", "123\n"], 'right structure';
$handle = $file->open(O_RDONLY);
is_deeply [<$handle>], ["test\n", "123\n"], 'right structure';
$file->spurt(encode('UTF-8', '♥'));
$handle = $file->open('<:encoding(UTF-8)');
is_deeply [<$handle>], ['♥'], 'right structure';
$dir = tempdir;
eval { $dir->child('does_not_exist')->open('<') };
like $@, qr/^Can't open file/, 'right error';
eval { $dir->child('does_not_exist')->slurp };
like $@, qr/^Can't open file/, 'right error';
eval { $dir->child('foo')->make_path->spurt('fail') };
like $@, qr/^Can't open file/, 'right error';

# Make path
$dir = tempdir;
my $subdir = $dir->child('foo', 'bar');
ok !-d $subdir, 'directory does not exist anymore';
$subdir->make_path;
ok -d $subdir, 'directory exists';
my $nextdir = $dir->child('foo', 'foobar')->make_path({error => \my $error});
ok -d $nextdir, 'directory exists';
ok $error, 'directory already existed';

# Remove
$dir = tempdir;
$dir->child('test.txt')->spurt('test!');
ok -e $dir->child('test.txt'), 'file exists';
is $dir->child('test.txt')->slurp, 'test!', 'right content';
ok !-e $dir->child('test.txt')->remove->touch->remove->remove,
  'file no longer exists';
eval { $dir->child('foo')->make_path->remove };
like $@, qr/^Can't remove file/, 'right error';

# Remove tree
$dir = tempdir;
$dir->child('foo', 'bar')->make_path->child('test.txt')->spurt('test!');
is $dir->child('foo', 'bar', 'test.txt')->slurp, 'test!', 'right content';
$subdir = $dir->child('foo', 'foobar')->make_path;
ok -e $subdir->child('bar')->make_path->child('test.txt')->spurt('test'),
  'file created';
ok -d $subdir->remove_tree({keep_root => 1}), 'directory still exists';
ok !-e $subdir->child('bar'), 'children have been removed';
ok !-e $dir->child('foo')->remove_tree->to_string, 'directory has been removed';

# Move to
$dir = tempdir;
my $destination = $dir->child('dest.txt');
my $source      = $dir->child('src.txt')->spurt('works!');
ok -f $source,       'file exists';
ok !-f $destination, 'file does not exists';
is $source->move_to($destination)->to_string, $destination, 'same path';
ok !-f $source,     'file no longer exists';
ok -f $destination, 'file exists';
is $destination->slurp, 'works!', 'right content';
$subdir = $dir->child('test')->make_path;
my $destination2 = $destination->move_to($subdir);
is $destination2, $subdir->child($destination->basename), 'same path';
ok !-f $destination, 'file no longer exists';
ok -f $destination2, 'file exists';
is $destination2->slurp, 'works!', 'right content';

# Copy to
$dir         = tempdir;
$destination = $dir->child('dest.txt');
$source      = $dir->child('src.txt')->spurt('works!');
ok -f $source,       'file exists';
ok !-f $destination, 'file does not exists';
is $source->copy_to($destination)->to_string, $destination, 'same path';
ok -f $source,      'file still exists';
ok -f $destination, 'file also exists now';
is $source->slurp,      'works!', 'right content';
is $destination->slurp, 'works!', 'right content';
$subdir       = $dir->child('test')->make_path;
$destination2 = $destination->copy_to($subdir);
is $destination2, $subdir->child($destination->basename), 'same path';
ok -f $destination,  'file still exists';
ok -f $destination2, 'file also exists now';
is $destination->slurp,  'works!', 'right content';
is $destination2->slurp, 'works!', 'right content';

# Change permissions
$dir = tempdir;
eval { $dir->child('does_not_exist')->chmod(644) };
like $@, qr/^Can't chmod file/, 'right error';

# Stat
$dir = tempdir;
is $dir->child('test.txt')->spurt('1234')->stat->size, 4, 'right size';

# Lstat
$dir = tempdir;
my $orig = $dir->child('test.txt')->spurt('');
my $link = $orig->sibling('test.link');
SKIP: {
  skip 'symlinks unimplemented', 2 unless eval { symlink $orig, $link };
  is $link->stat->size,    0, 'target file is empty';
  isnt $link->lstat->size, 0, 'link is not empty';
}

# List
is_deeply path('does_not_exist')->list->to_array, [], 'no files';
is_deeply path(__FILE__)->list->to_array,         [], 'no files';
my $lib   = path(__FILE__)->sibling('lib', 'Mojo');
my @files = map { path($lib)->child(split '/') } (
  'DeprecationTest.pm',  'LoaderException.pm',
  'LoaderException2.pm', 'TestConnectProxy.pm'
);
is_deeply path($lib)->list->map('to_string')->to_array, \@files, 'right files';
unshift @files, $lib->child('.hidden.txt')->to_string;
is_deeply path($lib)->list({hidden => 1})->map('to_string')->to_array, \@files,
  'right files';
@files = map { path($lib)->child(split '/') } (
  'BaseTest',           'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest',         'Server',
  'TestConnectProxy.pm'
);
is_deeply path($lib)->list({dir => 1})->map('to_string')->to_array, \@files,
  'right files';
my @hidden = map { path($lib)->child(split '/') } '.hidden.txt', '.test';
is_deeply path($lib)->list({dir => 1, hidden => 1})->map('to_string')->to_array,
  [@hidden, @files], 'right files';

# List tree
is_deeply path('does_not_exist')->list_tree->to_array, [], 'no files';
is_deeply path(__FILE__)->list_tree->to_array,         [], 'no files';
@files = map { path($lib)->child(split '/') } (
  'BaseTest/Base1.pm',  'BaseTest/Base2.pm',
  'BaseTest/Base3.pm',  'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest/A.pm',    'LoaderTest/B.pm',
  'LoaderTest/C.pm',    'Server/Morbo/Backend/TestBackend.pm',
  'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree->map('to_string')->to_array, \@files,
  'right files';
@hidden = map { path($lib)->child(split '/') } '.hidden.txt',
  '.test/hidden.txt';
is_deeply path($lib)->list_tree({hidden => 1})->map('to_string')->to_array,
  [@hidden, @files], 'right files';
my @all = map { path($lib)->child(split '/') } (
  '.hidden.txt',          '.test',
  '.test/hidden.txt',     'BaseTest',
  'BaseTest/Base1.pm',    'BaseTest/Base2.pm',
  'BaseTest/Base3.pm',    'DeprecationTest.pm',
  'LoaderException.pm',   'LoaderException2.pm',
  'LoaderTest',           'LoaderTest/A.pm',
  'LoaderTest/B.pm',      'LoaderTest/C.pm',
  'Server',               'Server/Morbo',
  'Server/Morbo/Backend', 'Server/Morbo/Backend/TestBackend.pm',
  'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree({dir => 1, hidden => 1})->map('to_string')
  ->to_array, [@all], 'right files';
my @one = map { path($lib)->child(split '/') } (
  'DeprecationTest.pm',  'LoaderException.pm',
  'LoaderException2.pm', 'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree({max_depth => 1})->map('to_string')->to_array,
  [@one], 'right files';
my @one_dir = map { path($lib)->child(split '/') } (
  'BaseTest',           'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest',         'Server',
  'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree({dir => 1, max_depth => 1})->map('to_string')
  ->to_array, [@one_dir], 'right files';
my @two = map { path($lib)->child(split '/') } (
  'BaseTest/Base1.pm',  'BaseTest/Base2.pm',
  'BaseTest/Base3.pm',  'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest/A.pm',    'LoaderTest/B.pm',
  'LoaderTest/C.pm',    'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree({max_depth => 2})->map('to_string')->to_array,
  [@two], 'right files';
my @three = map { path($lib)->child(split '/') } (
  '.hidden.txt',          '.test',
  '.test/hidden.txt',     'BaseTest',
  'BaseTest/Base1.pm',    'BaseTest/Base2.pm',
  'BaseTest/Base3.pm',    'DeprecationTest.pm',
  'LoaderException.pm',   'LoaderException2.pm',
  'LoaderTest',           'LoaderTest/A.pm',
  'LoaderTest/B.pm',      'LoaderTest/C.pm',
  'Server',               'Server/Morbo',
  'Server/Morbo/Backend', 'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree({dir => 1, hidden => 1, max_depth => 3})
  ->map('to_string')->to_array, [@three], 'right files';

# Touch
$dir  = tempdir;
$file = $dir->child('test.txt');
ok !-e $file, 'file does not exist';
ok -e $file->touch, 'file exists';
is $file->spurt('test!')->slurp, 'test!', 'right content';
is $file->touch->slurp, 'test!', 'right content';
my $future = time + 1000;
utime $future, $future, $file->to_string;
is $file->stat->mtime, $future, 'right mtime';
isnt $file->touch->stat->mtime, $future, 'different mtime';

# I/O
$dir  = tempdir;
$file = $dir->child('test.txt')->spurt('just works!');
is $file->slurp, 'just works!', 'right content';
is $file->spurt('w', 'orks', ' too!')->slurp, 'works too!', 'right content';
{
  no warnings 'redefine';
  local *IO::Handle::syswrite = sub { $! = 0; 5 };
  eval { $file->spurt("just\nworks!") };
  like $@, qr/Can't write to file ".*/, 'right error';
}

done_testing();
