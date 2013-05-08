use Mojo::Base -strict;

BEGIN {
  $ENV{PLACK_ENV}    = undef;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojolicious::Commands;

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

# cgi
require Mojolicious::Command::cgi;
my $cgi = Mojolicious::Command::cgi->new;
ok $cgi->description, 'has a description';
ok $cgi->usage,       'has usage information';

# cpanify
require Mojolicious::Command::cpanify;
my $cpanify = Mojolicious::Command::cpanify->new;
ok $cpanify->description, 'has a description';
ok $cpanify->usage,       'has usage information';

# daemon
require Mojolicious::Command::daemon;
my $daemon = Mojolicious::Command::daemon->new;
ok $daemon->description, 'has a description';
ok $daemon->usage,       'has usage information';

# eval
require Mojolicious::Command::eval;
my $eval = Mojolicious::Command::eval->new;
ok $eval->description, 'has a description';
ok $eval->usage,       'has usage information';

# generate
require Mojolicious::Command::generate;
my $generator = Mojolicious::Command::generate->new;
ok $generator->description, 'has a description';
ok $generator->usage,       'has usage information';

# generate app
require Mojolicious::Command::generate::app;
$app = Mojolicious::Command::generate::app->new;
ok $app->description, 'has a description';
ok $app->usage,       'has usage information';

# generate lite_app
require Mojolicious::Command::generate::lite_app;
$app = Mojolicious::Command::generate::lite_app->new;
ok $app->description, 'has a description';
ok $app->usage,       'has usage information';

# generate makefile
require Mojolicious::Command::generate::makefile;
my $makefile = Mojolicious::Command::generate::makefile->new;
ok $makefile->description, 'has a description';
ok $makefile->usage,       'has usage information';

# generate plugin
require Mojolicious::Command::generate::plugin;
my $plugin = Mojolicious::Command::generate::plugin->new;
ok $plugin->description, 'has a description';
ok $plugin->usage,       'has usage information';

# get
require Mojolicious::Command::get;
my $get = Mojolicious::Command::get->new;
ok $get->description, 'has a description';
ok $get->usage,       'has usage information';

# inflate
require Mojolicious::Command::inflate;
my $inflate = Mojolicious::Command::inflate->new;
ok $inflate->description, 'has a description';
ok $inflate->usage,       'has usage information';

# prefork
require Mojolicious::Command::prefork;
my $prefork = Mojolicious::Command::prefork->new;
ok $prefork->description, 'has a description';
ok $prefork->usage,       'has usage information';

# psgi
require Mojolicious::Command::psgi;
my $psgi = Mojolicious::Command::psgi->new;
ok $psgi->description, 'has a description';
ok $psgi->usage,       'has usage information';

# routes
require Mojolicious::Command::routes;
my $routes = Mojolicious::Command::routes->new;
ok $routes->description, 'has a description';
ok $routes->usage,       'has usage information';

# test
require Mojolicious::Command::test;
my $test = Mojolicious::Command::test->new;
ok $test->description, 'has a description';
ok $test->usage,       'has usage information';

# version
require Mojolicious::Command::version;
my $version = Mojolicious::Command::version->new;
ok $version->description, 'has a description';
ok $version->usage,       'has usage information';

done_testing();
