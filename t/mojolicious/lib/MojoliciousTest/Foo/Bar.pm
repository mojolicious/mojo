package MojoliciousTest::Foo::Bar;
use Mojolicious::Controller -base;

sub index {1}

sub test { shift->render(text => 'Class works!') }

1;
