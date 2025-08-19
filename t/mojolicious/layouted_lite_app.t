use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::Mojo;
use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('lib')->to_string;

use Mojolicious::Lite;

# Plugin with a template
plugin 'PluginWithTemplate';

app->renderer->paths->[0] = app->home->child('does_not_exist');

# Reverse filter
hook after_render => sub {
  my ($c, $output, $format) = @_;
  return unless $c->stash->{reverse};
  $$output = reverse $$output . $format;
};

# Shared content
hook before_dispatch => sub { shift->content_for(stuff => 'Shared content!') };

# Default layout for whole application
app->defaults(layout => 'default');

get '/works';

get '/mixed';

get '/doesnotexist';

get '/dies' => sub {die};

get '/template_inheritance' => sub { shift->render('template_inheritance') };

get '/layout_without_inheritance' => sub {
  shift->render(template => 'layouts/template_inheritance', handler => 'ep', layout => undef);
};

get '/double_inheritance' => sub { shift->render(template => 'double_inheritance') };

get '/triple_inheritance';

get '/mixed_inheritance/first' => {template => 'first'};

get '/mixed_inheritance/second' => {template => 'second', layout => 'green'};

get '/mixed_inheritance/third' => {template => 'third'};

get '/nested-includes' => sub {
  my $c = shift;
  $c->render(template => 'nested-includes', layout => 'layout', handler => 'ep');
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
  $c->render(template => 'outerlayout', extends => 'layouts/layout', layout => undef);
};

get '/outerlayouttwo' => {layout => 'layout'} => sub {
  my $c = shift;
  is($c->stash->{layout}, 'layout', 'right value');
  $c->render(handler => 'ep');
  is($c->stash->{layout}, 'layout', 'right value');
} => 'outerlayout';

get '/outerinnerlayout' => sub {
  my $c = shift;
  $c->render(template => 'outerinnerlayout', layout => 'layout', handler => 'ep');
};

get '/withblocklayout' => sub {
  my $c = shift;
  $c->render(template => 'index', layout => 'with_block', handler => 'epl');
};

get '/content_for';

get '/content_with';

get '/inline' => {inline => '<%= "inline!" %>'};

get '/inline/again' => {inline => 0};

get '/data' => {data => 0};

get '/variants' => [format => ['txt']] => {layout => 'variants', format => undef} => sub {
  my $c = shift;
  $c->stash->{variant} = $c->param('device');
  $c->render('variants');
};

get '/specific_template' => {template_path => curfile->sibling('templates2')->child('42.html.ep')->to_string};

my $t = Test::Mojo->new;

subtest '"0" content reassignment' => sub {
  my $c = $t->app->build_controller;
  $c->content(foo => '0');
  is $c->content('foo'), '0', 'right content';
  $c->content(foo => '1');
  is $c->content('foo'), '0', 'right content';
};

subtest 'Template with layout' => sub {
  $t->get_ok('/works')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is("DefaultJust worksThis <template> just works!\n\n");
};

subtest 'Different layout' => sub {
  $t->get_ok('/works?green=1')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is("GreenJust worksThis <template> just works!\n\n");
};

subtest 'Extended' => sub {
  $t->get_ok('/works?blue=1')
    ->status_is(200)
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is("BlueJust worksThis <template> just works!\n\n");
};

subtest 'Mixed formats' => sub {
  $t->get_ok('/mixed')->status_is(200)->content_type_is('text/plain;charset=UTF-8')->content_is("Mixed formats\n\n");
};

subtest 'Missing template' => sub {
  $t->get_ok('/doesnotexist')->status_is(500)->content_is("DefaultException happenedException happened!\n\n");
};

subtest 'Missing template with different layout' => sub {
  $t->get_ok('/doesnotexist?green=1')->status_is(500)->content_is("GreenException happenedException happened!\n\n");
};

subtest 'Extended missing template' => sub {
  $t->get_ok('/doesnotexist?blue=1')->status_is(500)->content_is("BlueException happenedException happened!\n\n");
};

subtest 'Extended missing template (not found)' => sub {
  $t->get_ok('/doesreallynotexist?green=1')
    ->status_is(404)
    ->content_is("GreenNot found happenedNot found happened!\n\n");
};

subtest 'Extended missing template (not found)' => sub {
  $t->get_ok('/doesreallynotexist?blue=1')->status_is(404)->content_is("BlueNot found happenedNot found happened!\n\n");
};

subtest 'Dead action' => sub {
  $t->get_ok('/dies')->status_is(500)->content_is("DefaultException happenedException happened!\n\n");
};

subtest 'Dead action with different layout' => sub {
  $t->get_ok('/dies?green=1')->status_is(500)->content_is("GreenException happenedException happened!\n\n");
};

subtest 'Extended dead action' => sub {
  $t->get_ok('/dies?blue=1')->status_is(500)->content_is("BlueException happenedException happened!\n\n");
};

subtest 'Template inheritance' => sub {
  $t->get_ok('/template_inheritance')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("<title>Works!</title>\n<br>\nSidebar!\nHello World!\n\nDefault footer!\n");
};

subtest 'Just the layout' => sub {
  $t->get_ok('/layout_without_inheritance')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("<title></title>\nDefault header!\nDefault sidebar!\n\nDefault footer!\n");
};

subtest 'Double inheritance' => sub {
  $t->get_ok('/double_inheritance')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("<title>Works!</title>\n<br>\nSidebar too!\n" . "Hello World!\n\nDefault footer!\n");
};

subtest 'Triple inheritance' => sub {
  $t->get_ok('/triple_inheritance')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is(
    "<title>Works!</title>\n<br>\nSidebar too!\n" . "New <content>.\nShared content!\n\nDefault footer!\n");
};

