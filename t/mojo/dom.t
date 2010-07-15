#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use utf8;

use Test::More tests => 106;

# Homer gave me a kidney: it wasn't his, I didn't need it,
# and it came postage due- but I appreciated the gesture!
use_ok('Mojo::DOM');

my $dom = Mojo::DOM->new;

# Simple (basics)
$dom->parse('<div><div id="a">A</div><div id="b">B</div></div>');
is($dom->at('#b')->text, 'B', 'right text');
my @div;
$dom->search('div[id]')->each(sub { push @div, shift->text });
is_deeply(\@div, [qw/A B/], 'found all div elements with id');

# Simple nesting (tree structure)
$dom->parse(<<EOF);
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</bar>works</foo>
EOF
is($dom->tree->[0],      'root', 'right element');
is($dom->tree->[1]->[0], 'tag',  'right element');
is($dom->tree->[1]->[1], 'foo',  'right tag');
is_deeply($dom->tree->[1]->[2], {}, 'empty attributes');
is($dom->tree->[1]->[3],      $dom->tree, 'right parent');
is($dom->tree->[1]->[4]->[0], 'tag',      'right element');
is($dom->tree->[1]->[4]->[1], 'bar',      'right tag');
is_deeply($dom->tree->[1]->[4]->[2], {a => 'b<c'}, 'right attributes');
is($dom->tree->[1]->[4]->[3],      $dom->tree->[1], 'right parent');
is($dom->tree->[1]->[4]->[4]->[0], 'text',          'right element');
is($dom->tree->[1]->[4]->[4]->[1], 'ju',            'right text');
is($dom->tree->[1]->[4]->[5]->[0], 'tag',           'right element');
is($dom->tree->[1]->[4]->[5]->[1], 'baz',           'right tag');
is_deeply($dom->tree->[1]->[4]->[5]->[2], {a23 => undef}, 'right attributes');
is($dom->tree->[1]->[4]->[5]->[3], $dom->tree->[1]->[4], 'right parent');
is($dom->tree->[1]->[4]->[6]->[0], 'text',               'right element');
is($dom->tree->[1]->[4]->[6]->[1], 's',                  'right text');
is($dom->tree->[1]->[4]->[7]->[0], 'tag',                'right element');
is($dom->tree->[1]->[4]->[7]->[1], 'bazz',               'right tag');
is_deeply($dom->tree->[1]->[4]->[7]->[2], {}, 'empty attributes');
is($dom->tree->[1]->[4]->[7]->[3], $dom->tree->[1]->[4], 'right parent');
is($dom->tree->[1]->[4]->[8]->[0], 'text',               'right element');
is($dom->tree->[1]->[4]->[8]->[1], 't',                  'right text');
is($dom->tree->[1]->[5]->[0],      'text',               'right element');
is($dom->tree->[1]->[5]->[1],      'works',              'right text');
is("$dom",                         <<EOF,                'stringified right');
<foo><bar a="b&lt;c">ju<baz a23 />s<bazz />t</bar>works</foo>
EOF

# A bit of everything (basic navigation)
$dom->parse(<<EOF);
<!doctype foo>
<foo bar="ba&lt;z">
  test
  <simple class="working">easy</simple>
  <test foo="bar" id="test" />
  <!-- lala -->
  works well
  <![CDATA[ yada yada]]>
  <?boom lalalala ?>
  <a little bit broken>
  < very broken
  <br />
  more text
</foo>
EOF
is($dom->tree->[1]->[0], 'doctype', 'right element');
is($dom->tree->[1]->[1], ' foo',    'right doctype');
is("$dom",               <<EOF,     'stringified right');
<!DOCTYPE foo>
<foo bar="ba&lt;z">
  test
  <simple class="working">easy</simple>
  <test foo="bar" id="test" />
  <!-- lala -->
  works well
  <![CDATA[ yada yada]]>
  <?boom lalalala ?>
  <a bit broken little />
  <very broken />
  more text
</foo>
EOF
my $simple = $dom->at('foo simple.working[class^="wor"]');
like($simple->parent->all_text,
    qr/test\s+works\s+well\s+yada\s+yada\s+more\s+text/);
