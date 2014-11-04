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

# Default layout for whole application
app->defaults(layout => 'default');

get '/works';

get '/mixed';

get '/doesnotexist';

get '/dies' => sub {die};

get '/template_inheritance' => sub { shift->render('template_inheritance') };

get '/layout_without_inheritance' => sub {
  shift->render(
    template => 'layouts/template_inheritance',
    handler  => 'ep',
    layout   => undef
  );
};

get '/double_inheritance' =>
  sub { shift->render(template => 'double_inheritance') };

get '/triple_inheritance';

get '/nested-includes' => sub {
  my $c = shift;
  $c->render(
    template => 'nested-includes',
    layout   => 'layout',
    handler  => 'ep'
  );
};

get '/localized/include' => sub {
  my $c = shift;
  $c->render('localized', test => 'foo', reverse => 1);
};

get '/plain/reverse' => {text => 'Hello!', format => 'foo', reverse => 1};

get '/outerlayout' => sub {
  my $c = shift;
  $c->render(template => 'outerlayout', layout => 'layout');
};

get '/outerextends' => sub {
  my $c = shift;
  $c->render(template => 'outerlayout', extends => 'layouts/layout');
};

get '/outerlayouttwo' => {layout => 'layout'} => sub {
  my $c = shift;
  is($c->stash->{layout}, 'layout', 'right value');
  $c->render(handler => 'ep');
  is($c->stash->{layout}, 'layout', 'right value');
} => 'outerlayout';

get '/outerinnerlayout' => sub {
  my $c = shift;
  $c->render(
    template => 'outerinnerlayout',
    layout   => 'layout',
    handler  => 'ep'
  );
};

get '/withblocklayout' => sub {
  my $c = shift;
  $c->render(template => 'index', layout => 'with_block', handler => 'epl');
};

get '/content_for';

get '/inline' => {inline => '<%= "inline!" %>'};

get '/inline/again' => {inline => 0};

get '/data' => {data => 0};

get '/variants' => {layout => 'variants'} => sub {
  my $c = shift;
  $c->stash->{variant} = $c->param('device');
  $c->render('variants');
};

my $t = Test::Mojo->new;

# "0" content reassignment
my $c = $t->app->build_controller;
$c->content(foo => '0');
is $c->content('foo'), '0', 'right content';
$c->content(foo => '1');
is $c->content('foo'), '0', 'right content';

# Template with layout
$t->get_ok('/works')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("DefaultJust worksThis <template> just works!\n\n");

# Different layout
$t->get_ok('/works?green=1')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("GreenJust worksThis <template> just works!\n\n");

# Extended
$t->get_ok('/works?blue=1')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("BlueJust worksThis <template> just works!\n\n");

# Mixed formats
$t->get_ok('/mixed')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is("Mixed formats\n\n");

# Missing template
$t->get_ok('/doesnotexist')->status_is(404)
  ->content_is("DefaultNot found happenedNot found happened!\n\n");

# Missing template with different layout
$t->get_ok('/doesnotexist?green=1')->status_is(404)
  ->content_is("GreenNot found happenedNot found happened!\n\n");

# Extended missing template
$t->get_ok('/doesnotexist?blue=1')->status_is(404)
  ->content_is("BlueNot found happenedNot found happened!\n\n");

# Dead action
$t->get_ok('/dies')->status_is(500)
  ->content_is("DefaultException happenedException happened!\n\n");

# Dead action with different layout
$t->get_ok('/dies?green=1')->status_is(500)
  ->content_is("GreenException happenedException happened!\n\n");

# Extended dead action
$t->get_ok('/dies?blue=1')->status_is(500)
  ->content_is("BlueException happenedException happened!\n\n");

# Template inheritance
$t->get_ok('/template_inheritance')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is(
  "<title>Works!</title>\n<br>\nSidebar!\nHello World!\n\nDefault footer!\n");

# Just the layout
$t->get_ok('/layout_without_inheritance')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is(
  "<title></title>\nDefault header!\nDefault sidebar!\n\nDefault footer!\n");

# Double inheritance
$t->get_ok('/double_inheritance')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("<title>Works!</title>\n<br>\nSidebar too!\n"
    . "Hello World!\n\nDefault footer!\n");

# Triple inheritance
$t->get_ok('/triple_inheritance')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("<title>Works!</title>\n<br>\nSidebar too!\n"
    . "New <content>.\n\nDefault footer!\n");

# Template from plugin
$t->get_ok('/plugin_with_template')->status_is(200)
  ->content_is("layout_with_template\nwith template\n\n");

# Nested included templates
$t->get_ok('/nested-includes')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("layouted Nested <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n\n");

# Included template with localized stash values
$t->get_ok('/localized/include')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("lmth\n\noof\n\n\n123 2dezilacol\noof 1dezilacol");

# Filter
$t->get_ok('/plain/reverse')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_type_is('text/plain')
  ->content_is('oof!olleH');

# Layout in render call
$t->get_ok('/outerlayout')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("layouted <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# Extends in render call
$t->get_ok('/outerextends')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("layouted <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# Layout in route
$t->get_ok('/outerlayouttwo')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("layouted <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# Included template with layout
$t->get_ok('/outerinnerlayout')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\nlayouted [\n  1,\n  2\n]\nthere<br>!\n\n\n\n");

# Layout with block
$t->get_ok('/withblocklayout')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("\nwith_block \n\nOne: one\nTwo: two\n\n");

# Content blocks
$t->get_ok('/content_for')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("DefaultThis\n\nseems\nto\nHello    world!\n\nwork!\n\n");

# Inline template
$t->get_ok('/inline')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("inline!\n");

# "0" inline template
$t->get_ok('/inline/again')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("0\n");

# "0" data
$t->get_ok('/data')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is(0);

# Variants (desktop)
$t->get_ok('/variants.txt')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is('Variant: Desktop!');

# Variants (tablet)
$t->get_ok('/variants.txt?device=tablet')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is('Variant: Tablet!');

# Variants (desktop fallback)
$t->get_ok('/variants.txt?device=phone')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is('Variant: Desktop!');

# Variants ("0")
$t->get_ok('/variants.txt?device=0')->status_is(200)
  ->content_type_is('text/plain;charset=UTF-8')
  ->content_is('Another variant: Desktop!');

done_testing();

__DATA__
@@ layouts/default.html.ep
Default<%= title %><%= content %>

@@ layouts/green.html.ep
Green<%= title %><%= content %>

@@ layouts/mixed.txt.ep
Mixed <%= content %>

@@ blue.html.ep
Blue<%= title %><%= content %>

@@ works.html.ep
% title 'Just works';
% layout 'green' if param 'green';
% extends 'blue' if param 'blue';
This <template> just works!

@@ mixed.html.ep
% layout 'mixed', format => 'txt';
formats

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
% extends 'localized1';
<%= $test %>
<%= include 'localized_include', test => 321, extends => 'localized2' %>
<%= $test %>

@@ localized_include.html.ep
<%= $test %>

@@ localized1.html.ep
localized1 <%= content %>

@@ localized2.html.ep
localized2 <%= content %>

@@ outerlayout.html.ep
%= c(qw(> o l l e H <))->reverse->join
<%= $c->render_to_string('outermenu') %>

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

@@ layouts/variants.txt.ep
Variant: <%= content %>\

@@ layouts/variants.txt+0.ep
Another variant: <%= content %>\

@@ variants.txt.ep
Desktop!\

@@ variants.txt+tablet.epl
Tablet!\
