use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Cwd qw(getcwd realpath);
use File::Spec::Functions qw(canonpath catdir catfile splitdir);
use FindBin;
use List::Util 'first';
use Mojo::HelloWorld;
use Mojo::Home;

# ENV detection
my $target = canonpath realpath getcwd;
{
  local $ENV{MOJO_HOME} = '.';
  my $home = Mojo::Home->new->detect;
  is_deeply [splitdir canonpath($home->to_string)], [splitdir $target],
    'right path detected';
}

# Current working directory
my $original = catdir splitdir getcwd;
my $home     = Mojo::Home->new->detect;
is_deeply [splitdir realpath getcwd], [splitdir $home], 'right path detected';

# Specific class detection
$INC{'MyClass.pm'} = 'MyClass.pm';
$home = Mojo::Home->new->detect('MyClass');
is_deeply [splitdir canonpath($home->to_string)], [splitdir $target],
  'right path detected';

# Path generation
$home = Mojo::Home->new($FindBin::Bin);
is $home->lib_dir, catdir(splitdir($FindBin::Bin), 'lib'), 'right path';
is $home->rel_file('foo.txt'), catfile(splitdir($FindBin::Bin), 'foo.txt'),
  'right path';
is $home->rel_file('foo/bar.txt'),
  catfile(splitdir($FindBin::Bin), 'foo', 'bar.txt'), 'right path';
is $home->rel_dir('foo'), catdir(splitdir($FindBin::Bin), 'foo'), 'right path';
is $home->rel_dir('foo/bar'), catdir(splitdir($FindBin::Bin), 'foo', 'bar'),
  'right path';

# List files
is_deeply $home->list_files('lib/does_not_exist'), [], 'no files';
is_deeply $home->list_files('lib/myapp.pl'),       [], 'no files';
my @files = (
  'BaseTest/Base1.pm',  'BaseTest/Base2.pm',
  'BaseTest/Base3.pm',  'DeprecationTest.pm',
  'LoaderException.pm', 'LoaderException2.pm',
  'LoaderTest/A.pm',    'LoaderTest/B.pm',
  'LoaderTest/C.pm'
);
is_deeply $home->list_files('lib/Mojo'), \@files, 'right files';
my @hidden = ('.hidden.txt', '.test/hidden.txt');
is_deeply $home->list_files('lib/Mojo', {hidden => 1}), [@hidden, @files],
  'right files';

done_testing();
