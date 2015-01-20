use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojolicious::Lite;
use Test::Mojo;

options 'tags';

patch 'more_tags';

get 'small_tags';

get 'tags_with_error';

any [qw(GET POST)] => 'links';

get 'script';

get 'style';

get '/basicform';

post '/text';

get '/multibox';

get 'form/:test' => 'form';

put 'selection';

any [qw(PATCH POST)] => '/☃' => 'snowman';

post '/no_snowman';

my $t = Test::Mojo->new;

# Reuse values
my $values = [app->c(EU => [qw(de en)])];
is app->select_field(country => $values),
    '<select name="country"><optgroup label="EU">'
  . '<option value="de">de</option>'
  . '<option value="en">en</option>'
  . '</optgroup></select>', 'right result';
is app->select_field(country => $values),
    '<select name="country"><optgroup label="EU">'
  . '<option value="de">de</option>'
  . '<option value="en">en</option>'
  . '</optgroup></select>', 'right result';

# Basic tags
$t->options_ok('/tags')->status_is(200)->content_is(<<EOF);
<foo></foo>
<foo bar="baz"></foo>
<foo one="t&lt;wo" three="four">Hello</foo>
<div data-my-test-id="1" data-name="test">some content</div>
<div data="bar">some content</div>
EOF
$t->patch_ok('/more_tags')->status_is(200)->content_is(<<EOF);
<bar>b&lt;a&gt;z</bar>
<bar>0</bar>
<bar class="test">0</bar>
<bar class="test"></bar>
EOF

# Shortcut
$t->get_ok('/small_tags')->status_is(200)->content_is(<<EOF);
<div id="&amp;lt;">test &amp; 123</div>
<div>
  <p id="0">just</p>
  <p>0</p>
</div>
<div>works</div>
EOF

# Tags with error
$t->get_ok('/tags_with_error')->status_is(200)->content_is(<<EOF);
<bar class="field-with-error">0</bar>
<bar class="test field-with-error">0</bar>
<bar class="test field-with-error">
  0
</bar>
EOF

# Links
$t->get_ok('/links')->status_is(200)->content_is(<<'EOF');
<a href="/path">Pa&lt;th</a>
<a href="http://example.com/" title="Foo">Foo</a>
<a href="//example.com/"><foo>Example</foo></a>
<a href="mailto:sri@example.com">Contact</a>
<a href="mailto:sri@example.com">Contact</a>
<a href="/links">Home</a>
<a href="/form/23" title="Foo">Foo</a>
<a href="/form/23" title="Foo">Foo</a>
EOF
$t->post_ok('/links')->status_is(200)->content_is(<<'EOF');
<a href="/path">Pa&lt;th</a>
<a href="http://example.com/" title="Foo">Foo</a>
<a href="//example.com/"><foo>Example</foo></a>
<a href="mailto:sri@example.com">Contact</a>
<a href="mailto:sri@example.com">Contact</a>
<a href="/links">Home</a>
<a href="/form/23" title="Foo">Foo</a>
<a href="/form/23" title="Foo">Foo</a>
EOF

# Scripts
$t->get_ok('/script')->status_is(200)->content_is(<<EOF);
<script src="/script.js"></script>
<script>//<![CDATA[

  var a = 'b';

//]]></script>
<script type="foo">//<![CDATA[

  var a = 'b';

//]]></script>
EOF

