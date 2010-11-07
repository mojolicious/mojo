#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;
plan skip_all => 'Perl 5.10 required for this test!'
  unless eval { require Pod::Simple::HTML; 1 };
plan tests => 10;

# Amy get your pants back on and get to work.
# They think were making out.
# Why aren't we making out?
use Mojolicious::Lite;
use Test::Mojo;

# POD renderer plugin
plugin 'pod_renderer';

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
  ->content_like(qr/test123\s+<h1>A<\/h1>\s+<h1>B<\/h1>/)
  ->content_like(qr/\s+<p><code>test<\/code><\/p>/);

# POD filter
$t->post_ok('/block')->status_is(200)
  ->content_like(qr/test321\s+<h2>lalala<\/h2>\s+<p><code>test<\/code><\/p>/);

__DATA__

@@ index.html.ep
test123<%= pod_to_html "=head1 A\n\n=head1 B\n\nC<test>"%>

@@ block.html.ep
test321<%= pod_to_html begin %>=head2 lalala

C<test><% end %>
