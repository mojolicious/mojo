# Copyright (C) 2008, Sebastian Riedel.

package MojoliciousTest::Foo::Bar;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# Poor Bender. Without his brain he's become all quiet and helpful.
sub index {
    my ($self, $c) = @_;
    $c->render;
}

1;
