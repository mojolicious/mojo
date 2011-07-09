#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

use Test::More tests => 94;

# "Why can't she just drink herself happy like a normal person?"
use_ok 'Mojo::HTML';

use Mojo::Util 'encode';

# Simple nesting with healing (tree structure)
my $html = Mojo::HTML->new->parse(<<EOF);
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</bar>works</foo>
EOF
is $html->tree->[0], 'root', 'right element';
is $html->tree->[1]->[0], 'tag', 'right element';
is $html->tree->[1]->[1], 'foo', 'right tag';
is_deeply $html->tree->[1]->[2], {}, 'empty attributes';
is $html->tree->[1]->[3], $html->tree, 'right parent';
is $html->tree->[1]->[4]->[0], 'tag', 'right element';
is $html->tree->[1]->[4]->[1], 'bar', 'right tag';
is_deeply $html->tree->[1]->[4]->[2], {a => 'b<c'}, 'right attributes';
is $html->tree->[1]->[4]->[3], $html->tree->[1], 'right parent';
is $html->tree->[1]->[4]->[4]->[0], 'text', 'right element';
is $html->tree->[1]->[4]->[4]->[1], 'ju',   'right text';
is $html->tree->[1]->[4]->[5]->[0], 'tag',  'right element';
is $html->tree->[1]->[4]->[5]->[1], 'baz',  'right tag';
is_deeply $html->tree->[1]->[4]->[5]->[2], {a23 => undef}, 'right attributes';
is $html->tree->[1]->[4]->[5]->[3], $html->tree->[1]->[4], 'right parent';
is $html->tree->[1]->[4]->[5]->[4]->[0], 'text', 'right element';
is $html->tree->[1]->[4]->[5]->[4]->[1], 's',    'right text';
is $html->tree->[1]->[4]->[5]->[5]->[0], 'tag',  'right element';
is $html->tree->[1]->[4]->[5]->[5]->[1], 'bazz', 'right tag';
is_deeply $html->tree->[1]->[4]->[5]->[5]->[2], {}, 'empty attributes';
is $html->tree->[1]->[4]->[5]->[5]->[3], $html->tree->[1]->[4]->[5],
  'right parent';
is $html->tree->[1]->[4]->[5]->[6]->[0], 'text', 'right element';
is $html->tree->[1]->[4]->[5]->[6]->[1], 't',    'right text';
is $html->tree->[1]->[5]->[0], 'text',  'right element';
is $html->tree->[1]->[5]->[1], 'works', 'right text';
is "$html", <<EOF, 'stringified right';
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</baz></bar>works</foo>
EOF

# Autoload children in XML mode
$html = Mojo::HTML->new(<<EOF, xml => 1);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $html->xml, 1, 'xml mode activated';
is $html->a->B->text, 'foo', 'right text';
is $html->a->B->c->[0]->text, 'bar', 'right text';
is $html->a->B->c->[1]->text, 'baz', 'right text';
is $html->a->B->c->[2], undef, 'no result';

# Autoload children in HTML mode
$html = Mojo::HTML->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $html->xml, undef, 'xml mode not activated';
is $html->a->b->text, 'foo', 'right text';
is $html->a->b->c->[0]->text, 'bar', 'right text';
is $html->a->b->c->[1]->text, 'baz', 'right text';
is $html->a->b->c->[2], undef, 'no result';

# Direct hash access to attributes in XML mode
$html = Mojo::HTML->new(<<EOF, xml => 1);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $html->xml, 1, 'xml mode activated';
is $html->a->{id}, 'one', 'right attribute';
is_deeply [sort keys %{$html->a}], ['id'], 'right attributes';
is $html->a->B->text, 'foo', 'right text';
is $html->a->B->{class}, 'two', 'right attribute';
is_deeply [sort keys %{$html->a->B}], [qw/class test/], 'right attributes';
is $html->a->B->c->[0]->text, 'bar', 'right text';
is $html->a->B->c->[0]->{id}, 'three', 'right attribute';
is_deeply [sort keys %{$html->a->B->c->[0]}], ['id'], 'right attributes';
is $html->a->B->c->[1]->text, 'baz', 'right text';
is $html->a->B->c->[1]->{ID}, 'four', 'right attribute';
is_deeply [sort keys %{$html->a->B->c->[1]}], ['ID'], 'right attributes';
is $html->a->B->c->[2], undef, 'no result';
is_deeply [keys %$html], [], 'root has no attributes';

