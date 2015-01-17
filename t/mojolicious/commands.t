use Mojo::Base -strict;

BEGIN {
  $ENV{PLACK_ENV}    = undef;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Cwd 'cwd';
use File::Temp 'tempdir';

# Make sure @ARGV is not changed
{
  local $ENV{MOJO_MODE};
  local @ARGV = qw(-m production -x whatever);
  require Mojolicious::Commands;
  is $ENV{MOJO_MODE}, 'production', 'right mode';
  is_deeply \@ARGV, [qw(-m production -x whatever)], 'unchanged';
}

# Environment detection
my $commands = Mojolicious::Commands->new;
{
  local $ENV{PLACK_ENV} = 'production';
  is $commands->detect, 'psgi', 'right environment';
}
{
  local $ENV{PATH_INFO} = '/test';
  is $commands->detect, 'cgi', 'right environment';
}
{
  local $ENV{GATEWAY_INTERFACE} = 'CGI/1.1';
  is $commands->detect, 'cgi', 'right environment';
}
{
  local @ENV{qw(PLACK_ENV PATH_INFO GATEWAY_INTERFACE)};
  is $commands->detect, undef, 'no environment';
}
{
  local $ENV{PLACK_ENV} = 'production';
  is ref Mojolicious::Commands->new->run, 'CODE', 'right reference';
  local $ENV{MOJO_NO_DETECT} = 1;
  isnt ref Mojolicious::Commands->new->run, 'CODE', 'not a CODE reference';
}

# Run command
is ref Mojolicious::Commands->new->run('psgi'), 'CODE', 'right reference';

# Start application
{
  local $ENV{MOJO_APP_LOADER} = 1;
  is ref Mojolicious::Commands->start_app('MojoliciousTest'),
    'MojoliciousTest', 'right class';
}

# Start application with command
{
  is ref Mojolicious::Commands->start_app(MojoliciousTest => 'psgi'), 'CODE',
    'right reference';
}

# Start application with application specific command
my $app;
{
  local $ENV{MOJO_APP_LOADER} = 1;
  $app = Mojolicious::Commands->start_app('MojoliciousTest');
}
is $app->start('test_command'), 'works!', 'right result';
{
  is(Mojolicious::Commands->start_app(MojoliciousTest => 'test_command'),
    'works!', 'right result');
}

# Do not pick up options for detected environments
{
  local $ENV{MOJO_MODE};
  local $ENV{PLACK_ENV} = 'testing';
  local @ARGV = qw(psgi -m production);
  is ref Mojolicious::Commands->start_app('MojoliciousTest'), 'CODE',
    'right reference';
  is $ENV{MOJO_MODE}, undef, 'no mode';
}

# mojo
ok $commands->description, 'has a description';
like $commands->message,   qr/COMMAND/, 'has a message';
like $commands->hint,      qr/help/, 'has a hint';
my $buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  local $ENV{HARNESS_ACTIVE} = 0;
  $commands->run;
}
like $buffer, qr/Usage: APPLICATION COMMAND \[OPTIONS\].*daemon.*version/s,
  'right output';

# help
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $commands->run('help', 'generate', 'lite_app');
}
like $buffer, qr/Usage: APPLICATION generate lite_app \[NAME\]/,
  'right output';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $commands->run('generate', 'app', '-h');
}
like $buffer, qr/Usage: APPLICATION generate app \[NAME\]/, 'right output';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $commands->run('generate', 'lite_app', '--help');
}
like $buffer, qr/Usage: APPLICATION generate lite_app \[NAME\]/,
  'right output';

# cgi
require Mojolicious::Command::cgi;
my $cgi = Mojolicious::Command::cgi->new;
ok $cgi->description, 'has a description';
like $cgi->usage, qr/cgi/, 'has usage information';

# cpanify
require Mojolicious::Command::cpanify;
my $cpanify = Mojolicious::Command::cpanify->new;
ok $cpanify->description, 'has a description';
like $cpanify->usage, qr/cpanify/, 'has usage information';

# daemon
require Mojolicious::Command::daemon;
my $daemon = Mojolicious::Command::daemon->new;
ok $daemon->description, 'has a description';
like $daemon->usage, qr/daemon/, 'has usage information';

# eval
require Mojolicious::Command::eval;
my $eval = Mojolicious::Command::eval->new;
ok $eval->description, 'has a description';
like $eval->usage, qr/eval/, 'has usage information';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $eval->run('-v', 'app->controller_class');
}
like $buffer, qr/Mojolicious::Controller/, 'right output';

# generate
require Mojolicious::Command::generate;
my $generator = Mojolicious::Command::generate->new;
ok $generator->description, 'has a description';
like $generator->message,   qr/generate/, 'has a message';
like $generator->hint,      qr/help/, 'has a hint';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  local $ENV{HARNESS_ACTIVE} = 0;
  $generator->run;
}
like $buffer,
  qr/Usage: APPLICATION generate GENERATOR \[OPTIONS\].*lite_app.*plugin/s,
  'right output';

