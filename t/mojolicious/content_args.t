use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojolicious::Lite;
use Test::Mojo;

# Plugin with a template
plugin 'PluginWithTemplate';

app->renderer->paths->[0] = app->home->rel_dir('does_not_exist');

# Reverse filter
hook after_render => sub {
  my ($c, $output, $format) = @_;
  return unless $c->stash->{reverse};
  $$output = reverse $$output . $format;
};

get '/index';

get '/default_content';

get '/default_content_with_args';

get '/named_content_old_interface_text';

get '/named_content_old_interface_block';

get '/named_content_with_args';

get '/pass_args_to_block';


my $t = Test::Mojo->new;

# Simple content
$t->get_ok('/index')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("Default\n");

# Default content
$t->get_ok('/default_content')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("Default\n");

# Default content with arguments
$t->get_ok('/default_content_with_args')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("Default\n");

# Named content with old interface. One text argument
$t->get_ok('/named_content_old_interface_text')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("DefaultText\n");

# Named content with old interface. One block argument
$t->get_ok('/named_content_old_interface_block')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("Default\nText\n");

# Named content with arguments
$t->get_ok('/named_content_with_args')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("Default\n");

# Pass args to content's block
$t->get_ok('/pass_args_to_block')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("Default a b c\n\n");


__DATA__

@@ index.html.ep
Default<%= content %>

@@ default_content.html.ep
Default<%= content undef %>

@@ default_content_with_args.html.ep
Default<%= content undef, foo => 'bar' %>

@@ named_content_old_interface_text.html.ep
Default<%= content foo => 'Text' %>

@@ named_content_old_interface_block.html.ep
Default<%= content foo => begin %>
Text
% end

@@ named_content_with_args.html.ep
Default<%= content 'foo', foo => 'bar' %>

@@ pass_args_to_block.html.ep
% content foo => begin
<%= "@_" %>
% end
Default <%= content foo => qw/ a b c / %>
