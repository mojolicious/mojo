use Mojo::Base -strict;

use utf8;
use FindBin;
use lib "$FindBin::Bin/lib";

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 72;

# "Hey! Bite my glorious golden ass!"
use Test::Mojo;

my $t = Test::Mojo->new('MojoliciousTest');

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

