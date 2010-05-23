#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan skip_all => 'Perl 5.10 required for this test!'
  unless eval { require Pod::Simple::HTML; 1 };
plan tests => 9;

# Amy get your pants back on and get to work.
# They think were making out.
# Why aren't we making out?
use Mojolicious::Lite;
use Test::Mojo;

# POD renderer plugin
plugin 'pod_renderer';

# Silence
app->log->level('error');

# GET /
get '/' => sub {
    my $self = shift;
    $self->render('simple', handler => 'pod');
};

# POST /
post '/' => 'index';

# GET /block
post '/block' => 'block';

my $t = Test::Mojo->new;

# Simple POD template
$t->get_ok('/')->status_is(200)
  ->content_like(qr/<h1>Test123<\/h1>\s+<p>It <code>works<\/code>!<\/p>/);

# POD helper
$t->post_ok('/')->status_is(200)
  ->content_like(qr/test123\s+<h1>lalala<\/h1>\s+<p><code>test<\/code><\/p>/);

# POD filter
$t->post_ok('/block')->status_is(200)
  ->content_like(qr/test321\s+<h2>lalala<\/h2>\s+<p><code>test<\/code><\/p>/);

__DATA__

@@ index.html.ep
test123<%= pod_to_html "=head1 lalala\n\nC<test>"%>

@@ block.html.ep
test321<%{= pod_to_html %>=head2 lalala

C<test><%}%>