# Stylesheets
$t->get_ok('/style')->status_is(200)->content_is(<<EOF);
<link href="/foo.css" rel="stylesheet">
<style>/*<![CDATA[*/

  body {color: #000}

/*]]>*/</style>
<style type="foo">/*<![CDATA[*/

  body {color: #000}

/*]]>*/</style>
EOF

# Basic form
$t->get_ok('/basicform')->status_is(200)->content_is(<<EOF);
<form action="/links">
  <label for="foo">&lt;Foo&gt;</label>
  <input name="foo" type="text" value="bar">
  <label for="bar">
    Bar<br>
  </label>
  <input class="test" name="bar" type="text" value="baz">
  <input name="yada" type="text" value="">
  <input class="tset" name="baz" value="yada">
  <input type="submit" value="Ok">
</form>
EOF

# Text input fields
$t->post_ok('/text')->status_is(200)->content_is(<<'EOF');
<form action="/text" method="POST">
  <input class="foo" name="color" type="color" value="#ffffff">
  <input class="foo" name="date" type="date" value="2012-12-12">
  <input class="foo" name="dt" type="datetime" value="2012-12-12T23:59:59Z">
  <input class="foo" name="email" type="email" value="nospam@example.com">
  <input class="foo" name="month" type="month" value="2012-12">
  <input class="foo" name="number" type="number" value="23">
  <input class="foo" name="range" type="range" value="24">
  <input class="foo" name="search" type="search" value="perl">
  <input class="foo" name="tel" type="tel" value="123456789">
  <input class="foo" name="time" type="time" value="23:59:59">
  <input class="foo" name="url" type="url" value="http://mojolicio.us">
  <input class="foo" name="week" type="week" value="2012-W16">
  <input type="submit" value="Ok">
</form>
EOF

# Text input fields with values
$t->post_ok(
  '/text' => form => {
    color  => '#000000',
    date   => '2012-12-13',
    dt     => '2012-12-13T23:59:59Z',
    email  => 'spam@example.com',
    month  => '2012-11',
    number => 25,
    range  => 26,
    search => 'c',
    tel    => '987654321',
    time   => '23:59:58',
    url    => 'http://example.com',
    week   => '2012-W17'
  }
)->status_is(200)->content_is(<<'EOF');
<form action="/text" method="POST">
  <input class="foo" name="color" type="color" value="#000000">
  <input class="foo" name="date" type="date" value="2012-12-13">
  <input class="foo" name="dt" type="datetime" value="2012-12-13T23:59:59Z">
  <input class="foo" name="email" type="email" value="spam@example.com">
  <input class="foo" name="month" type="month" value="2012-11">
  <input class="foo" name="number" type="number" value="25">
  <input class="foo" name="range" type="range" value="26">
  <input class="foo" name="search" type="search" value="c">
  <input class="foo" name="tel" type="tel" value="987654321">
  <input class="foo" name="time" type="time" value="23:59:58">
  <input class="foo" name="url" type="url" value="http://example.com">
  <input class="foo" name="week" type="week" value="2012-W17">
  <input type="submit" value="Ok">
</form>
EOF

# Checkboxes
$t->get_ok('/multibox')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input name="foo" type="checkbox" value="one">
  <input name="foo" type="checkbox" value="two">
  <input type="submit" value="Ok">
</form>
EOF

# Checkboxes with one value
$t->get_ok('/multibox?foo=two')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input name="foo" type="checkbox" value="one">
  <input checked name="foo" type="checkbox" value="two">
  <input type="submit" value="Ok">
</form>
EOF

# Checkboxes with one right and one wrong value
$t->get_ok('/multibox?foo=one&foo=three')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input checked name="foo" type="checkbox" value="one">
  <input name="foo" type="checkbox" value="two">
  <input type="submit" value="Ok">
</form>
EOF

# Checkboxes with wrong value
$t->get_ok('/multibox?foo=bar')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input name="foo" type="checkbox" value="one">
  <input name="foo" type="checkbox" value="two">
  <input type="submit" value="Ok">
</form>
EOF

# Checkboxes with two values
$t->get_ok('/multibox?foo=two&foo=one')->status_is(200)->content_is(<<EOF);
<form action="/multibox">
  <input checked name="foo" type="checkbox" value="one">
  <input checked name="foo" type="checkbox" value="two">
  <input type="submit" value="Ok">
</form>
EOF

# Advanced form with values
$t->get_ok('/form/lala?a=2&b=0&c=2&d=3&escaped=1%22+%222')->status_is(200)
  ->content_is(<<EOF);
<form action="/links" method="post">
  <input name="foo">
</form>
<form action="/form/24" method="post">
  <input name="foo" type="text">
  <input data-id="1" data-name="test" name="foo" type="text" value="1">
  <input data="ok" name="foo" type="text" value="1">
  <input name="foo" type="checkbox" value="1">
  <input checked name="a" type="checkbox" value="2">
  <input name="b" type="radio" value="1">
  <input checked name="b" type="radio" value="0">
  <input name="c" type="hidden" value="foo">
  <input name="d" type="file">
  <textarea cols="40" name="e" rows="50">
    default!
  </textarea>
  <textarea name="f"></textarea>
  <input name="g" type="password">
  <input id="foo" name="h" type="password">
  <input type="submit" value="Ok!">
  <input id="bar" type="submit" value="Ok too!">
</form>
<form action="/">
  <input name="foo">
</form>
<input name="escaped" value="1&quot; &quot;2">
<input name="a" value="2">
<input name="a" value="2">
EOF

# Advanced form with different values
$t->get_ok('/form/lala?c=b&d=3&e=4&f=<5')->status_is(200)->content_is(<<EOF);
<form action="/links" method="post">
  <input name="foo">
</form>
<form action="/form/24" method="post">
  <input name="foo" type="text">
  <input data-id="1" data-name="test" name="foo" type="text" value="1">
  <input data="ok" name="foo" type="text" value="1">
  <input name="foo" type="checkbox" value="1">
  <input name="a" type="checkbox" value="2">
  <input name="b" type="radio" value="1">
  <input name="b" type="radio" value="0">
  <input name="c" type="hidden" value="foo">
  <input name="d" type="file">
  <textarea cols="40" name="e" rows="50">4</textarea>
  <textarea name="f">&lt;5</textarea>
  <input name="g" type="password">
  <input id="foo" name="h" type="password">
  <input type="submit" value="Ok!">
  <input id="bar" type="submit" value="Ok too!">
</form>
<form action="/">
  <input name="foo">
</form>
<input name="escaped">
<input name="a">
<input name="a" value="c">
EOF

# Empty selection
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
    . "</select>\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option value="bar">bar</option>'
    . '<option value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" value="d">D</option>'
    . '<option value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="yada">'
    . '<optgroup class="x" label="test">'
    . '<option value="a">a</option>'
    . '<option value="b">b</option>'
    . '</optgroup>'
    . "</select>\n  "
    . '<input type="submit" value="Ok">'
    . "\n</form>\n");

# Selection with values
$t->put_ok('/selection?a=e&foo=bar&bar=baz&yada=b')->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option selected value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option value="g">g</option>'
    . "</select>\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option selected value="bar">bar</option>'
    . '<option value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" value="d">D</option>'
    . '<option selected value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="yada">'
    . '<optgroup class="x" label="test">'
    . '<option value="a">a</option>'
    . '<option selected value="b">b</option>'
    . '</optgroup>'
    . "</select>\n  "
    . '<input type="submit" value="Ok">'
    . "\n</form>\n");

