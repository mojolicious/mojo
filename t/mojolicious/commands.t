use Mojo::Base -strict;

use Test::More tests => 7;

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
  local $ENV{MOJO_APP}        = 'MojoliciousTest';
  is ref Mojolicious::Commands->start, 'MojoliciousTest', 'right class';
}
{
  local $ENV{MOJO_APP_LOADER} = 1;
  is ref Mojolicious::Commands->start_app('MojoliciousTest'),
    'MojoliciousTest', 'right class';
}

# Start application with command
is ref Mojolicious::Commands->start_app(MojoliciousTest => 'psgi'),
  'CODE', 'right reference';
