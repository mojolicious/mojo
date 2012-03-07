use Mojo::Base -strict;

# "Would you kindly shut your noise-hole?"
use Test::More tests => 4;

package Mojo::TestServerViaEnv;
use Mojo::Base 'Mojo';

package Mojo::TestServerViaApp;
use Mojo::Base 'Mojo';

package main;

use Mojo::Server;

my $server = Mojo::Server->new;
isa_ok $server, 'Mojo::Server', 'right object';

# Test an explicit class name
my $app = $server->new(app_class => 'Mojo::TestServerViaApp')->app;
isa_ok $app, 'Mojo::TestServerViaApp', 'right object';

# Test setting the class name through the environment
{
  local $ENV{MOJO_APP} = 'Mojo::TestServerViaEnv';
  $app = $server->new->app;
  isa_ok $app, 'Mojo::TestServerViaEnv', 'right object';
}

# Test the default
$app = $server->new->app;
isa_ok $app, 'Mojolicious::Lite', 'right default app';
