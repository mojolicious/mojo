use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Cwd 'getcwd';
use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use Mojolicious::Command;

# Application
my $command = Mojolicious::Command->new;
isa_ok $command->app, 'Mojo',        'right application';
isa_ok $command->app, 'Mojolicious', 'right application';

# Creating directories
my $cwd = getcwd;
my $dir = tempdir CLEANUP => 1;
chdir $dir;
my $buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->create_rel_dir('foo/bar');
}
like $buffer, qr/[mkdir]/, 'right output';
ok -d catdir(qw(foo bar)), 'directory exists';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->create_rel_dir('foo/bar');
}
like $buffer, qr/\[exist\]/, 'right output';
chdir $cwd;

# Generating files
my $template = "@@ foo_bar\njust <%= 'works' %>!\n";
open my $data, '<', \$template;
no strict 'refs';
*{"Mojolicious::Command::DATA"} = $data;
chdir $dir;
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->render_to_rel_file('foo_bar', 'bar/baz.txt');
}
like $buffer, qr/\[mkdir\].*\[write\]/s, 'right output';
open my $txt, '<', $command->rel_file('bar/baz.txt');
is join('', <$txt>), "just works!\n", 'right result';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->chmod_rel_file('bar/baz.txt', 0700);
}
like $buffer, qr/\[chmod\]/, 'right output';
ok -e $command->rel_file('bar/baz.txt'), 'file is executable';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->write_rel_file('123.xml', "seems\nto\nwork");
}
like $buffer, qr/\[exist\].*\[write\]/s, 'right output';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->write_rel_file('123.xml', 'fail');
}
like $buffer, qr/\[exist\]/, 'right output';
open my $xml, '<', $command->rel_file('123.xml');
is join('', <$xml>), "seems\nto\nwork", 'right result';
chdir $cwd;

# Quiet
chdir $dir;
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $command->quiet(1)->write_rel_file('123.xml', 'fail');
}
is $buffer, '', 'no output';
chdir $cwd;

# Abstract methods
eval { Mojolicious::Command->run };
like $@, qr/Method "run" not implemented by subclass/, 'right error';

done_testing();
