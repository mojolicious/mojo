#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More;
plan skip_all => 'Perl 5.10 or Pod::Simple required for this test!'
  unless eval { require Pod::Simple::HTML; 1 };
plan tests => 28;

# "Amy get your pants back on and get to work.
#  They think were making out.
#  Why aren't we making out?"
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

# Perldoc browser (Welcome)
$t->get_ok('/perldoc')->status_is(200)->text_is('h1 a[id="NAME"]', 'NAME')
  ->text_is('a[id="TUTORIAL"]', 'TUTORIAL')
  ->text_is('a[id="GUIDES"]',   'GUIDES')->content_like(qr/Galaxy/);

# Perldoc browser (Welcome with slash)
$t->get_ok('/perldoc/')->status_is(200)->text_is('h1 a[id="NAME"]', 'NAME')
  ->text_is('a[id="TUTORIAL"]', 'TUTORIAL')
  ->text_is('a[id="GUIDES"]',   'GUIDES')->content_like(qr/Galaxy/);

# Perldoc browser (Mojolicious)
$t->get_ok('/perldoc/Mojolicious')->status_is(200)
  ->text_is('h1 a[id="NAME"]', 'NAME')->text_is('a[id="handler"]', 'handler')
  ->text_like('p', qr/Mojolicious/)->content_like(qr/Sebastian\ Riedel/);

__DATA__

@@ index.html.ep
test123<%= pod_to_html "=head1 A\n\n=head1 B\n\nC<test>"%>

@@ block.html.ep
test321<%= pod_to_html begin %>=head2 lalala

C<test><% end %>
