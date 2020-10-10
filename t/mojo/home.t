use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::File qw(curfile path);
use Mojo::HelloWorld;
use Mojo::Home;

subtest 'ENV detection' => sub {
  my $fake = path->to_abs->child('does_not_exist');
  local $ENV{MOJO_HOME} = $fake->to_string;
  my $home = Mojo::Home->new->detect;
  is_deeply $home->to_array, $fake->to_array, 'right path detected';
};

subtest 'Specific class detection' => sub {
  my $fake = path->to_abs->child('does_not_exist_2');
  local $INC{'My/Class.pm'} = $fake->child('My', 'Class.pm')->to_string;
  my $home = Mojo::Home->new->detect('My::Class');
  is_deeply $home->to_array, $fake->to_array, 'right path detected';
};

subtest 'Specific class detection (with "lib")' => sub {
  my $fake = path->to_abs->child('does_not_exist_3');
  local $INC{'My/Class.pm'} = $fake->child('lib', 'My', 'Class.pm')->to_string;
  my $home = Mojo::Home->new->detect('My::Class');
  is_deeply $home->to_array, $fake->to_array, 'right path detected';
};

subtest 'Specific class detection (with "blib/lib")' => sub {
  my $fake = path->to_abs->child('does_not_exist_3');
  local $INC{'My/Class.pm'} = $fake->child('blib', 'lib', 'My', 'Class.pm')->to_string;
  my $home = Mojo::Home->new->detect('My::Class');
  is_deeply $home->to_array, $fake->to_array, 'right path detected';
};

subtest 'Specific class detection (relative)' => sub {
  local $INC{'My/Class.pm'} = path('My', 'Class.pm')->to_string;
  my $home = Mojo::Home->new->detect('My::Class');
  is_deeply $home->to_array, path->to_array, 'right path detected';
};

subtest 'Specific class detection (relative "blib/lib")' => sub {
  local $INC{'My/Class.pm'} = path('blib', 'lib', 'My', 'Class.pm')->to_string;
  my $home = Mojo::Home->new->detect('My::Class');
  is_deeply $home->to_array, path->to_array, 'right path detected';
};

subtest 'Current working directory' => sub {
  my $home = Mojo::Home->new->detect;
  is_deeply $home->to_array, path->to_abs->to_array, 'right path detected';
};

subtest 'Path generation' => sub {
  my $home = Mojo::Home->new(curfile->dirname);
  my $path = curfile->dirname;
  is $home->rel_file('foo.txt'), $path->child('foo.txt'), 'right path';
  is $home->rel_file('foo/bar.txt'), $path->child('foo', 'bar.txt'), 'right path';
  is $home->rel_file('foo/bar.txt')->basename, 'bar.txt', 'right result';
};

done_testing();