# generate app
require Mojolicious::Command::generate::app;
$app = Mojolicious::Command::generate::app->new;
ok $app->description, 'has a description';
like $app->usage, qr/app/, 'has usage information';
my $cwd = cwd;
my $dir = tempdir CLEANUP => 1;
chdir $dir;
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $app->run;
}
like $buffer, qr/my_app/, 'right output';
ok -e $app->rel_file('my_app/script/my_app'), 'script exists';
ok -e $app->rel_file('my_app/lib/MyApp.pm'),  'application class exists';
ok -e $app->rel_file('my_app/lib/MyApp/Controller/Example.pm'),
  'controller exists';
ok -e $app->rel_file('my_app/t/basic.t'),         'test exists';
ok -e $app->rel_file('my_app/public/index.html'), 'static file exists';
ok -e $app->rel_file('my_app/templates/layouts/default.html.ep'),
  'layout exists';
ok -e $app->rel_file('my_app/templates/example/welcome.html.ep'),
  'template exists';
chdir $cwd;

# generate lite_app
require Mojolicious::Command::generate::lite_app;
$app = Mojolicious::Command::generate::lite_app->new;
ok $app->description, 'has a description';
like $app->usage, qr/lite_app/, 'has usage information';
$dir = tempdir CLEANUP => 1;
chdir $dir;
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $app->run;
}
like $buffer, qr/myapp\.pl/, 'right output';
ok -e $app->rel_file('myapp.pl'), 'app exists';
chdir $cwd;

# generate makefile
require Mojolicious::Command::generate::makefile;
my $makefile = Mojolicious::Command::generate::makefile->new;
ok $makefile->description, 'has a description';
like $makefile->usage, qr/makefile/, 'has usage information';
$dir = tempdir CLEANUP => 1;
chdir $dir;
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $makefile->run;
}
like $buffer, qr/Makefile\.PL/, 'right output';
ok -e $app->rel_file('Makefile.PL'), 'Makefile.PL exists';
chdir $cwd;

# generate plugin
require Mojolicious::Command::generate::plugin;
my $plugin = Mojolicious::Command::generate::plugin->new;
ok $plugin->description, 'has a description';
like $plugin->usage, qr/plugin/, 'has usage information';
$dir = tempdir CLEANUP => 1;
chdir $dir;
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $plugin->run;
}
like $buffer, qr/MyPlugin\.pm/, 'right output';
ok -e $app->rel_file(
  'Mojolicious-Plugin-MyPlugin/lib/Mojolicious/Plugin/MyPlugin.pm'),
  'class exists';
ok -e $app->rel_file('Mojolicious-Plugin-MyPlugin/t/basic.t'), 'test exists';
ok -e $app->rel_file('Mojolicious-Plugin-MyPlugin/Makefile.PL'),
  'Makefile.PL exists';
chdir $cwd;

# get
require Mojolicious::Command::get;
my $get = Mojolicious::Command::get->new;
ok $get->description, 'has a description';
like $get->usage, qr/get/, 'has usage information';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $get->run('/');
}
like $buffer, qr/Your Mojo is working!/, 'right output';
$get->app->hook(
  before_dispatch => sub {
    my $c = shift;
    return $c->render(text => '<p>works</p>')
      if $c->req->url->path->contains('/html');
    $c->render(json => {works => 'too'})
      if $c->req->url->path->contains('/json');
  }
);
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $get->run('/html', 'p', 'text');
}
like $buffer, qr/works/, 'right output';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $get->run('/json', '/works');
}
like $buffer, qr/too/, 'right output';

# inflate
require Mojolicious::Command::inflate;
my $inflate = Mojolicious::Command::inflate->new;
ok $inflate->description, 'has a description';
like $inflate->usage, qr/inflate/, 'has usage information';

# prefork
require Mojolicious::Command::prefork;
my $prefork = Mojolicious::Command::prefork->new;
ok $prefork->description, 'has a description';
like $prefork->usage, qr/prefork/, 'has usage information';

# psgi
require Mojolicious::Command::psgi;
my $psgi = Mojolicious::Command::psgi->new;
ok $psgi->description, 'has a description';
like $psgi->usage, qr/psgi/, 'has usage information';

# routes
require Mojolicious::Command::routes;
my $routes = Mojolicious::Command::routes->new;
ok $routes->description, 'has a description';
like $routes->usage, qr/routes/, 'has usage information';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $routes->run;
}
like $buffer,   qr!/\*whatever!, 'right output';
unlike $buffer, qr!/\(\.\+\)\?!, 'not verbose';
$buffer = '';
{
  open my $handle, '>', \$buffer;
  local *STDOUT = $handle;
  $routes->run('-v');
}
like $buffer, qr!/\*whatever!, 'right output';
like $buffer, qr!/\(\.\+\)\?!, 'verbose';

# test
require Mojolicious::Command::test;
my $test = Mojolicious::Command::test->new;
ok $test->description, 'has a description';
like $test->usage, qr/test/, 'has usage information';

# version
require Mojolicious::Command::version;
my $version = Mojolicious::Command::version->new;
ok $version->description, 'has a description';
like $version->usage, qr/version/, 'has usage information';

done_testing();
