use Mojo::Base -strict;

# Disable libev
BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More tests => 15;

# "Uh, no, you got the wrong number. This is 9-1... 2"
use Cwd qw(cwd realpath);
use File::Spec::Functions qw(canonpath catdir splitdir);
use FindBin;
use List::Util 'first';
use Mojo::HelloWorld;
use Mojo::Home;

# ENV detection
{
  local $ENV{MOJO_HOME} = '.';
  my $home = Mojo::Home->new->detect;
  is_deeply [split /\\|\//, canonpath($home->to_string)],
    [split /\\|\//, canonpath(realpath cwd())], 'right path detected';
}

# Class detection
my $original = catdir(splitdir($FindBin::Bin), '..', '..');
my $home     = Mojo::Home->new->detect;
my $target   = realpath $original;
is_deeply [split /\\|\//, $target], [split /\\|\//, $home],
  'right path detected';

# Specific class detection
$INC{'MyClass.pm'} = 'MyClass.pm';
$home = Mojo::Home->new->detect('MyClass');
is_deeply [split /\\|\//, canonpath($home->to_string)],
  [split /\\|\//, canonpath(realpath cwd())], 'right path detected';

# FindBin detection
$home = Mojo::Home->new->detect(undef);
is_deeply [split /\\|\//, catdir(splitdir($FindBin::Bin))],
  [split /\\|\//, $home], 'right path detected';

# Path generation
$home = Mojo::Home->new($FindBin::Bin);
is $home->lib_dir, catdir(splitdir($FindBin::Bin), 'lib'), 'right path';
is $home->rel_file('foo.txt'), catdir(splitdir($FindBin::Bin), 'foo.txt'),
  'right path';
is $home->rel_file('foo/bar.txt'),
  catdir(splitdir($FindBin::Bin), 'foo', 'bar.txt'), 'right path';
is $home->rel_dir('foo'), catdir(splitdir($FindBin::Bin), 'foo'), 'right path';
is $home->rel_dir('foo/bar'), catdir(splitdir($FindBin::Bin), 'foo', 'bar'),
  'right path';

# List files
is first(sub {/Base1\.pm$/}, @{$home->list_files('lib')}),
  'Mojo/BaseTest/Base1.pm', 'right result';
is first(sub {/Base2\.pm$/}, @{$home->list_files('lib')}),
  'Mojo/BaseTest/Base2.pm', 'right result';
is first(sub {/Base3\.pm$/}, @{$home->list_files('lib')}),
  'Mojo/BaseTest/Base3.pm', 'right result';

# Slurp files
like $home->slurp_rel_file('lib/Mojo/BaseTest/Base1.pm'), qr/Base1/,
  'right content';
like $home->slurp_rel_file('lib/Mojo/BaseTest/Base2.pm'), qr/Base2/,
  'right content';
like $home->slurp_rel_file('lib/Mojo/BaseTest/Base3.pm'), qr/Base3/,
  'right content';
