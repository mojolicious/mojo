package MojoliciousTest::SideEffects::Test;
use Mojo::Base 'Mojolicious::Controller';

sub index { shift->render(text => 'pass') }

1;