# Selection with multiple values
$t->put_ok('/selection?foo=bar&a=e&foo=baz&bar=d&yada=a&yada=b')
  ->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option selected value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option value="g">g</option>'
    . "</select>\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option selected value="bar">bar</option>'
    . '<option selected value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" selected value="d">D</option>'
    . '<option value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="yada">'
    . '<optgroup class="x" label="test">'
    . '<option selected value="a">a</option>'
    . '<option selected value="b">b</option>'
    . '</optgroup>'
    . "</select>\n  "
    . '<input type="submit" value="Ok">'
    . "\n</form>\n");

# Selection with multiple values preselected
$t->put_ok('/selection?preselect=1')->status_is(200)
  ->content_is("<form action=\"/selection\">\n  "
    . '<select name="a">'
    . '<option selected value="b">b</option>'
    . '<optgroup label="c">'
    . '<option value="&lt;d">&lt;d</option>'
    . '<option value="e">E</option>'
    . '<option value="f">f</option>'
    . '</optgroup>'
    . '<option selected value="g">g</option>'
    . "</select>\n  "
    . '<select multiple="multiple" name="foo">'
    . '<option value="bar">bar</option>'
    . '<option value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="bar">'
    . '<option disabled="disabled" value="d">D</option>'
    . '<option value="baz">baz</option>'
    . "</select>\n  "
    . '<select name="yada">'
    . '<optgroup class="x" label="test">'
    . '<option value="a">a</option>'
    . '<option value="b">b</option>'
    . '</optgroup>'
    . "</select>\n  "
    . '<input type="submit" value="Ok">'
    . "\n</form>\n");

# Snowman form
$t->post_ok('/☃')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="foo">b&lt;a&gt;r</textarea>
  <input type="submit" value="☃">
