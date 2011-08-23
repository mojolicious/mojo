#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER}  = 'Mojo::IOWatcher';
  $ENV{MOJO_MODE}       = 'development';
}

use Test::More tests => 54;

# "This calls for a party, baby.
#  I'm ordering 100 kegs, 100 hookers and 100 Elvis impersonators that aren't
#  above a little hooking should the occasion arise."
use Mojolicious::Lite;
use Test::Mojo;

app->renderer->root(app->home->rel_dir('does_not_exist'));

# GET /dead_template
get '/dead_template';

# GET /dead_included_template
get '/dead_included_template';

# GET /dead_template_with_layout
get '/dead_template_with_layout';

# GET /dead_action
get '/dead_action' => sub { die 'dead action!' };

# GET /double_dead_action
get '/double_dead_action' => sub {
  eval { die 'double dead action!' };
  die $@;
};

# GET /trapped
get '/trapped' => sub {
  my $self = shift;
  eval { die {foo => 'bar'} };
  $self->render_text($@->{foo} || 'failed');
};

# GET /missing_template
get '/missing_template';

# Dummy exception object
package MyException;
use Mojo::Base -base;
use overload '""' => sub { shift->error }, fallback => 1;

has 'error';

package main;

# GET /trapped/too
get '/trapped/too' => sub {
  my $self = shift;
  eval { die MyException->new(error => 'works') };
  $self->render_text("$@" || 'failed');
};

my $t = Test::Mojo->new;

# GET /does_not_exist ("not_found.development.html.ep" route suggestion)
$t->get_ok('/does_not_exist')->status_is(404)
  ->content_like(qr/get '\/does_not_exist'/);

# POST /does_not_exist ("not_found.development.html.ep" route suggestion)
$t->post_ok('/does_not_exist')->status_is(404)
  ->content_like(qr/any '\/does_not_exist'/);

# GET /dead_template
$t->get_ok('/dead_template')->status_is(500)->content_like(qr/1\./)
  ->content_like(qr/dead\ template!/);

# GET /dead_included_template
$t->get_ok('/dead_included_template')->status_is(500)->content_like(qr/1\./)
  ->content_like(qr/dead\ template!/);

# GET /dead_template_with_layout
$t->get_ok('/dead_template_with_layout')->status_is(500)
  ->content_like(qr/2\./)->content_like(qr/dead\ template\ with\ layout!/);

# GET /dead_action
$t->get_ok('/dead_action')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')->content_like(qr/32\./)
  ->content_like(qr/dead\ action!/);

# GET /dead_action.xml (different format)
$t->get_ok('/dead_action.xml')->status_is(500)->content_type_is('text/xml')
  ->content_is("<very>bad</very>\n");

# GET /dead_action.json (unsupported format)
$t->get_ok('/dead_action.json')->status_is(500)
  ->content_type_is('text/html;charset=UTF-8')->content_like(qr/32\./)
  ->content_like(qr/dead\ action!/);

# GET /double_dead_action
$t->get_ok('/double_dead_action')->status_is(500)->content_like(qr/36\./)
  ->content_like(qr/double\ dead\ action!/);

# GET /trapped
$t->get_ok('/trapped')->status_is(200)->content_is('bar');

# GET /trapped/too
$t->get_ok('/trapped/too')->status_is(200)->content_is('works');

# GET /missing_template
$t->get_ok('/missing_template')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8')->content_like(qr/Not Found/);

# GET /missing_template.xml (different format)
$t->get_ok('/missing_template.xml')->status_is(404)
  ->content_type_is('text/xml')->content_is("<somewhat>bad</somewhat>\n");

# GET /missing_template.json (unsupported format)
$t->get_ok('/missing_template.json')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8')->content_like(qr/Not Found/);

__DATA__
@@ layouts/green.html.ep
%= content

@@ dead_template.html.ep
% die 'dead template!';

@@ dead_included_template.html.ep
this
%= include 'dead_template'
works!

@@ dead_template_with_layout.html.ep
% layout 'green';
% die 'dead template with layout!';

@@ exception.xml.ep
<very>bad</very>

@@ not_found.xml.ep
<somewhat>bad</somewhat>
