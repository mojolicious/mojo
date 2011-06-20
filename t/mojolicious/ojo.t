#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable IPv6, epoll and kqueue
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1;
  $ENV{MOJO_MODE} = 'development';
}

use Test::More tests => 9;

# "What do you mean 'we', flesh-tube?"
use_ok 'ojo';

# * /
a('/' => sub {
    my $self = shift;
    $self->render(text => $self->req->method . ($self->param('foo') || ''));
  }
);

# GET /
is g('/')->body, 'GET', 'right content';

# HEAD /
is h('/')->body, '', 'no content';

# POST /
is p('/')->body, 'POST', 'right content';

# PUT /
is u('/')->body, 'PUT', 'right content';

# DELETE /
is d('/')->body, 'DELETE', 'right content';

# POST / (form)
is f('/' => {foo => 'bar'})->body, 'POSTbar', 'right content';

# Parse XML
is x('<title>works</title>')->at('title')->text, 'works', 'right text';

# Bytestream
is b('<foo>')->url_escape, '%3Cfoo%3E', 'right result';
