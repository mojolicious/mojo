use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Cwd 'cwd';
use File::Spec::Functions 'catdir';
use File::Temp 'tempdir';
use Mojolicious::Command;

# Application
my $command = Mojolicious::Command->new(quiet => 1);
isa_ok $command->app, 'Mojo',        'right application';
isa_ok $command->app, 'Mojolicious', 'right application';

# Generating files
my $cwd = cwd;
my $dir = tempdir CLEANUP => 1;
chdir $dir;
$command->create_rel_dir('foo/bar');
ok -d catdir(qw(foo bar)), 'directory exists';
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

# Abstract methods
eval { Mojolicious::Command->run };
like $@, qr/Method "run" not implemented by subclass/, 'right error';

done_testing();
