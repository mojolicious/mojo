use Mojo::Base -strict;

# Disable libev
BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More tests => 28;

# "My cat's breath smells like cat food."
use Cwd 'cwd';
use File::Spec::Functions 'catdir';
use File::Temp;
use Mojo::Command;

# Application
my $command = Mojo::Command->new;
isa_ok $command->app, 'Mojo', 'right application';

# UNIX DATA templates
my $unix = "@@ template1\nFirst Template\n@@ template2\r\nSecond Template\n";
open my $data, '<', \$unix;
no strict 'refs';
*{"Example::Package::UNIX::DATA"} = $data;
is $command->get_data('template1', 'Example::Package::UNIX'),
  "First Template\n", 'right template';
is $command->get_data('template2', 'Example::Package::UNIX'),
  "Second Template\n", 'right template';
is_deeply [sort keys %{$command->get_all_data('Example::Package::UNIX')}],
  [qw(template1 template2)], 'right DATA files';
close $data;

# Windows DATA templates
my $windows
  = "@@ template3\r\nThird Template\r\n@@ template4\r\nFourth Template\r\n";
open $data, '<', \$windows;
no strict 'refs';
*{"Example::Package::Windows::DATA"} = $data;
is $command->get_data('template3', 'Example::Package::Windows'),
  "Third Template\r\n", 'right template';
is $command->get_data('template4', 'Example::Package::Windows'),
  "Fourth Template\r\n", 'right template';
is_deeply [sort keys %{$command->get_all_data('Example::Package::Windows')}],
  [qw(template3 template4)], 'right DATA files';
close $data;

# Mixed whitespace
my $mixed = "@\@template5\n5\n\n@@  template6\n6\n@@     template7\n7";
open $data, '<', \$mixed;
no strict 'refs';
*{"Example::Package::Mixed::DATA"} = $data;
is $command->get_data('template5', 'Example::Package::Mixed'), "5\n\n",
  'right template';
is $command->get_data('template6', 'Example::Package::Mixed'), "6\n",
  'right template';
is $command->get_data('template7', 'Example::Package::Mixed'), '7',
  'right template';
is_deeply [sort keys %{$command->get_all_data('Example::Package::Mixed')}],
  [qw(template5 template6 template7)], 'right DATA files';
close $data;

# Class to file
is $command->class_to_file('Foo::Bar'), 'foo_bar', 'right file';
is $command->class_to_file('FooBar'),   'foo_bar', 'right file';
is $command->class_to_file('FOOBar'),   'foobar',  'right file';
is $command->class_to_file('FOOBAR'),   'foobar',  'right file';
is $command->class_to_file('FOO::Bar'), 'foobar',  'right file';
is $command->class_to_file('FooBAR'),   'foo_bar', 'right file';
is $command->class_to_file('Foo::BAR'), 'foo_bar', 'right file';

# Class to path
is $command->class_to_path('Foo::Bar'),      'Foo/Bar.pm',     'right path';
is $command->class_to_path("Foo'Bar"),       'Foo/Bar.pm',     'right path';
is $command->class_to_path("Foo'Bar::Baz"),  'Foo/Bar/Baz.pm', 'right path';
is $command->class_to_path("Foo::Bar'Baz"),  'Foo/Bar/Baz.pm', 'right path';
is $command->class_to_path("Foo::Bar::Baz"), 'Foo/Bar/Baz.pm', 'right path';
is $command->class_to_path("Foo'Bar'Baz"),   'Foo/Bar/Baz.pm', 'right path';

# Generating files
my $cwd = cwd;
my $dir = File::Temp::tempdir(CLEANUP => 1);
chdir $dir;
$command->create_rel_dir('foo/bar');
ok -d catdir($dir, qw(foo bar)), 'directory exists';
my $template = "@@ foo_bar\njust <%= 'works' %>!\n";
open $data, '<', \$template;
no strict 'refs';
*{"Mojo::Command::DATA"} = $data;
$command->render_to_rel_file('foo_bar', 'bar/baz.txt');
open my $txt, '<', $command->rel_file('bar/baz.txt');
is join('', <$txt>), "just works!\n", 'right result';
$command->chmod_rel_file('bar/baz.txt', 0700);
ok -e $command->rel_file('bar/baz.txt'), 'file is executable';
$command->write_rel_file('123.xml', "seems\nto\nwork");
open my $xml, '<', $command->rel_file('123.xml');
is join('', <$xml>), "seems\nto\nwork", 'right result';
chdir $cwd;
