use Mojo::Base -strict;

use Test::More tests => 10;

use FindBin;
use lib "$FindBin::Bin/lib";

# "I'm not a robot!
#  I don't like having discs crammed into me, unless they're Oreos.
#  And then, only in the mouth."
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
is ref Mojolicious::Commands->run('psgi'), 'CODE', 'right reference';

# Start application
{
  local $ENV{MOJO_APP_LOADER} = 1;
  local $ENV{MOJO_APP};
  is ref Mojolicious::Commands->start_app('MojoliciousTest'),
    'MojoliciousTest', 'right class';
}
{
  local $ENV{MOJO_APP_LOADER} = 1;
  local $ENV{MOJO_APP}        = 'MojoliciousTest';
  is ref Mojolicious::Commands->start, 'MojoliciousTest', 'right class';
}

# Start application with command
{
  local $ENV{MOJO_APP};
  is ref Mojolicious::Commands->start_app(MojoliciousTest => 'psgi'), 'CODE',
    'right reference';
}
{
  local $ENV{MOJO_APP} = 'MojoliciousTest';
  is ref Mojolicious::Commands->start('psgi'), 'CODE', 'right reference';
}

# Start application with application specific command
my $app;
{
  local $ENV{MOJO_APP_LOADER} = 1;
  $app = Mojolicious::Commands->start_app('MojoliciousTest');
}
is $app->start('test_command'), 'works!', 'right result';
{
  local $ENV{MOJO_APP};
  is(Mojolicious::Commands->start_app(MojoliciousTest => 'test_command'),
    'works!', 'right result');
}
