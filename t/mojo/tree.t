#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

use Test::More tests => 94;

# "Why can't she just drink herself happy like a normal person?"
use_ok 'Mojo::Tree';

use Mojo::Util 'encode';

# Simple nesting with healing (tree structure)
my $t = Mojo::Tree->new->parse(<<EOF);
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</bar>works</foo>
EOF
is $t->tree->[0], 'root', 'right element';
is $t->tree->[1]->[0], 'tag', 'right element';
is $t->tree->[1]->[1], 'foo', 'right tag';
is_deeply $t->tree->[1]->[2], {}, 'empty attributes';
is $t->tree->[1]->[3], $t->tree, 'right parent';
is $t->tree->[1]->[4]->[0], 'tag', 'right element';
is $t->tree->[1]->[4]->[1], 'bar', 'right tag';
is_deeply $t->tree->[1]->[4]->[2], {a => 'b<c'}, 'right attributes';
is $t->tree->[1]->[4]->[3], $t->tree->[1], 'right parent';
is $t->tree->[1]->[4]->[4]->[0], 'text', 'right element';
is $t->tree->[1]->[4]->[4]->[1], 'ju',   'right text';
is $t->tree->[1]->[4]->[5]->[0], 'tag',  'right element';
is $t->tree->[1]->[4]->[5]->[1], 'baz',  'right tag';
is_deeply $t->tree->[1]->[4]->[5]->[2], {a23 => undef}, 'right attributes';
is $t->tree->[1]->[4]->[5]->[3], $t->tree->[1]->[4], 'right parent';
is $t->tree->[1]->[4]->[5]->[4]->[0], 'text', 'right element';
is $t->tree->[1]->[4]->[5]->[4]->[1], 's',    'right text';
is $t->tree->[1]->[4]->[5]->[5]->[0], 'tag',  'right element';
is $t->tree->[1]->[4]->[5]->[5]->[1], 'bazz', 'right tag';
is_deeply $t->tree->[1]->[4]->[5]->[5]->[2], {}, 'empty attributes';
is $t->tree->[1]->[4]->[5]->[5]->[3], $t->tree->[1]->[4]->[5], 'right parent';
is $t->tree->[1]->[4]->[5]->[6]->[0], 'text', 'right element';
is $t->tree->[1]->[4]->[5]->[6]->[1], 't',    'right text';
is $t->tree->[1]->[5]->[0], 'text',  'right element';
is $t->tree->[1]->[5]->[1], 'works', 'right text';
is "$t", <<EOF, 'stringified right';
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</baz></bar>works</foo>
EOF

# Autoload children in XML mode
$t = Mojo::Tree->new(<<EOF, xml => 1);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $t->xml, 1, 'xml mode activated';
is $t->a->B->text, 'foo', 'right text';
is $t->a->B->c->[0]->text, 'bar', 'right text';
is $t->a->B->c->[1]->text, 'baz', 'right text';
is $t->a->B->c->[2], undef, 'no result';

# Autoload children in HTML mode
$t = Mojo::Tree->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $t->xml, undef, 'xml mode not activated';
is $t->a->b->text, 'foo', 'right text';
is $t->a->b->c->[0]->text, 'bar', 'right text';
is $t->a->b->c->[1]->text, 'baz', 'right text';
is $t->a->b->c->[2], undef, 'no result';

# Direct hash access to attributes in XML mode
$t = Mojo::Tree->new(<<EOF, xml => 1);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $t->xml, 1, 'xml mode activated';
is $t->a->{id}, 'one', 'right attribute';
is_deeply [sort keys %{$t->a}], ['id'], 'right attributes';
is $t->a->B->text, 'foo', 'right text';
is $t->a->B->{class}, 'two', 'right attribute';
is_deeply [sort keys %{$t->a->B}], [qw/class test/], 'right attributes';
is $t->a->B->c->[0]->text, 'bar', 'right text';
is $t->a->B->c->[0]->{id}, 'three', 'right attribute';
is_deeply [sort keys %{$t->a->B->c->[0]}], ['id'], 'right attributes';
is $t->a->B->c->[1]->text, 'baz', 'right text';
is $t->a->B->c->[1]->{ID}, 'four', 'right attribute';
is_deeply [sort keys %{$t->a->B->c->[1]}], ['ID'], 'right attributes';
is $t->a->B->c->[2], undef, 'no result';
is_deeply [keys %$t], [], 'root has no attributes';