is($simple->name,                        'simple',  'right name');
is($simple->attributes->{class},         'working', 'right class attribute');
is($simple->text,                        'easy',    'right text');
is($simple->parent->name,                'foo',     'right parent name');
is($simple->parent->attributes->{bar},   'ba<z',    'right parent attribute');
is($simple->parent->children->[1]->name, 'test',    'right sibling');
is( $simple->to_xml,
    '<simple class="working">easy</simple>',
    'stringified right'
);
is($dom->at('test#test')->name,         'test',   'right name');
is($dom->at('[class$="ing"]')->name,    'simple', 'right name');
is($dom->at('[class="working"]')->name, 'simple', 'right name');

# Deep nesting (parent combinator)
$dom->parse(<<EOF);
<html>
  <head>
    <title>Foo</title>
  </head>
  <body>
    <div id="container">
      <div id="header">
        <div id="logo">Hello World</div>
        <div id="buttons">
          <p id="foo">Foo</p>
        </div>
      </div>
      <form>
        <div id="buttons">
          <p id="bar">Bar</p>
        </div>
      </form>
      <div id="content">More stuff</div>
    </div>
  </body>
</html>
EOF
my $p = $dom->search('body > #container > div p[id]');
is($p->[0]->attributes->{id}, 'foo', 'right id attribute');
is($p->[1],                   undef, 'no second result');
my @p;
@div = ();
$dom->search('div')->each(sub { push @div, $_->attributes->{id} })
  ->search('p')->each(sub { push @p, $_->attributes->{id} });
is_deeply(\@p, [qw/foo bar/], 'found all p elements');
my $ids = [qw/container header content logo buttons buttons/];
is_deeply(\@div, $ids, 'found all div elements');

# Script tag
$dom->parse(<<EOF);
<script type="text/javascript" charset="utf-8">alert('lalala');</script>
EOF
is($dom->at('script')->text, "alert('lalala');", 'right script content');

# HTML5 (unquoted values)
$dom->parse(qq/<div id = test foo ="bar" class=tset>works<\/div>/);
is($dom->at('#test')->text,       'works', 'right text');
is($dom->at('div')->text,         'works', 'right text');
is($dom->at('[foo="bar"]')->text, 'works', 'right text');
is($dom->at('[foo="ba"]'),        undef,   'no result');
is($dom->at('.tset')->text,       'works', 'right text');

# HTML1 (single quotes, uppercase tags and whitespace in attributes)
$dom->parse(qq/<DIV id = 'test' foo ='bar' class= "tset">works<\/DIV>/);
is($dom->at('#test')->text,       'works', 'right text');
is($dom->at('div')->text,         'works', 'right text');
is($dom->at('[foo="bar"]')->text, 'works', 'right text');
is($dom->at('[foo="ba"]'),        undef,   'no result');
is($dom->at('.tset')->text,       'works', 'right text');

# Already decoded unicode snowman and quotes in selector
$dom->charset(undef)->parse('<div id="sno&quot;wman">☃</div>');
is($dom->at('[id="sno\"wman"]')->text, '☃', 'right text');

# Unicode and escaped selectors
$dom->parse(
    qq/<p><div id="☃x">Snowman<\/div><div class="x ♥">Heart<\/div><\/p>/);
