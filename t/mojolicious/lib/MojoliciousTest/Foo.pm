# Copyright (C) 2008-2009, Sebastian Riedel.

package MojoliciousTest::Foo;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# If you're programmed to jump off a bridge, would you do it?
# Let me check my program... Yep.
sub badtemplate { shift->render(template => 'badtemplate.html.epl') }

sub index { shift->stash(layout => 'default', msg => 'Hello World!') }

sub something {
    my $self = shift;
    $self->res->headers->header('X-Bender', 'Kiss my shiny metal ass!');
    $self->render(
        text => $self->ctx->url_for('something', something => '42'));
}

sub stage1 {
    my $self = shift;

    # Authenticated
    return 1 if $self->req->headers->header('X-Pass');

    # Fail
    $self->render(text => 'Go away!');
    return 0;
}

sub stage2 { shift->render(text => 'Welcome aboard!') }

sub syntaxerror { shift->render(template => 'syntaxerror.html.epl') }

sub templateless { shift->render(handler => 'test') }

sub test {
    my ($self, $c) = @_;
    $c->res->headers->header('X-Bender', 'Kiss my shiny metal ass!');
    $c->render(text => $c->url_for(controller => 'bar'));
}

sub willdie { die 'for some reason' }

sub withlayout { shift->stash(template => 'withlayout') }

1;