# Direct hash access to attributes in HTML mode
$t = Mojo::Tree->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
is $t->xml, undef, 'xml mode not activated';
is $t->a->{id}, 'one', 'right attribute';
is_deeply [sort keys %{$t->a}], ['id'], 'right attributes';
is $t->a->b->text, 'foo', 'right text';
is $t->a->b->{class}, 'two', 'right attribute';
is_deeply [sort keys %{$t->a->b}], [qw/class test/], 'right attributes';
is $t->a->b->c->[0]->text, 'bar', 'right text';
is $t->a->b->c->[0]->{id}, 'three', 'right attribute';
is_deeply [sort keys %{$t->a->b->c->[0]}], ['id'], 'right attributes';
is $t->a->b->c->[1]->text, 'baz', 'right text';
is $t->a->b->c->[1]->{id}, 'four', 'right attribute';
is_deeply [sort keys %{$t->a->b->c->[1]}], ['id'], 'right attributes';
is $t->a->b->c->[2], undef, 'no result';
is_deeply [keys %$t], [], 'root has no attributes';

# Adding nodes
$t = Mojo::Tree->new->parse(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$t->ul->li->[0]->append('<p>A1</p>23');
is "$t", <<EOF, 'right result';
<ul>
    <li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$t->ul->li->[0]->prepend('24')->prepend('<div>A-1</div>25');
is "$t", <<EOF, 'right result';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
is $t->ul->div->text, 'A-1', 'right text';
is $t->ul->children('iv')->[0], undef, 'no result';
$t->prepend('l')->prepend('alal')->prepend('a');
is "$t", <<EOF, 'no change';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$t->append('lalala');
is "$t", <<EOF, 'no change';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
$t->ul->div->append('works');
$t->div->append('works');
is "$t", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
$t->ul->li->[0]->prepend_content('A3<p>A2</p>')->prepend_content('A4');
is $t->ul->li->[0]->text, 'A4 A3 A', 'right text';
is "$t", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
$t->ul->li->[1]->append_content('<p>C2</p>C3')->append_content('♥');
is $t->ul->li->[1]->text, 'C C3 ♥', 'right text';
is "$t", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C<p>C2</p>C3♥</li>
</ul>
<div>D</div>works
EOF

# A collection of wonderful screwups
$t = Mojo::Tree->new->parse(<<'EOF');
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
is $t->html->body->b->text, 'lalala', 'right text';
is $t->html->body->div->div->a->[0]->img->{src}, '/test.png',
  'right attribute';
is $t->html->body->div->div->a->[1]->img->{src}, '/test2.png',
  'right attribute';
is $t->html->body->div->div->a->[2], undef, 'no result';

# Modifying an XML document
$t = Mojo::Tree->new->parse(<<'EOF');
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest />
EOF
is $t->xml, 1, 'xml mode detected';
$t->XMLTest->replace_content('<Element />');
my $element = $t->XMLTest->Element;
is $element->type, 'Element', 'right type';
is $element->xml,  1,         'xml mode detected';
$element = $t->XMLTest->children->[0];
is $element->type, 'Element', 'right child';
is $element->parent->type, 'XMLTest', 'right parent';
is $element->root->xml,    1,         'xml mode detected';
$t->replace('<XMLTest2 />');
is $t->xml, undef, 'xml mode not detected';
is $t->children->[0], '<xmltest2 />', 'right result';
$t->replace(<<EOF);
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest3 />
EOF
is $t->xml, 1, 'xml mode detected';
is $t->children->[0], '<XMLTest3 />', 'right result';

# Unicode
my $unicode =
  qq/<html><div id="☃x">Snowman<\/div><div class="x ♥">Heart<\/div><\/html>/;
encode 'UTF-8', $unicode;
$t = Mojo::Tree->new(charset => 'UTF-8');
$t->parse($unicode);
is $t->html->div->[0]->{id}, '☃x', 'right attribute';
is $t->html->div->[0]->text, 'Snowman', 'right text';
is $t->html->div->[1]->{class}, 'x ♥', 'right attribute';
is $t->html->div->[1]->text, 'Heart', 'right text';
