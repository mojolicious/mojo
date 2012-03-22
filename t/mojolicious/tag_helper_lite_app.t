use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 72;

# "Hey! Bite my glorious golden ass!"
use Mojolicious::Lite;
use Test::Mojo;

# OPTIONS /tags
options 'tags';

# PATCH /more_tags
patch 'more_tags';

# GET /small_tags
get 'small_tags';

# GET|POST /links
any [qw/GET POST/] => 'links';

# GET /script
get 'script';

# GET /style
get 'style';

# GET /basicform
get '/basicform';

# GET /multibox
get '/multibox';

# GET /form
get 'form/:test' => 'form';

# PUT /selection
put 'selection';

# PATCH|POST /☃
any [qw/PATCH POST/] => '/☃' => 'snowman';

# POST /no_snowman
post '/no_snowman';

my $t = Test::Mojo->new;

# OPTIONS /tags
$t->options_ok('/tags')->status_is(200)->content_is(<<EOF);
<foo />
<foo bar="baz" />
<foo one="t&lt;wo" three="four">Hello</foo>
EOF

# PATCH /more_tags
$t->patch_ok('/more_tags')->status_is(200)->content_is(<<EOF);
<bar>b&lt;a&gt;z</bar>
<bar>0</bar>
<bar class="test">0</bar>
<bar class="test"></bar>
EOF

# GET /small_tags
$t->get_ok('/small_tags')->status_is(200)->content_is(<<EOF);
<div>some &amp; content</div>
<div>
  <p id="0">just</p>
  <p>0</p>
</div>
<div>works</div>
EOF

# GET /links
$t->get_ok('/links')->status_is(200)->content_is(<<EOF);
<a href="/path">Pa&lt;th</a>
<a href="http://example.com/" title="Foo">Foo</a>
<a href="http://example.com/"><foo>Example</foo></a>
<a href="/links">Home</a>
<a href="/form/23" title="Foo">Foo</a>
EOF

# POST /links
$t->post_ok('/links')->status_is(200)->content_is(<<EOF);
<a href="/path">Pa&lt;th</a>
<a href="http://example.com/" title="Foo">Foo</a>
<a href="http://example.com/"><foo>Example</foo></a>
<a href="/links">Home</a>
<a href="/form/23" title="Foo">Foo</a>
EOF

# GET /script
$t->get_ok('/script')->status_is(200)->content_is(<<EOF);
<script src="/script.js" type="text/javascript"></script>
<script type="text/javascript">//<![CDATA[

  var a = 'b';

//]]></script>
<script type="foo">//<![CDATA[

  var a = 'b';

//]]></script>
EOF

