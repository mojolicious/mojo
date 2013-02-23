package Mojo::DeprecationTest;

use Mojo::Util 'deprecated';

sub foo {
  deprecated 'foo is DEPRECATED';
  return 'bar';
}

1;
