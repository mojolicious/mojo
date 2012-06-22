use Mojo::Base -strict;

# "Would you kindly shut your noise-hole?"
use Test::More tests => 3;

package Mojo::TestServerViaEnv;
use Mojo::Base 'Mojo';

package Mojo::TestServerViaApp;
use Mojo::Base 'Mojo';

package main;

use Mojo::Server;

my $server = Mojo::Server->new;
isa_ok $server, 'Mojo::Server', 'right object';

# Test the default
{
  local $ENV{MOJO_APP};
  my $app = $server->new->app;
  isa_ok $app, 'Mojolicious::Lite', 'right default app';
}

# Test setting the class name through the environment
{
  local $ENV{MOJO_APP} = 'Mojo::TestServerViaEnv';
  my $app = $server->new->app;
  isa_ok $app, 'Mojo::TestServerViaEnv', 'right object';
}
