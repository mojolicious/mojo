#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Mojo::IOLoop;
use Test::More;

# Make sure sockets are working
plan skip_all => 'working sockets required for this test!'
  unless Mojo::IOLoop->new->generate_port;
plan tests => 11;

# Pizza delivery for...
# I. C. Weiner. Aww... I always thought by this stage in my life I'd be the
# one making the crank calls.
use Mojolicious::Lite;
use Test::Mojo;

# Silence
app->log->level('error');

# Twinkle template syntax
my $twinkle = {
    escape_mark     => '*',
    expression_mark => '*',
    line_start      => '**',
    tag_end         => '**',
    tag_start       => '**',
    trim_mark       => '*'
};

# Plugins
plugin ep_renderer => {name => 'twinkle', template => $twinkle};
plugin 'pod_renderer';
plugin pod_renderer => {name => 'teapod', preprocess => 'twinkle'};
my $config =
  plugin json_config => {default => {foo => 'bar'}, template => $twinkle};
is($config->{foo},  'bar');
is($config->{test}, 23);

# GET /
get '/' => {name => '<sebastian>'} => 'index';

# GET /docs
get '/docs' => {codename => 'snowman'} => 'docs';

# GET /docs
get '/docs2' => {codename => 'snowman'} => 'docs2';

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_like(qr/testHello <sebastian>!123/);

# GET /docs
$t->get_ok('/docs')->status_is(200)->content_like(qr/<h3>snowman<\/h3>/);

# GET /docs2
$t->get_ok('/docs2')->status_is(200)->content_like(qr/<h2>snowman<\/h2>/);

__DATA__
@@ index.html.twinkle
** layout 'twinkle';
Hello **** $name **!\

@@ layouts/twinkle.html.ep
test<%= content %>123\

@@ docs.html.pod
<%= '=head3 ' . $codename %>

@@ docs2.html.teapod
*** '=head2 ' . $codename
