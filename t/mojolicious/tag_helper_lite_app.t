#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More tests => 30;

# "Hey! Bite my glorious golden ass!"
use Mojolicious::Lite;
use Test::Mojo;

# GET /tags
get 'tags';

# GET /links
get 'links';

# GET /script
get 'script';

# GET /style
get 'style';

# GET /basicform
get '/basicform';

# GET /form
get 'form/:test' => 'form';

# PUT /selection
put 'selection';

my $t = Test::Mojo->new;

# GET /tags
$t->get_ok('/tags')->status_is(200)->content_is(<<EOF);
<foo />
<foo bar="baz" />
<foo one="t&lt;wo" three="four">Hello</foo>
EOF

# GET /links
$t->get_ok('/links')->status_is(200)->content_is(<<EOF);
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

# GET /form
$t->get_ok('/form/lala?a=b&b=0&c=2&d=3&escaped=1%22+%222')->status_is(200)
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
<input name="a" value="b" />
<input name="a" value="b" />
EOF

# GET /form (alternative)
$t->get_ok('/form/lala?c=b&d=3&e=4&f=5')->status_is(200)->content_is(<<EOF);
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
  <textarea name="f">5</textarea>
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
    . '<option value="d">d</option>'
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
    . '<option value="d">d</option>'
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
    . '<option value="d">d</option>'
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

__DATA__
@@ tags.html.ep
<%= tag 'foo' %>
<%= tag 'foo', bar => 'baz' %>
<%= tag 'foo', one => 't<wo', three => 'four' => begin %>Hello<% end %>

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
%= form_for selection => begin
  %= select_field a => ['b', {c => ['d', [ E => 'e'], 'f']}, 'g']
  %= select_field foo => [qw/bar baz/], multiple => 'multiple'
  %= select_field bar => [['D' => 'd', disabled => 'disabled'], 'baz']
  %= submit_button
%= end