is($dom->at("#\\\n\\002603x")->text,               'Snowman', 'right text');
is($dom->at('#\\2603 x')->text,                    'Snowman', 'right text');
is($dom->at("#\\\n\\2603 x")->text,                'Snowman', 'right text');
is($dom->at(qq/[id="\\\n\\2603 x"]/)->text,        'Snowman', 'right text');
is($dom->at(qq/[id="\\\n\\002603x"]/)->text,       'Snowman', 'right text');
is($dom->at(qq/[id="\\\\2603 x"]/)->text,          'Snowman', 'right text');
is($dom->at("p #\\\n\\002603x")->text,             'Snowman', 'right text');
is($dom->at('p #\\2603 x')->text,                  'Snowman', 'right text');
is($dom->at("p #\\\n\\2603 x")->text,              'Snowman', 'right text');
is($dom->at(qq/p [id="\\\n\\2603 x"]/)->text,      'Snowman', 'right text');
is($dom->at(qq/p [id="\\\n\\002603x"]/)->text,     'Snowman', 'right text');
is($dom->at(qq/p [id="\\\\2603 x"]/)->text,        'Snowman', 'right text');
is($dom->at('#☃x')->text,                        'Snowman', 'right text');
is($dom->at('div#☃x')->text,                     'Snowman', 'right text');
is($dom->at('p div#☃x')->text,                   'Snowman', 'right text');
is($dom->at('[id^="☃"]')->text,                  'Snowman', 'right text');
is($dom->at('div[id^="☃"]')->text,               'Snowman', 'right text');
is($dom->at('p div[id^="☃"]')->text,             'Snowman', 'right text');
is($dom->at('p > div[id^="☃"]')->text,           'Snowman', 'right text');
is($dom->at(".\\\n\\002665")->text,                'Heart',   'right text');
is($dom->at('.\\2665')->text,                      'Heart',   'right text');
is($dom->at("p .\\\n\\002665")->text,              'Heart',   'right text');
is($dom->at('p .\\2665')->text,                    'Heart',   'right text');
is($dom->at(qq/p [class\$="\\\n\\002665"]/)->text, 'Heart',   'right text');
is($dom->at(qq/p [class\$="\\2665"]/)->text,       'Heart',   'right text');
is($dom->at(qq/[class\$="\\\n\\002665"]/)->text,   'Heart',   'right text');
is($dom->at(qq/[class\$="\\2665"]/)->text,         'Heart',   'right text');
is($dom->at('.x')->text,                           'Heart',   'right text');
is($dom->at('p .x')->text,                         'Heart',   'right text');
is($dom->at('.♥')->text,                         'Heart',   'right text');
is($dom->at('p .♥')->text,                       'Heart',   'right text');
is($dom->at('div.♥')->text,                      'Heart',   'right text');
is($dom->at('p div.♥')->text,                    'Heart',   'right text');
is($dom->at('[class$="♥"]')->text,               'Heart',   'right text');
is($dom->at('div[class$="♥"]')->text,            'Heart',   'right text');
is($dom->at('p div[class$="♥"]')->text,          'Heart',   'right text');
is($dom->at('p > div[class$="♥"]')->text,        'Heart',   'right text');

# Looks remotely like HTML
$dom->parse('<!DOCTYPE H "-/W/D HT 4/E">☃<title class=test>♥</title>☃');
is($dom->at('title')->text, '♥', 'right text');
is($dom->at('*')->text,     '♥', 'right text');
is($dom->at('.test')->text, '♥', 'right text');

# Replace elements
$dom->parse('<div>foo<p>lalala</p>bar</div>');
$dom->at('p')->replace('<foo>bar</foo>');
is("$dom", '<div>foo<foo>bar</foo>bar</div>', 'right text');
$dom->at('foo')->replace(Mojo::DOM->new->parse('text'));
is("$dom", '<div>footextbar</div>', 'right text');
$dom->parse('<div>foo</div><div>bar</div>');
$dom->search('div')->each(sub { shift->replace('<p>test</p>') });
is("$dom", '<p>test</p><p>test</p>', 'right text');

# Replace element content
$dom->parse('<div>foo<p>lalala</p>bar</div>');
$dom->at('p')->replace_content('bar');
is("$dom", '<div>foo<p>bar</p>bar</div>', 'right text');
$dom->at('p')->replace_content(Mojo::DOM->new->parse('text'));
is("$dom", '<div>foo<p>text</p>bar</div>', 'right text');
$dom->parse('<div>foo</div><div>bar</div>');
$dom->search('div')->each(sub { shift->replace_content('<p>test</p>') });
is("$dom", '<div><p>test</p></div><div><p>test</p></div>', 'right text');
$dom->parse('<div><p id="foo" /></div>');
$dom->at('p')->replace_content('♥');
is("$dom", '<div><p id="foo">♥</p></div>', 'right text');