# GET /style
$t->get_ok('/style')->status_is(200)->content_is(<<EOF);
<link href="/foo.css" media="screen" rel="stylesheet" type="text/css" />
<style type="text/css">/*<![CDATA[*/

  body {color: #000}

/*]]>*/</style>
<style type="foo">/*<![CDATA[*/

  body {color: #000}

/*]]>*/</style>
EOF

# GET /basicform
$t->get_ok('/basicform')->status_is(200)->content_is(<<EOF);
<form action="/links">
  <input name="foo" value="bar" />
  <input class="test" name="bar" value="baz" />
  <input name="yada" value="" />
  <input class="tset" name="baz" value="yada" />
  <input type="submit" value="Ok" />
</form>
EOF

# GET /multibox
$t->get_ok('/multibox')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input name="foo" type="checkbox" value="one" />
  <input name="foo" type="checkbox" value="two" />
  <input type="submit" value="Ok" />
</form>
EOF

# GET /multibox (with one value)
$t->get_ok('/multibox?foo=two')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input name="foo" type="checkbox" value="one" />
  <input checked="checked" name="foo" type="checkbox" value="two" />
  <input type="submit" value="Ok" />
</form>
EOF

# GET /multibox (with one right and one wrong value)
$t->get_ok('/multibox?foo=one&foo=three')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input checked="checked" name="foo" type="checkbox" value="one" />
  <input name="foo" type="checkbox" value="two" />
  <input type="submit" value="Ok" />
</form>
EOF

# GET /multibox (with wrong value)
$t->get_ok('/multibox?foo=bar')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input name="foo" type="checkbox" value="one" />
  <input name="foo" type="checkbox" value="two" />
  <input type="submit" value="Ok" />
</form>
EOF

# GET /multibox (with two values)
$t->get_ok('/multibox?foo=two&foo=one')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input checked="checked" name="foo" type="checkbox" value="one" />
  <input checked="checked" name="foo" type="checkbox" value="two" />
  <input type="submit" value="Ok" />
</form>
EOF

# GET /form
$t->get_ok('/form/lala?a=2&b=0&c=2&d=3&escaped=1%22+%222')->status_is(200)
  ->content_is(<<EOF);
<form action="/links" method="post">
  <input name="foo" />
</form>
<form action="/form/24" method="post">
  <input name="foo" />
  <input name="foo" type="checkbox" value="1" />
  <input checked="checked" name="a" type="checkbox" value="2" />
  <input name="b" type="radio" value="1" />
  <input checked="checked" name="b" type="radio" value="0" />
  <input name="c" type="hidden" value="foo" />
  <input name="d" type="file" />
  <textarea cols="40" name="e" rows="50">
    default!
  </textarea>
  <textarea name="f"></textarea>
  <input name="g" type="password" />
  <input id="foo" name="h" type="password" />
  <input type="submit" value="Ok!" />
  <input id="bar" type="submit" value="Ok too!" />
</form>
<form action="/">
  <input name="foo" />
</form>
<input name="escaped" value="1&quot; &quot;2" />
<input name="a" value="2" />
<input name="a" value="2" />
EOF

# GET /form (alternative)
$t->get_ok('/form/lala?c=b&d=3&e=4&f=<5')->status_is(200)->content_is(<<EOF);
<form action="/links" method="post">
  <input name="foo" />
</form>
<form action="/form/24" method="post">
  <input name="foo" />
  <input name="foo" type="checkbox" value="1" />
  <input name="a" type="checkbox" value="2" />
  <input name="b" type="radio" value="1" />
  <input name="b" type="radio" value="0" />
  <input name="c" type="hidden" value="foo" />
  <input name="d" type="file" />
  <textarea cols="40" name="e" rows="50">4</textarea>
  <textarea name="f">&lt;5</textarea>
  <input name="g" type="password" />
  <input id="foo" name="h" type="password" />
  <input type="submit" value="Ok!" />
  <input id="bar" type="submit" value="Ok too!" />
</form>
<form action="/">
  <input name="foo" />
</form>
<input name="escaped" />
<input name="a" />
<input name="a" value="c" />
EOF

# PUT /selection (empty)
$t->put_ok('/selection')->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option value="g">g</option>'
    . '</select>' . "\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option value="bar">bar</option>'
    . '<option value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" value="d">D</option>'
    . '<option value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<input type="submit" value="Ok" />' . "\n"
    . '</form>'
    . "\n");

# PUT /selection (values)
$t->put_ok('/selection?a=e&foo=bar&bar=baz')->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option selected="selected" value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option value="g">g</option>'
    . '</select>' . "\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option selected="selected" value="bar">bar</option>'
    . '<option value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" value="d">D</option>'
    . '<option selected="selected" value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<input type="submit" value="Ok" />' . "\n"
    . '</form>'
    . "\n");

# PUT /selection (multiple values)
$t->put_ok('/selection?foo=bar&a=e&foo=baz&bar=d')->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option selected="selected" value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option value="g">g</option>'
    . '</select>' . "\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option selected="selected" value="bar">bar</option>'
    . '<option selected="selected" value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" selected="selected" value="d">D</option>'
    . '<option value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<input type="submit" value="Ok" />' . "\n"
    . '</form>'
    . "\n");

# PUT /selection (multiple values preselected)
$t->put_ok('/selection?preselect=1')->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option selected="selected" value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option selected="selected" value="g">g</option>'
    . '</select>' . "\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option value="bar">bar</option>'
    . '<option value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" value="d">D</option>'
    . '<option value="baz">baz</option>'
    . '</select>' . "\n  "
    . '<input type="submit" value="Ok" />' . "\n"
    . '</form>'
    . "\n");

# PATCH /☃
$t->post_ok('/☃')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="foo">b&lt;a&gt;r</textarea>
  <input type="submit" value="☃" />
