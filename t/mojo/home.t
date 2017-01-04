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

done_testing();