subtest 'Mixed inheritance (with layout)' => sub {
  $t->get_ok('/mixed_inheritance/first')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Default\n  Default header\nStuff\n\n  Default footer\n\n");
  $t->get_ok('/mixed_inheritance/second')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Green  New header\nStuff\n\n  Default footer\n\n");
  $t->get_ok('/mixed_inheritance/third')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Default  New header\nStuff\n  New footer\n\n");
};

subtest 'Template from plugin' => sub {
  $t->get_ok('/plugin_with_template')->status_is(200)->content_is("layout_with_template\nwith template\n\n");
};

subtest 'Nested included templates' => sub {
  $t->get_ok('/nested-includes')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("layouted Nested <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n\n");
};

subtest 'Included template with localized stash values' => sub {
  $t->get_ok('/localized/include')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_type_is('text/html;charset=UTF-8')
    ->content_is("lmth\n\noof\n\n\n123 2dezilacol\noof 1dezilacol");
};

subtest 'Filter' => sub {
  $t->get_ok('/plain/reverse')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_type_is('application/octet-stream')
    ->content_is('oof!olleH');
};

subtest 'Layout in render call' => sub {
  $t->get_ok('/outerlayout')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("layouted <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");
};

subtest 'Extends in render call' => sub {
  $t->get_ok('/outerextends')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("layouted <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");
};

subtest 'Layout in route' => sub {
  $t->get_ok('/outerlayouttwo')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("layouted <Hello>\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");
};

subtest 'Included template with layout' => sub {
  $t->get_ok('/outerinnerlayout')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("layouted Hello\nlayouted [\n  1,\n  2\n]\nthere<br>!\n\n\n\n");
};

subtest 'Layout with block' => sub {
  $t->get_ok('/withblocklayout')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("\nwith_block \n\nOne: one\nTwo: two\n\n");
};

subtest 'Content blocks' => sub {
  $t->get_ok('/content_for')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Content!This\n\nseems\nto\nHello    World!\n\nwork!\n\nShared content!\n\n");
  $t->get_ok('/content_with')
    ->status_is(200)
    ->header_is(Server => 'Mojolicious (Perl)')
    ->content_is("Default\n\nSomething <b>else</b>!\n\n\n<br>Hello World!\n\n");
};

subtest 'Inline template' => sub {
  $t->get_ok('/inline')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is("inline!\n");
};

subtest '"0" inline template' => sub {
  $t->get_ok('/inline/again')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is("0\n");
};

subtest '"0" data' => sub {
  $t->get_ok('/data')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')->content_is(0);
};

subtest 'Variants (desktop)' => sub {
  $t->get_ok('/variants.txt')
    ->status_is(200)
    ->content_type_is('text/plain;charset=UTF-8')
    ->content_is('Variant: Desktop!');
};

subtest 'Variants (tablet)' => sub {
  $t->get_ok('/variants.txt?device=tablet')
    ->status_is(200)
    ->content_type_is('text/plain;charset=UTF-8')
    ->content_is('Variant: Tablet!');
};

subtest 'Variants (desktop fallback)' => sub {
  $t->get_ok('/variants.txt?device=phone')
    ->status_is(200)
    ->content_type_is('text/plain;charset=UTF-8')
    ->content_is('Variant: Desktop!');
};

subtest 'Variants ("0")' => sub {
  $t->get_ok('/variants.txt?device=0')
    ->status_is(200)
    ->content_type_is('text/plain;charset=UTF-8')
    ->content_is('Another variant: Desktop!');
};

subtest 'Specific template path' => sub {
  $t->get_ok('/specific_template')->status_is(200)->content_is("DefaultThe answer is 42.\n\n");
};

done_testing();

__DATA__
@@ layouts/default.html.ep
Default<%= title %><%= content %>

@@ layouts/green.html.ep
Green<%= title %><%= content %>

@@ layouts/mixed.txt.ep
Mixed <%= content %>

@@ blue.html.ep
% layout undef;
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

@@ first.html.ep
%= content header => begin
  Default header
% end
Stuff
%= content footer => begin
  Default footer
% end

@@ second.html.ep
% extends 'first';
% content header => begin
  New header
% end

@@ third.html.ep
% extends 'second';
% content footer => begin
  New footer
% end

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
%= content_for 'stuff'

@@ layouts/plugin_with_template.html.ep
layout_with_template
<%= content %>

@@ nested-includes.html.ep
Nested <%= include 'outerlayout' %>

@@ localized.html.ep
% extends 'localized1';
% layout undef;
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

@@ layouts/content_for.html.ep
Content<%= title %><%= content_for 'more' %><%= content %>

@@ content_for.html.ep
% layout 'content_for';
This
<% content_for message => begin =%>Hello<% end %>
seems
% content_for message => begin
    World!
% end
to
<%= content_for 'message' %>
%= include 'content_for_partial'
%= content_for 'stuff'

@@ content_for_partial.html.ep
<% content_for more => begin %>!<% end %>work!

@@ content_with.html.ep
<% content first => begin %>Something<% end %>
<% content_for first => begin %> <b>else<% end %>
% content_for first => '</b>!';
%= content_with 'first'
% content_with first => '';
%= content_with 'first'
<% content second => begin %>World<% end %>
<%= content_with second => begin %><br>Hello <%= content 'second' %>!<% end %>
% content_with 'second'

@@ layouts/variants.txt.ep
Variant: <%= content %>\

@@ layouts/variants.txt+0.ep
Another variant: <%= content %>\

@@ variants.txt.ep
Desktop!\

@@ variants.txt+tablet.epl
Tablet!\
