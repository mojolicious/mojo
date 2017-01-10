use Mojo::Base -strict;

use Test::More;
use Cwd 'getcwd';
use File::Basename qw(basename dirname);
use File::Spec::Functions qw(abs2rel canonpath catfile rel2abs splitdir);
use File::Temp;
use Mojo::File qw(path tempdir);

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

# Make path
$dir = tempdir;
my $subdir = $dir->child('foo', 'bar');
ok !-d $subdir, 'directory does not exist anymore';
$subdir->make_path;
ok -d $subdir, 'directory exists';

# Move to
$dir = tempdir;
my $destination = $dir->child('dest.txt');
my $source      = $dir->child('src.txt')->spurt('works!');
ok -f $source,       'file exists';
ok !-f $destination, 'file does not exists';
ok !-f $source->move_to($destination), 'file no longer exists';
ok -f $destination, 'file exists';
is $destination->slurp, 'works!', 'right content';

# List
is_deeply path('does_not_exist')->list->to_array, [], 'no files';
is_deeply path(__FILE__)->list->to_array,         [], 'no files';
my $lib = path(__FILE__)->dirname->child('lib', 'Mojo');
my @files = map { path($lib)->child(split '/') }
  ('DeprecationTest.pm', 'LoaderException.pm', 'LoaderException2.pm');
is_deeply path($lib)->list->map('to_string')->to_array, \@files, 'right files';
unshift @files, $lib->child('.hidden.txt')->to_string;
is_deeply path($lib)->list({hidden => 1})->map('to_string')->to_array, \@files,
  'right files';
@files = map { path($lib)->child(split '/') } (
  'BaseTest',           'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest'
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
  'LoaderTest/C.pm'
);
is_deeply path($lib)->list_tree->map('to_string')->to_array, \@files,
  'right files';
@hidden = map { path($lib)->child(split '/') } '.hidden.txt',
  '.test/hidden.txt';
is_deeply path($lib)->list_tree({hidden => 1})->map('to_string')->to_array,
  [@hidden, @files], 'right files';

# I/O
$dir = tempdir;
my $file = $dir->child('test.txt')->spurt('just works!');
is $file->slurp, 'just works!', 'right content';
{
  no warnings 'redefine';
  local *IO::Handle::syswrite = sub { $! = 0; 5 };
  eval { $file->spurt("just\nworks!") };
  like $@, qr/Can't write to file ".*/, 'right error';
}

done_testing();
