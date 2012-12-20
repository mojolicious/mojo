package LiteTestKeyword;
use Mojo::Base -base;

use Mojo::Util 'monkey_patch';

sub import {
  my $caller = caller;
  monkey_patch $caller, 'test_keyword', sub { $caller->app->routes->get(@_) };
}

1;