</form>
EOF

# Snowman form with value
$t->post_ok('/☃?foo=ba<z')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="foo">ba&lt;z</textarea>
  <input type="submit" value="☃">
</form>
EOF

# Snowman form with empty value
$t->patch_ok('/☃?foo=')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="foo"></textarea>
  <input type="submit" value="☃">
</form>
EOF

# Snowman POST form
$t->post_ok('/no_snowman')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="POST">
  <textarea cols="40" name="bar"></textarea>
  <input type="submit" value="whatever">
</form>
EOF

# Form with alternative method
$t->post_ok('/no_snowman?foo=1')->status_is(200)->content_is(<<'EOF');
<form action="/%E2%98%83" method="PATCH">
  <textarea cols="40" name="bar"></textarea>
  <input type="submit" value="whatever">
</form>
EOF

done_testing();

__DATA__
@@ tags.html.ep
<%= tag 'foo' %>
<%= tag 'foo', bar => 'baz' %>
<%= tag 'foo', one => 't<wo', three => 'four' => begin %>Hello<% end %>
<%= tag 'div', data => {my_test_ID => 1, naMe => 'test'} => 'some content' %>
<%= tag 'div', data => 'bar' => 'some content' %>

@@ more_tags.html.ep
%= tag bar => 'b<a>z'
%= tag bar => 0
%= tag 'bar', class => 'test', 0
%= tag 'bar', class => 'test', ''

@@ small_tags.html.ep
%=t div => (id => '&lt;') => 'test & 123'
%=t div => begin
  %=t p => (id => 0) => 'just'
  %=t p => 0
%= end
%=t div => 'works'

@@ tags_with_error.html.ep
%= tag_with_error bar => 0
%= tag_with_error 'bar', class => 'test', 0
%= tag_with_error 'bar', (class => 'test') => begin
  0
%= end

@@ links.html.ep
<%= link_to 'Pa<th' => '/path' %>
<%= link_to 'http://example.com/', title => 'Foo', sub { 'Foo' } %>
<%= link_to '//example.com/' => begin %><foo>Example</foo><% end %>
<%= link_to Contact => Mojo::URL->new('mailto:sri@example.com') %>
<%= link_to Contact => 'mailto:sri@example.com' %>
<%= link_to Home => 'links' %>
<%= link_to Foo => 'form', {test => 23}, title => 'Foo' %>
<%= link_to form => {test => 23} => (title => 'Foo') => begin %>Foo<% end %>

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
  %= label_for foo => '<Foo>'
  %= text_field foo => 'bar'
  %= label_for bar => begin
    Bar<br>
  %= end
  %= text_field bar => 'baz', class => 'test'
  %= text_field yada => ''
  %= input_tag baz => 'yada', class => 'tset'
  %= submit_button
%= end

@@ text.html.ep
%= form_for text => begin
  %= color_field color => '#ffffff', class => 'foo'
  %= date_field date => '2012-12-12', class => 'foo'
  %= datetime_field dt => '2012-12-12T23:59:59Z', class => 'foo'
  %= email_field email => 'nospam@example.com', class => 'foo'
  %= month_field month => '2012-12', class => 'foo'
  %= number_field number => 23, class => 'foo'
  %= range_field range => 24, class => 'foo'
  %= search_field search => 'perl', class => 'foo'
  %= tel_field tel => '123456789', class => 'foo'
  %= time_field time => '23:59:59', class => 'foo'
  %= url_field url => 'http://mojolicio.us', class => 'foo'
  %= week_field week => '2012-W16', class => 'foo'
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
  %= text_field foo => 1, data => {id => 1, name => 'test'}
  %= text_field foo => 1, data => 'ok'
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
% param a => qw(b g) if param 'preselect';
%= form_for selection => begin
  %= select_field a => ['b', c(c => ['<d', [ E => 'e'], 'f']), 'g']
  %= select_field foo => [qw(bar baz)], multiple => 'multiple'
  %= select_field bar => [['D' => 'd', disabled => 'disabled'], 'baz']
  %= select_field yada => [c(test => [qw(a b)], class => 'x')];
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
  %= text_area 'bar', cols => 40
  %= submit_button 'whatever'
%= end
