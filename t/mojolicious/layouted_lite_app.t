use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor';
}

use Test::More tests => 102;

use FindBin;
use lib "$FindBin::Bin/lib";

# "We're certainly not building anything sinster, if that's what you mean.
#  Now come on, something sinister won't build itself."
use Mojolicious::Lite;
use Test::Mojo;

# Plugin with a template
plugin 'PluginWithTemplate';

app->renderer->paths->[0] = app->home->rel_dir('does_not_exist');

# Default layout for whole application
app->defaults(layout => 'default');

# GET /works
get '/works';

# GET /doenotexist
get '/doesnotexist';

# GET /dies
get '/dies' => sub {die};

# GET /template_inheritance
get '/template_inheritance' => sub { shift->render('template_inheritance') };

# GET /layout_without_inheritance
get '/layout_without_inheritance' => sub {
  shift->render(
    template => 'layouts/template_inheritance',
    handler  => 'ep',
    layout   => undef
  );
};

# GET /double_inheritance
get '/double_inheritance' =>
  sub { shift->render(template => 'double_inheritance') };

# GET /triple_inheritance
get '/triple_inheritance';

# GET /nested-includes
get '/nested-includes' => sub {
  my $self = shift;
  $self->render(
    template => 'nested-includes',
    layout   => 'layout',
    handler  => 'ep'
  );
};

# GET /localized/include
get '/localized/include' => sub {
  my $self = shift;
  $self->render('localized', test => 'foo');
};

# GET /outerlayout
get '/outerlayout' => sub {
  my $self = shift;
  $self->render(
    template => 'outerlayout',
    layout   => 'layout',
    handler  => 'ep'
  );
};

# GET /outerlayouttwo
get '/outerlayouttwo' => {layout => 'layout'} => sub {
  my $self = shift;
  is($self->stash->{layout}, 'layout', 'right value');
  $self->render(handler => 'ep');
  is($self->stash->{layout}, 'layout', 'right value');
} => 'outerlayout';

# GET /outerinnerlayout
get '/outerinnerlayout' => sub {
  my $self = shift;
  $self->render(
    template => 'outerinnerlayout',
    layout   => 'layout',
    handler  => 'ep'
  );
};

# GET /withblocklayout
get '/withblocklayout' => sub {
  my $self = shift;
  $self->render(
    template => 'index',
    layout   => 'with_block',
    handler  => 'epl'
  );
};

# GET /content_for
get '/content_for';

# GET /inline
get '/inline' => {inline => '<%= "inline!" %>'};

# GET /inline/again
get '/inline/again' => {inline => 0};

# GET /data
get '/data' => {data => 0};

my $t = Test::Mojo->new;

# GET /works
$t->get_ok('/works')->status_is(200)
  ->content_is("DefaultJust worksThis <template> just works!\n\n");

# GET /works (different layout)
$t->get_ok('/works?green=1')->status_is(200)
  ->content_is("GreenJust worksThis <template> just works!\n\n");

# GET /works (extended)
$t->get_ok('/works?blue=1')->status_is(200)
  ->content_is("BlueJust worksThis <template> just works!\n\n");

# GET /doesnotexist
$t->get_ok('/doesnotexist')->status_is(404)
  ->content_is("DefaultNot found happenedNot found happened!\n\n");

# GET /doesnotexist (different layout)
$t->get_ok('/doesnotexist?green=1')->status_is(404)
  ->content_is("GreenNot found happenedNot found happened!\n\n");

# GET /doesnotexist (extended)
$t->get_ok('/doesnotexist?blue=1')->status_is(404)
  ->content_is("BlueNot found happenedNot found happened!\n\n");

# GET /dies
$t->get_ok('/dies')->status_is(500)
  ->content_is("DefaultException happenedException happened!\n\n");

# GET /dies (different layout)
$t->get_ok('/dies?green=1')->status_is(500)
  ->content_is("GreenException happenedException happened!\n\n");

# GET /dies (extended)
$t->get_ok('/dies?blue=1')->status_is(500)
  ->content_is("BlueException happenedException happened!\n\n");

