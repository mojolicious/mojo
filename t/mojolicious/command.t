use Mojo::Base -strict;

# Disable libev
BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More tests => 5;

# "Robot 1-X, save my friends! And Zoidberg!"
use Cwd 'cwd';
use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use Mojolicious::Command;

# Application
my $command = Mojolicious::Command->new;
isa_ok $command->app, 'Mojo', 'right application';

# Generating files
my $cwd = cwd;
my $dir = tempdir CLEANUP => 1;
chdir $dir;
$command->create_rel_dir('foo/bar');
ok -d catdir($dir, qw(foo bar)), 'directory exists';
my $template = "@@ foo_bar\njust <%= 'works' %>!\n";
open my $data, '<', \$template;
no strict 'refs';
*{"Mojolicious::Command::DATA"} = $data;
$command->render_to_rel_file('foo_bar', 'bar/baz.txt');
open my $txt, '<', $command->rel_file('bar/baz.txt');
is join('', <$txt>), "just works!\n", 'right result';
$command->chmod_rel_file('bar/baz.txt', 0700);
ok -e $command->rel_file('bar/baz.txt'), 'file is executable';
$command->write_rel_file('123.xml', "seems\nto\nwork");
open my $xml, '<', $command->rel_file('123.xml');
is join('', <$xml>), "seems\nto\nwork", 'right result';
chdir $cwd;
