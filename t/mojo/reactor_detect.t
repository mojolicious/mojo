use Mojo::Base -strict;

use Test::More;
use Mojo::Reactor::Poll;

# Dummy reactor
package Mojo::Reactor::Test;
use Mojo::Base 'Mojo::Reactor::Poll';

package main;

# Detection (env)
{
  local $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Test';
  is(Mojo::Reactor->detect, 'Mojo::Reactor::Test', 'right class');
}

# Event loop detection
require Mojo::IOLoop;
is ref Mojo::IOLoop->new->reactor, 'Mojo::Reactor::Test', 'right class';

done_testing();