</form>
EOF

# POST /☃ (form value)
$t->post_ok('/☃?foo=ba<z')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="foo">ba&lt;z</textarea>
  <input type="submit" value="☃" />
</form>
EOF

# PATCH /☃ (empty form value)
$t->patch_ok('/☃?foo=')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="foo"></textarea>
  <input type="submit" value="☃" />
</form>
EOF

# POST /no_snowman (POST form)
$t->post_ok('/no_snowman')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <input type="submit" value="whatever" />
</form>
EOF

# POST /no_snowman (PATCH form)
$t->post_ok('/no_snowman?foo=1')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="PATCH">
  <input type="submit" value="whatever" />
</form>
EOF

__DATA__
@@ tags.html.ep
<%= tag 'foo' %>
<%= tag 'foo', bar => 'baz' %>
<%= tag 'foo', one => 't<wo', three => 'four' => begin %>Hello<% end %>

@@ more_tags.html.ep
%= tag bar => 'b<a>z'
%= tag bar => 0
%= tag 'bar', class => 'test', 0
%= tag 'bar', class => 'test', ''

@@ small_tags.html.ep
%=t div => 'some & content'
%=t div => begin
  %=t p => (id => 0) => 'just'
  %=t p => 0
%= end
%=t div => 'works'

@@ links.html.ep
<%= link_to 'Pa<th' => '/path' %>
<%= link_to 'http://example.com/', title => 'Foo', sub { 'Foo' } %>
<%= link_to 'http://example.com/' => begin %><foo>Example</foo><% end %>
<%= link_to Home => 'links' %>
<%= link_to Foo => 'form', {test => 23}, title => 'Foo' %>

@@ script.html.ep
<%= javascript '/script.js' %>
<%= javascript begin %>
  var a = 'b';
<% end %>
<%= javascript type => 'foo' => begin %>
  var a = 'b';
<% end %>

@@ style.html.ep
<%= stylesheet '/foo.css' %>
<%= stylesheet begin %>
  body {color: #000}
<% end %>
<%= stylesheet type => 'foo' => begin %>
  body {color: #000}
<% end %>

@@ basicform.html.ep
%= form_for links => begin
  %= text_field foo => 'bar'
  %= text_field bar => 'baz', class => 'test'
  %= text_field yada => undef
  %= input_tag baz => 'yada', class => 'tset'
  %= submit_button
%= end

@@ multibox.html.ep
%= form_for multibox => begin
  %= check_box foo => 'one'
  %= check_box foo => 'two'
  %= submit_button
%= end

@@ form.html.ep
<%= form_for 'links', method => 'post' => begin %>
  <%= input_tag 'foo' %>
<% end %>
%= form_for 'form', {test => 24}, method => 'post' => begin
  %= text_field 'foo'
  %= check_box foo => 1
  %= check_box a => 2
  %= radio_button b => '1'
  %= radio_button b => '0'
  %= hidden_field c => 'foo'
  %= file_field 'd'
  %= text_area e => (cols => 40, rows => 50) => begin
    default!
  %= end
  %= text_area 'f'
  %= password_field 'g'
  %= password_field 'h', id => 'foo'
  %= submit_button 'Ok!'
  %= submit_button 'Ok too!', id => 'bar'
%= end
<%= form_for '/' => begin %>
  <%= input_tag 'foo' %>
<% end %>
<%= input_tag 'escaped' %>
<%= input_tag 'a' %>
<%= input_tag 'a', value => 'c' %>

@@ selection.html.ep
% param a => qw/b g/ if param 'preselect';
%= form_for selection => begin
  %= select_field a => ['b', {c => ['<d', [ E => 'e'], 'f']}, 'g']
  %= select_field foo => [qw/bar baz/], multiple => 'multiple'
  %= select_field bar => [['D' => 'd', disabled => 'disabled'], 'baz']
  %= submit_button
%= end

@@ snowman.html.ep
%= form_for snowman => begin
  %= text_area foo => 'b<a>r', cols => 40
  %= submit_button '☃'
%= end

@@ no_snowman.html.ep
% my @attrs = param('foo') ? (method => 'PATCH') : ();
%= form_for 'snowman', @attrs => begin
  %= submit_button 'whatever'
%= end
