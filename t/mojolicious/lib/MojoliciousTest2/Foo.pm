# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoliciousTest2::Foo;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# I can't afford to keep running people over.
# I'm not famous enough to get away with it.
sub test {
    my $self = shift;
    $self->res->code(200);
    $self->res->headers->header('X-Bender', 'Kiss my shiny metal ass!');
    $self->res->body($self->ctx->url_for);
}

1;
