use Mojo::Base -strict;

use Test::More;
use Cwd 'getcwd';
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

# Basename
is path('file.t')->to_abs->basename, basename(rel2abs 'file.t'), 'same path';
is path('file.t')->to_abs->basename('.t'), basename(rel2abs('file.t'), '.t'),
  'same path';

# Dirname
is path('file.t')->to_abs->dirname, dirname(rel2abs 'file.t'), 'same path';

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

# Make path
$dir = tempdir;
my $subdir = $dir->child('foo', 'bar');
ok !-d $subdir, 'directory does not exist anymore';
$subdir->make_path;
ok -d $subdir, 'directory exists';
my $nextdir = $dir->child('foo', 'foobar')->make_path({error => \my $error});
ok -d $nextdir, 'directory exists';
ok $error, 'directory already existed';

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
ok !-f $source->move_to($destination), 'file no longer exists';
ok -f $destination, 'file exists';
is $destination->slurp, 'works!', 'right content';

# Copy to
$dir         = tempdir;
$destination = $dir->child('dest.txt');
$source      = $dir->child('src.txt')->spurt('works!');
ok -f $source,       'file exists';
ok !-f $destination, 'file does not exists';
ok -f $source->copy_to($destination), 'file still exists';
ok -f $destination, 'file also exists now';
is $source->slurp,      'works!', 'right content';
is $destination->slurp, 'works!', 'right content';

# List
is_deeply path('does_not_exist')->list->to_array, [], 'no files';
is_deeply path(__FILE__)->list->to_array,         [], 'no files';
my $lib = path(__FILE__)->dirname->child('lib', 'Mojo');
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
  'LoaderTest',         'TestConnectProxy.pm'
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
  'LoaderTest/C.pm',    'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree->map('to_string')->to_array, \@files,
  'right files';
@hidden = map { path($lib)->child(split '/') } '.hidden.txt',
  '.test/hidden.txt';
is_deeply path($lib)->list_tree({hidden => 1})->map('to_string')->to_array,
  [@hidden, @files], 'right files';
my @all = map { path($lib)->child(split '/') } (
  '.hidden.txt',        '.test',
  '.test/hidden.txt',   'BaseTest',
  'BaseTest/Base1.pm',  'BaseTest/Base2.pm',
  'BaseTest/Base3.pm',  'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest',         'LoaderTest/A.pm',
  'LoaderTest/B.pm',    'LoaderTest/C.pm',
  'TestConnectProxy.pm'
);
is_deeply path($lib)->list_tree({dir => 1, hidden => 1})->map('to_string')
  ->to_array, [@all], 'right files';

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
