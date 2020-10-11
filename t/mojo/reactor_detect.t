use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::Reactor::Poll;

# Dummy reactor
package Mojo::Reactor::Test;
use Mojo::Base 'Mojo::Reactor::Poll';

package main;

subtest 'Detection (success)' => sub {
  local $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Test';
  is(Mojo::Reactor->detect, 'Mojo::Reactor::Test', 'right class');
};

subtest 'Detection (fail)' => sub {
  local $ENV{MOJO_REACTOR} = 'Mojo::Reactor::DoesNotExist';
  is(Mojo::Reactor->detect, 'Mojo::Reactor::Poll', 'right class');
};

subtest 'Event loop detection' => sub {
  local $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Test';
  require Mojo::IOLoop;
  is ref Mojo::IOLoop->new->reactor, 'Mojo::Reactor::Test', 'right class';
};

done_testing();