# GET /template_inheritance
$t->get_ok('/template_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  "<title>Works!</title>\n<br>\nSidebar!\nHello World!\n\nDefault footer!\n");

# GET /layout_without_inheritance
$t->get_ok('/layout_without_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  "<title></title>\nDefault header!\nDefault sidebar!\n\nDefault footer!\n");

# GET /double_inheritance
$t->get_ok('/double_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("<title>Works!</title>\n<br>\nSidebar too!\n"
    . "Hello World!\n\nDefault footer!\n");

# GET /triple_inheritance
$t->get_ok('/triple_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("<title>Works!</title>\n<br>\nSidebar too!\n"
    . "New <content>.\n\nDefault footer!\n");

# GET /plugin_with_template
$t->get_ok('/plugin_with_template')->status_is(200)
  ->content_is("layout_with_template\nwith template\n\n");

# GET /nested-includes
$t->get_ok('/nested-includes')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Nested Hello\n[\n  1,\n  2\n]\nthere<br>!\n\n\n\n");

# GET /localized/include
$t->get_ok('/localized/include')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("localized1 foo\nlocalized2 321\n\n\nfoo\n\n");

# GET /outerlayout
$t->get_ok('/outerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# GET /outerlayouttwo
$t->get_ok('/outerlayouttwo')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# GET /outerinnerlayout
$t->get_ok('/outerinnerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  "layouted Hello\nlayouted [\n  1,\n  2\n]\nthere<br>!\n\n\n\n");

# GET /withblocklayout
$t->get_ok('/withblocklayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("\nwith_block \n\nOne: one\nTwo: two\n\n");

# GET /content_for
$t->get_ok('/content_for')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("DefaultThis\n\nseems\nto\nHello    world!\n\nwork!\n\n");

# GET /inline
$t->get_ok('/inline')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("inline!\n");

# GET /inline/again
$t->get_ok('/inline/again')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("0\n");

# GET /data
$t->get_ok('/data')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is(0);

__DATA__
@@ layouts/default.html.ep
Default<%= title %><%= content %>

@@ layouts/green.html.ep
Green<%= title %><%= content %>

@@ blue.html.ep
Blue<%= title %><%= content %>

@@ works.html.ep
% title 'Just works';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
This <template> just works!

@@ exception.html.ep
% title 'Exception happened';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
Exception happened!

@@ not_found.html.ep
% title 'Not found happened';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
Not found happened!

@@ template_inheritance.html.ep
% layout 'template_inheritance';
% title 'Works!';
<% content header => begin =%>
<%= b('<br>') %>
<% end =%>
<% content sidebar => begin =%>
Sidebar!
<% end =%>
Hello World!

@@ layouts/template_inheritance.html.ep
<title><%= title %></title>
% stash foo => 'Default';
<%= content header => begin =%>
Default header!
<% end =%>
<%= content sidebar => begin =%>
<%= stash 'foo' %> sidebar!
<% end =%>
%= content
<%= content footer => begin =%>
Default footer!
<% end =%>

@@ double_inheritance.html.ep
% extends 'template_inheritance';
<% content sidebar => begin =%>
Sidebar too!
<% end =%>

@@ triple_inheritance.html.ep
% extends 'double_inheritance';
New <content>.

@@ layouts/plugin_with_template.html.ep
layout_with_template
<%= content %>

@@ nested-includes.html.ep
Nested <%= include 'outerlayout' %>

@@ localized.html.ep
% layout 'localized1';
<%= $test %>
<%= include 'localized_partial', test => 321, layout => 'localized2' %>
<%= $test %>

@@ localized_partial.html.ep
<%= $test %>

@@ layouts/localized1.html.ep
localized1 <%= content %>

@@ layouts/localized2.html.ep
localized2 <%= content %>

@@ outerlayout.html.ep
Hello
<%= $self->render('outermenu', partial => 1) %>

@@ outermenu.html.ep
% stash test => 'there';
<%= dumper [1, 2] %><%= stash 'test' %><br>!

@@ outerinnerlayout.html.ep
Hello
<%= include 'outermenu', layout => 'layout' %>

@@ layouts/layout.html.ep
layouted <%== content %>

@@ index.html.epl
Just works!\

@@ layouts/with_block.html.epl
<% my $block = begin %>
<% my ($one, $two) = @_; %>
One: <%= $one %>
Two: <%= $two %>
<% end %>
with_block <%= $block->('one', 'two') %>

@@ content_for.html.ep
This
<% content_for message => begin =%>Hello<% end %>
seems
% content_for message => begin
    world!
% end
to
<%= content_for 'message' %>
work!
