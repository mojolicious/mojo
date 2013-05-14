package MojoliciousTest3::Baz;
use Mojo::Base 'MojoliciousTest::Baz';

sub index {
  shift->render(text => 'Development namespace has high precedence!');
}

1;