# Direct hash access to attributes in HTML mode
$html = Mojo::HTML->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $html->xml, undef, 'xml mode not activated';
is $html->a->{id}, 'one', 'right attribute';
is_deeply [sort keys %{$html->a}], ['id'], 'right attributes';
is $html->a->b->text, 'foo', 'right text';
is $html->a->b->{class}, 'two', 'right attribute';
is_deeply [sort keys %{$html->a->b}], [qw/class test/], 'right attributes';
is $html->a->b->c->[0]->text, 'bar', 'right text';
is $html->a->b->c->[0]->{id}, 'three', 'right attribute';
is_deeply [sort keys %{$html->a->b->c->[0]}], ['id'], 'right attributes';
is $html->a->b->c->[1]->text, 'baz', 'right text';
is $html->a->b->c->[1]->{id}, 'four', 'right attribute';
is_deeply [sort keys %{$html->a->b->c->[1]}], ['id'], 'right attributes';
is $html->a->b->c->[2], undef, 'no result';
is_deeply [keys %$html], [], 'root has no attributes';

# Adding nodes
$html = Mojo::HTML->new->parse(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$html->ul->li->[0]->append('<p>A1</p>23');
is "$html", <<EOF, 'right result';
<ul>
    <li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$html->ul->li->[0]->prepend('24')->prepend('<div>A-1</div>25');
is "$html", <<EOF, 'right result';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
is $html->ul->div->text, 'A-1', 'right text';
is $html->ul->children('iv')->[0], undef, 'no result';
$html->prepend('l')->prepend('alal')->prepend('a');
is "$html", <<EOF, 'no change';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$html->append('lalala');
is "$html", <<EOF, 'no change';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$html->ul->div->append('works');
$html->div->append('works');
is "$html", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
$html->ul->li->[0]->prepend_content('A3<p>A2</p>')->prepend_content('A4');
is $html->ul->li->[0]->text, 'A4 A3 A', 'right text';
is "$html", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
$html->ul->li->[1]->append_content('<p>C2</p>C3')->append_content('♥');
is $html->ul->li->[1]->text, 'C C3 ♥', 'right text';
is "$html", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C<p>C2</p>C3♥</li>
</ul>
<div>D</div>works
EOF

# A collection of wonderful screwups
$html = Mojo::HTML->new->parse(<<'EOF');
<!doctype html>
<html lang="en">
  <head><title>Wonderful Screwups</title></head>
  <body id="screw-up">
    <div>
      <div class="ewww">
        <a href="/test" target='_blank'><img src="/test.png"></a>
        <a href='/real bad' screwup: http://localhost/bad' target='_blank'>
          <img src="/test2.png">
      </div>
      </mt:If>
    </div>
    <b>lalala</b>
  </body>
</html>
EOF
is $html->html->body->b->text, 'lalala', 'right text';
is $html->html->body->div->div->a->[0]->img->{src}, '/test.png',
  'right attribute';
is $html->html->body->div->div->a->[1]->img->{src}, '/test2.png',
  'right attribute';
is $html->html->body->div->div->a->[2], undef, 'no result';

# Modifying an XML document
$html = Mojo::HTML->new->parse(<<'EOF');
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest />
EOF
is $html->xml, 1, 'xml mode detected';
$html->XMLTest->replace_content('<Element />');
my $element = $html->XMLTest->Element;
is $element->type, 'Element', 'right type';
is $element->xml,  1,         'xml mode detected';
$element = $html->XMLTest->children->[0];
is $element->type, 'Element', 'right child';
is $element->parent->type, 'XMLTest', 'right parent';
is $element->root->xml,    1,         'xml mode detected';
$html->replace('<XMLTest2 />');
is $html->xml, undef, 'xml mode not detected';
is $html->children->[0], '<xmltest2 />', 'right result';
$html->replace(<<EOF);
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest3 />
EOF
is $html->xml, 1, 'xml mode detected';
is $html->children->[0], '<XMLTest3 />', 'right result';

# Unicode
my $unicode =
  qq/<html><div id="☃x">Snowman<\/div><div class="x ♥">Heart<\/div><\/html>/;
encode 'UTF-8', $unicode;
$html = Mojo::HTML->new(charset => 'UTF-8');
$html->parse($unicode);
is $html->html->div->[0]->{id}, '☃x', 'right attribute';
is $html->html->div->[0]->text, 'Snowman', 'right text';
is $html->html->div->[1]->{class}, 'x ♥', 'right attribute';
is $html->html->div->[1]->text, 'Heart', 'right text';
