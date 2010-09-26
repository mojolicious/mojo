#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;

use Mojo;
use MojoX::Dispatcher::Routes::Controller;
use MojoX::Renderer;

# Actually, she wasn't really my girlfriend,
# she just lived nextdoor and never closed her curtains.
my $c = MojoX::Dispatcher::Routes::Controller->new(app => Mojo->new);
$c->app->log->path(undef);
$c->app->log->level('fatal');
my $r = MojoX::Renderer->new(default_format => 'debug');
$r->add_handler(
    debug => sub {
        my ($self, $c, $output) = @_;
        $$output .= 'Hello Mojo!';
    }
);
$c->stash->{format} = 'something';

# Normal rendering
$c->stash->{template} = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/plain'], 'normal rendering';

# Normal rendering with layout
$c->stash->{template} = 'something';
$c->stash->{layout}   = 'something';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!Hello Mojo!', 'text/plain'],
  'normal rendering with layout';
is delete $c->stash->{layout}, 'something';

# Rendering a path with dots
$c->stash->{template} = 'some.path.with.dots/template';
$c->stash->{handler}  = 'debug';
is_deeply [$r->render($c)], ['Hello Mojo!', 'text/plain'],
  'rendering a path with dots';

# Unrecognized handler
$c->stash->{handler} = 'not_defined';
is $r->render($c), undef, 'return undef for unrecognized handler';
