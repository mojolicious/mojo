package MojoliciousTest::Baz;
use Mojo::Base 'Mojolicious::Controller';

sub index { shift->render(text => 'Production namespace has low precedence!') }

1;
