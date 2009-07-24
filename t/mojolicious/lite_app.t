#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 8;

# Wait you're the only friend I have...
# You really want a robot for a friend?
# Yeah ever since I was six.
# Well, ok but I don't want people thinking we're robosexuals,
# so if anyone asks you're my debugger.
use Mojo::Client;
use Mojo::Transaction;
use Mojolicious::Lite;

# Silence
app->log->level('error');

# /foo
get '/foo' => sub {
    my $self = shift;
    $self->res->code(200);
    $self->res->body('Yea baby!');
};

# /template
get '/template' => 'index';

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $client = Mojo::Client->new;

# /foo
my $tx = Mojo::Transaction->new_get('/foo');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            'Yea baby!');

# /template
$tx = Mojo::Transaction->new_get('/template');
$client->process_app('Mojolicious::Lite', $tx);
is($tx->res->code,                            200);
is($tx->res->headers->server,                 'Mojo (Perl)');
is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
is($tx->res->body,                            "works!\n");

__DATA__
__index.html.eplite__
works!
