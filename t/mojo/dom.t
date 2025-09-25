use Mojo::Base -strict;

use Test::More;
use Mojo::DOM;
use Mojo::DOM::HTML qw(tag_to_html);

subtest 'Empty' => sub {
  is(Mojo::DOM->new,                     '',    'right result');
  is(Mojo::DOM->new(''),                 '',    'right result');
  is(Mojo::DOM->new->parse(''),          '',    'right result');
  is(Mojo::DOM->new->at('p'),            undef, 'no result');
  is(Mojo::DOM->new->append_content(''), '',    'right result');
  is(Mojo::DOM->new->all_text,           '',    'right result');
};

subtest 'Simple (basics)' => sub {
  my $dom = Mojo::DOM->new('<div><div FOO="0" id="a">A</div><div id="b">B</div></div>');
  is $dom->at('#b')->text, 'B', 'right text';
  my @div;
  push @div, $dom->find('div[id]')->map('text')->each;
  is_deeply \@div, [qw(A B)], 'found all div elements with id';
  @div = ();
  $dom->find('div[id]')->each(sub { push @div, $_->text });
  is_deeply \@div, [qw(A B)], 'found all div elements with id';
  is $dom->at('#a')->attr('foo'), 0,                                                           'right attribute';
  is $dom->at('#a')->attr->{foo}, 0,                                                           'right attribute';
  is "$dom",                      '<div><div foo="0" id="a">A</div><div id="b">B</div></div>', 'right result';
};

subtest 'Tap into method chain' => sub {
  my $dom = Mojo::DOM->new->parse('<div id="a">A</div><div id="b">B</div>');
  is_deeply [$dom->find('[id]')->map(attr => 'id')->each], [qw(a b)], 'right result';
  is $dom->tap(sub { $_->at('#b')->remove }), '<div id="a">A</div>', 'right result';
};

subtest 'Build tree from scratch' => sub {
  is(Mojo::DOM->new->append_content('<p>')->at('p')->append_content('0')->text, '0', 'right text');
};

subtest 'Simple nesting with healing (tree structure)' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<foo><bar a="b&lt;c">ju<baz a23>s<bazz />t</bar>works</foo>
EOF
  is $dom->tree->[0],    'root', 'right type';
  is $dom->tree->[1][0], 'tag',  'right type';
  is $dom->tree->[1][1], 'foo',  'right tag';
  is_deeply $dom->tree->[1][2], {}, 'empty attributes';
  is $dom->tree->[1][3],    $dom->tree, 'right parent';
  is $dom->tree->[1][4][0], 'tag',      'right type';
  is $dom->tree->[1][4][1], 'bar',      'right tag';
  is_deeply $dom->tree->[1][4][2], {a => 'b<c'}, 'right attributes';
  is $dom->tree->[1][4][3],    $dom->tree->[1],    'right parent';
  is $dom->tree->[1][4][4][0], 'text',             'right type';
  is $dom->tree->[1][4][4][1], 'ju',               'right text';
  is $dom->tree->[1][4][4][2], $dom->tree->[1][4], 'right parent';
  is $dom->tree->[1][4][5][0], 'tag',              'right type';
  is $dom->tree->[1][4][5][1], 'baz',              'right tag';
  is_deeply $dom->tree->[1][4][5][2], {a23 => undef}, 'right attributes';
  is $dom->tree->[1][4][5][3],    $dom->tree->[1][4],    'right parent';
  is $dom->tree->[1][4][5][4][0], 'text',                'right type';
  is $dom->tree->[1][4][5][4][1], 's',                   'right text';
  is $dom->tree->[1][4][5][4][2], $dom->tree->[1][4][5], 'right parent';
  is $dom->tree->[1][4][5][5][0], 'tag',                 'right type';
  is $dom->tree->[1][4][5][5][1], 'bazz',                'right tag';
  is_deeply $dom->tree->[1][4][5][5][2], {}, 'empty attributes';
  is $dom->tree->[1][4][5][5][3], $dom->tree->[1][4][5], 'right parent';
  is $dom->tree->[1][4][5][6][0], 'text',                'right type';
  is $dom->tree->[1][4][5][6][1], 't',                   'right text';
  is $dom->tree->[1][4][5][6][2], $dom->tree->[1][4][5], 'right parent';
  is $dom->tree->[1][5][0],       'text',                'right type';
  is $dom->tree->[1][5][1],       'works',               'right text';
  is $dom->tree->[1][5][2],       $dom->tree->[1],       'right parent';
  is "$dom",                      <<EOF,                 'right result';
<foo><bar a="b&lt;c">ju<baz a23>s<bazz></bazz>t</baz></bar>works</foo>
EOF
};

subtest 'Select based on parent' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
  <body>
    <div>test1</div>
    <div><div>test2</div></div>
  <body>
EOF
  is $dom->find('body > div')->[0]->text,       'test1', 'right text';
  is $dom->find('body > div')->[1]->text,       '',      'no content';
  is $dom->find('body > div')->[2],             undef,   'no result';
  is $dom->find('body > div')->size,            2,       'right number of elements';
  is $dom->find('body > div > div')->[0]->text, 'test2', 'right text';
  is $dom->find('body > div > div')->[1],       undef,   'no result';
  is $dom->find('body > div > div')->size,      1,       'right number of elements';
};

subtest 'A bit of everything (basic navigation)' => sub {
  my $dom = Mojo::DOM->new->parse(<<EOF);
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
  ok !$dom->xml, 'XML mode not detected';
  is $dom->tag,                             undef,     'no tag';
  is $dom->attr('foo'),                     undef,     'no attribute';
  is $dom->attr(foo => 'bar')->attr('foo'), undef,     'no attribute';
  is $dom->tree->[1][0],                    'doctype', 'right type';
  is $dom->tree->[1][1],                    ' foo',    'right doctype';
  is "$dom",                                <<EOF,     'right result';
<!DOCTYPE foo>
<foo bar="ba&lt;z">
  test
  <simple class="working">easy</simple>
  <test foo="bar" id="test"></test>
  <!-- lala -->
  works well
  <![CDATA[ yada yada]]>
  <?boom lalalala ?>
  <a bit broken little>
  &lt; very broken
  <br>
  more text
</a></foo>
EOF
  my $simple = $dom->at('foo simple.working[class^="wor"]');
  is $simple->parent->all_text,
    "\n  test\n  easy\n  \n  \n  works well\n   yada yada\n" . "  \n  \n  < very broken\n  \n  more text\n",
    'right text';
  is $simple->tag,                        'simple',                                'right tag';
  is $simple->attr('class'),              'working',                               'right class attribute';
  is $simple->text,                       'easy',                                  'right text';
  is $simple->parent->tag,                'foo',                                   'right parent tag';
  is $simple->parent->attr->{bar},        'ba<z',                                  'right parent attribute';
  is $simple->parent->children->[1]->tag, 'test',                                  'right sibling';
  is $simple->to_string,                  '<simple class="working">easy</simple>', 'stringified right';
  $simple->parent->attr(bar => 'baz')->attr({this => 'works', too => 'yea'});
  is $simple->parent->attr('bar'),              'baz',    'right parent attribute';
  is $simple->parent->attr('this'),             'works',  'right parent attribute';
  is $simple->parent->attr('too'),              'yea',    'right parent attribute';
  is $dom->at('test#test')->tag,                'test',   'right tag';
  is $dom->at('[class$="ing"]')->tag,           'simple', 'right tag';
  is $dom->at('[class="working"]')->tag,        'simple', 'right tag';
  is $dom->at('[class$=ing]')->tag,             'simple', 'right tag';
  is $dom->at('[class=working][class]')->tag,   'simple', 'right tag';
  is $dom->at('foo > simple')->next->tag,       'test',   'right tag';
  is $dom->at('foo > simple')->next->next->tag, 'a',      'right tag';
  is $dom->at('foo > test')->previous->tag,     'simple', 'right tag';
  is $dom->next,                                undef,    'no siblings';
  is $dom->previous,                            undef,    'no siblings';
  is $dom->at('foo > a')->next,                 undef,    'no next sibling';
  is $dom->at('foo > simple')->previous,        undef,    'no previous sibling';
  is_deeply [$dom->at('simple')->ancestors->map('tag')->each], ['foo'], 'right results';
  ok !$dom->at('simple')->ancestors->first->xml, 'XML mode not active';
};

subtest 'Nodes' => sub {
  my $dom = Mojo::DOM->new('<!DOCTYPE before><p>test<![CDATA[123]]><!-- 456 --></p><?after?>');
  is $dom->at('p')->preceding_nodes->first->content,                          ' before', 'right content';
  is $dom->at('p')->preceding_nodes->size,                                    1,         'right number of nodes';
  is $dom->at('p')->child_nodes->last->preceding_nodes->first->content,       'test',    'right content';
  is $dom->at('p')->child_nodes->last->preceding_nodes->last->content,        '123',     'right content';
  is $dom->at('p')->child_nodes->last->preceding_nodes->size,                 2,         'right number of nodes';
  is $dom->preceding_nodes->size,                                             0,         'no preceding nodes';
  is $dom->at('p')->following_nodes->first->content,                          'after',   'right content';
  is $dom->at('p')->following_nodes->size,                                    1,         'right number of nodes';
  is $dom->child_nodes->first->following_nodes->first->tag,                   'p',       'right tag';
  is $dom->child_nodes->first->following_nodes->last->content,                'after',   'right content';
  is $dom->child_nodes->first->following_nodes->size,                         2,         'right number of nodes';
  is $dom->following_nodes->size,                                             0,         'no following nodes';
  is $dom->at('p')->previous_node->content,                                   ' before', 'right content';
  is $dom->at('p')->previous_node->previous_node,                             undef,     'no more siblings';
  is $dom->at('p')->next_node->content,                                       'after',   'right content';
  is $dom->at('p')->next_node->next_node,                                     undef,     'no more siblings';
  is $dom->at('p')->child_nodes->last->previous_node->previous_node->content, 'test',    'right content';
  is $dom->at('p')->child_nodes->first->next_node->next_node->content,        ' 456 ',   'right content';
  is $dom->descendant_nodes->[0]->type,                                       'doctype', 'right type';
  is $dom->descendant_nodes->[0]->content,                                    ' before', 'right content';
  is $dom->descendant_nodes->[0],                                             '<!DOCTYPE before>', 'right content';
  is $dom->descendant_nodes->[1]->tag,                                        'p',                 'right tag';
  is $dom->descendant_nodes->[2]->type,                                       'text',              'right type';
  is $dom->descendant_nodes->[2]->content,                                    'test',              'right content';
  is $dom->descendant_nodes->[5]->type,                                       'pi',                'right type';
  is $dom->descendant_nodes->[5]->content,                                    'after',             'right content';
  is $dom->at('p')->descendant_nodes->[0]->type,                              'text',              'right type';
  is $dom->at('p')->descendant_nodes->[0]->content,                           'test',              'right type';
  is $dom->at('p')->descendant_nodes->last->type,                             'comment',           'right type';
  is $dom->at('p')->descendant_nodes->last->content,                          ' 456 ',             'right type';
  is $dom->child_nodes->[1]->child_nodes->first->parent->tag,                 'p',                 'right tag';
  is $dom->child_nodes->[1]->child_nodes->first->content,                     'test',              'right content';
  is $dom->child_nodes->[1]->child_nodes->first,                              'test',              'right content';
  is $dom->at('p')->child_nodes->first->type,                                 'text',              'right type';
  is $dom->at('p')->child_nodes->first->remove->tag,                          'p',                 'right tag';
  is $dom->at('p')->child_nodes->first->type,                                 'cdata',             'right type';
  is $dom->at('p')->child_nodes->first->content,                              '123',               'right content';
  is $dom->at('p')->child_nodes->[1]->type,                                   'comment',           'right type';
  is $dom->at('p')->child_nodes->[1]->content,                                ' 456 ',             'right content';
  is $dom->[0]->type,                                                         'doctype',           'right type';
  is $dom->[0]->content,                                                      ' before',           'right content';
  is $dom->child_nodes->[2]->type,                                            'pi',                'right type';
  is $dom->child_nodes->[2]->content,                                         'after',             'right content';
  is $dom->child_nodes->first->content(' again')->content,                    ' again',            'right content';
  is $dom->child_nodes->grep(sub { $_->type eq 'pi' })->map('remove')->first->type, 'root',        'right type';
  is "$dom", '<!DOCTYPE again><p><![CDATA[123]]><!-- 456 --></p>',                                 'right result';
};

subtest 'Modify nodes' => sub {
  my $dom = Mojo::DOM->new('<script>la<la>la</script>');
  is $dom->at('script')->type,         'tag',                                                          'right type';
  is $dom->at('script')->[0]->type,    'raw',                                                          'right type';
  is $dom->at('script')->[0]->content, 'la<la>la',                                                     'right content';
  is "$dom",                           '<script>la<la>la</script>',                                    'right result';
  is $dom->at('script')->child_nodes->first->replace('a<b>c</b>1<b>d</b>')->tag, 'script',             'right tag';
  is "$dom",                                                  '<script>a<b>c</b>1<b>d</b></script>',   'right result';
  is $dom->at('b')->child_nodes->first->append('e')->content, 'c',                                     'right content';
  is $dom->at('b')->child_nodes->first->prepend('f')->type,   'text',                                  'right type';
  is "$dom",                                                  '<script>a<b>fce</b>1<b>d</b></script>', 'right result';
  is $dom->at('script')->child_nodes->first->following->first->tag, 'b',                               'right tag';
  is $dom->at('script')->child_nodes->first->next->content,         'fce',                             'right content';
  is $dom->at('script')->child_nodes->first->previous,              undef,                             'no siblings';
  is $dom->at('script')->child_nodes->[2]->previous->content,       'fce',                             'right content';
  is $dom->at('b')->child_nodes->[1]->next,                         undef,                             'no siblings';
  is $dom->at('script')->child_nodes->first->wrap('<i>:)</i>')->root, '<script><i>:)a</i><b>fce</b>1<b>d</b></script>',
    'right result';
  is $dom->at('i')->child_nodes->first->wrap_content('<b></b>')->root,
    '<script><i>:)a</i><b>fce</b>1<b>d</b></script>', 'no changes';
  is $dom->at('i')->child_nodes->first->wrap('<b></b>')->root, '<script><i><b>:)</b>a</i><b>fce</b>1<b>d</b></script>',
    'right result';
  is $dom->at('b')->child_nodes->first->ancestors->map('tag')->join(','), 'b,i,script',             'right result';
  is $dom->at('b')->child_nodes->first->append_content('g')->content,     ':)g',                    'right content';
  is $dom->at('b')->child_nodes->first->prepend_content('h')->content,    'h:)g',                   'right content';
  is "$dom", '<script><i><b>h:)g</b>a</i><b>fce</b>1<b>d</b></script>',                             'right result';
  is $dom->at('script > b:last-of-type')->append('<!--y-->')->following_nodes->first->content, 'y', 'right content';
  is $dom->at('i')->prepend('z')->preceding_nodes->first->content,                             'z', 'right content';
  is $dom->at('i')->following->last->text,                                                     'd', 'right text';
  is $dom->at('i')->following->size,                                  2,         'right number of following elements';
  is $dom->at('i')->following('b:last-of-type')->first->text,         'd',       'right text';
  is $dom->at('i')->following('b:last-of-type')->size,                1,         'right number of following elements';
  is $dom->following->size,                                           0,         'no following elements';
  is $dom->at('script > b:last-of-type')->preceding->first->tag,      'i',       'right tag';
  is $dom->at('script > b:last-of-type')->preceding->size,            2,         'right number of preceding elements';
  is $dom->at('script > b:last-of-type')->preceding('b')->first->tag, 'b',       'right tag';
  is $dom->at('script > b:last-of-type')->preceding('b')->size,       1,         'right number of preceding elements';
  is $dom->preceding->size,                                           0,         'no preceding elements';
  is "$dom", '<script>z<i><b>h:)g</b>a</i><b>fce</b>1<b>d</b><!--y--></script>', 'right result';
};

subtest 'XML nodes' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse('<b>test<image /></b>');
  ok $dom->at('b')->child_nodes->first->xml,                                      'XML mode active';
  ok $dom->at('b')->child_nodes->first->replace('<br>')->child_nodes->first->xml, 'XML mode active';
  is "$dom", '<b><br /><image /></b>', 'right result';
};

subtest 'Treating nodes as elements' => sub {
  my $dom = Mojo::DOM->new('foo<b>bar</b>baz');
  is $dom->child_nodes->first->child_nodes->size,      0,                  'no nodes';
  is $dom->child_nodes->first->descendant_nodes->size, 0,                  'no nodes';
  is $dom->child_nodes->first->children->size,         0,                  'no children';
  is $dom->child_nodes->first->strip->parent,          'foo<b>bar</b>baz', 'no changes';
  is $dom->child_nodes->first->at('b'),                undef,              'no result';
  is $dom->child_nodes->first->find('*')->size,        0,                  'no results';
  ok !$dom->child_nodes->first->matches('*'), 'no match';
  is_deeply $dom->child_nodes->first->attr, {}, 'no attributes';
  is $dom->child_nodes->first->namespace, undef, 'no namespace';
  is $dom->child_nodes->first->tag,       undef, 'no tag';
  is $dom->child_nodes->first->text,      '',    'no text';
  is $dom->child_nodes->first->all_text,  '',    'no text';
};

subtest 'Class and ID' => sub {
  my $dom = Mojo::DOM->new('<div id="id" class="class">a</div>');
  is $dom->at('div#id.class')->text, 'a', 'right text';
};

subtest 'Deep nesting (parent combinator)' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
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
  my $p = $dom->find('body > #container > div p[id]');
  is $p->[0]->attr('id'), 'foo', 'right id attribute';
  is $p->[1],             undef, 'no second result';
  is $p->size,            1,     'right number of elements';
  my @p;
  my @div;
  $dom->find('div')->each(sub { push @div, $_->attr('id') });
  $dom->find('p')->each(sub { push @p, $_->attr('id') });
  is_deeply \@p, [qw(foo bar)], 'found all p elements';
  my $ids = [qw(container header logo buttons buttons content)];
  is_deeply \@div,                                        $ids,                        'found all div elements';
  is_deeply [$dom->at('p')->ancestors->map('tag')->each], [qw(div div div body html)], 'right results';
  is_deeply [$dom->at('html')->ancestors->each],          [],                          'no results';
  is_deeply [$dom->ancestors->each],                      [],                          'no results';
};

subtest 'Script tag' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<script charset="utf-8">alert('lalala');</script>
EOF
  is $dom->at('script')->text, "alert('lalala');", 'right script content';
};

subtest 'HTML5 (unquoted values)' => sub {
  my $dom = Mojo::DOM->new('<div id = test foo ="bar" class=tset bar=/baz/ value baz=//>works</div>');
  is $dom->at('#test')->text,                'works', 'right text';
  is $dom->at('div')->text,                  'works', 'right text';
  is $dom->at('[foo=bar][foo="bar"]')->text, 'works', 'right text';
  is $dom->at('[foo="ba"]'),                 undef,   'no result';
  is $dom->at('[foo=bar]')->text,            'works', 'right text';
  is $dom->at('[foo=ba]'),                   undef,   'no result';
  is $dom->at('.tset')->text,                'works', 'right text';
  is $dom->at('[bar=/baz/]')->text,          'works', 'right text';
  is $dom->at('[baz=//]')->text,             'works', 'right text';
  is $dom->at('[value]')->text,              'works', 'right text';
  is $dom->at('[value=baz]'),                undef,   'no result';
};

subtest 'HTML1 (single quotes, uppercase tags and whitespace in attributes)' => sub {
  my $dom = Mojo::DOM->new(q{<DIV id = 'test' foo ='bar' class= "tset">works</DIV>});
  is $dom->at('#test')->text,       'works', 'right text';
  is $dom->at('div')->text,         'works', 'right text';
  is $dom->at('[foo="bar"]')->text, 'works', 'right text';
  is $dom->at('[foo="ba"]'),        undef,   'no result';
  is $dom->at('[foo=bar]')->text,   'works', 'right text';
  is $dom->at('[foo=ba]'),          undef,   'no result';
  is $dom->at('.tset')->text,       'works', 'right text';
};

subtest 'Already decoded Unicode snowman and quotes in selector' => sub {
  my $dom = Mojo::DOM->new('<div id="snow&apos;m&quot;an">☃</div>');
  is $dom->at('[id="snow\'m\"an"]')->text,      '☃',   'right text';
  is $dom->at('[id="snow\'m\22 an"]')->text,    '☃',   'right text';
  is $dom->at('[id="snow\'m\000022an"]')->text, '☃',   'right text';
  is $dom->at('[id="snow\'m\22an"]'),           undef, 'no result';
  is $dom->at('[id="snow\'m\21 an"]'),          undef, 'no result';
  is $dom->at('[id="snow\'m\000021an"]'),       undef, 'no result';
  is $dom->at('[id="snow\'m\000021 an"]'),      undef, 'no result';
  is $dom->at("[id='snow\\'m\"an']")->text,     '☃',   'right text';
  is $dom->at("[id='snow\\27m\"an']")->text,    '☃',   'right text';
};

subtest 'Unicode and escaped selectors' => sub {
  my $html = '<html><div id="☃x">Snowman</div><div class="x ♥">Heart</div></html>';
  my $dom  = Mojo::DOM->new($html);
  is $dom->at("#\\\n\\002603x")->text,                  'Snowman', 'right text';
  is $dom->at('#\\2603 x')->text,                       'Snowman', 'right text';
  is $dom->at("#\\\n\\2603 x")->text,                   'Snowman', 'right text';
  is $dom->at(qq{[id="\\\n\\2603 x"]})->text,           'Snowman', 'right text';
  is $dom->at(qq{[id="\\\n\\002603x"]})->text,          'Snowman', 'right text';
  is $dom->at(qq{[id="\\\\2603 x"]})->text,             'Snowman', 'right text';
  is $dom->at("html #\\\n\\002603x")->text,             'Snowman', 'right text';
  is $dom->at('html #\\2603 x')->text,                  'Snowman', 'right text';
  is $dom->at("html #\\\n\\2603 x")->text,              'Snowman', 'right text';
  is $dom->at(qq{html [id="\\\n\\2603 x"]})->text,      'Snowman', 'right text';
  is $dom->at(qq{html [id="\\\n\\002603x"]})->text,     'Snowman', 'right text';
  is $dom->at(qq{html [id="\\\\2603 x"]})->text,        'Snowman', 'right text';
  is $dom->at('#☃x')->text,                             'Snowman', 'right text';
  is $dom->at('div#☃x')->text,                          'Snowman', 'right text';
  is $dom->at('html div#☃x')->text,                     'Snowman', 'right text';
  is $dom->at('[id^="☃"]')->text,                       'Snowman', 'right text';
  is $dom->at('div[id^="☃"]')->text,                    'Snowman', 'right text';
  is $dom->at('html div[id^="☃"]')->text,               'Snowman', 'right text';
  is $dom->at('html > div[id^="☃"]')->text,             'Snowman', 'right text';
  is $dom->at('[id^=☃]')->text,                         'Snowman', 'right text';
  is $dom->at('div[id^=☃]')->text,                      'Snowman', 'right text';
  is $dom->at('html div[id^=☃]')->text,                 'Snowman', 'right text';
  is $dom->at('html > div[id^=☃]')->text,               'Snowman', 'right text';
  is $dom->at(".\\\n\\002665")->text,                   'Heart',   'right text';
  is $dom->at('.\\2665')->text,                         'Heart',   'right text';
  is $dom->at("html .\\\n\\002665")->text,              'Heart',   'right text';
  is $dom->at('html .\\2665')->text,                    'Heart',   'right text';
  is $dom->at(qq{html [class\$="\\\n\\002665"]})->text, 'Heart',   'right text';
  is $dom->at(qq{html [class\$="\\2665"]})->text,       'Heart',   'right text';
  is $dom->at(qq{[class\$="\\\n\\002665"]})->text,      'Heart',   'right text';
  is $dom->at(qq{[class\$="\\2665"]})->text,            'Heart',   'right text';
  is $dom->at('.x')->text,                              'Heart',   'right text';
  is $dom->at('html .x')->text,                         'Heart',   'right text';
  is $dom->at('.♥')->text,                              'Heart',   'right text';
  is $dom->at('html .♥')->text,                         'Heart',   'right text';
  is $dom->at('div.♥')->text,                           'Heart',   'right text';
  is $dom->at('html div.♥')->text,                      'Heart',   'right text';
  is $dom->at('[class$="♥"]')->text,                    'Heart',   'right text';
  is $dom->at('div[class$="♥"]')->text,                 'Heart',   'right text';
  is $dom->at('html div[class$="♥"]')->text,            'Heart',   'right text';
  is $dom->at('html > div[class$="♥"]')->text,          'Heart',   'right text';
  is $dom->at('[class$=♥]')->text,                      'Heart',   'right text';
  is $dom->at('div[class$=♥]')->text,                   'Heart',   'right text';
  is $dom->at('html div[class$=♥]')->text,              'Heart',   'right text';
  is $dom->at('html > div[class$=♥]')->text,            'Heart',   'right text';
  is $dom->at('[class~="♥"]')->text,                    'Heart',   'right text';
  is $dom->at('div[class~="♥"]')->text,                 'Heart',   'right text';
  is $dom->at('html div[class~="♥"]')->text,            'Heart',   'right text';
  is $dom->at('html > div[class~="♥"]')->text,          'Heart',   'right text';
  is $dom->at('[class~=♥]')->text,                      'Heart',   'right text';
  is $dom->at('div[class~=♥]')->text,                   'Heart',   'right text';
  is $dom->at('html div[class~=♥]')->text,              'Heart',   'right text';
  is $dom->at('html > div[class~=♥]')->text,            'Heart',   'right text';
  is $dom->at('[class~="x"]')->text,                    'Heart',   'right text';
  is $dom->at('div[class~="x"]')->text,                 'Heart',   'right text';
  is $dom->at('html div[class~="x"]')->text,            'Heart',   'right text';
  is $dom->at('html > div[class~="x"]')->text,          'Heart',   'right text';
  is $dom->at('[class~=x]')->text,                      'Heart',   'right text';
  is $dom->at('div[class~=x]')->text,                   'Heart',   'right text';
  is $dom->at('html div[class~=x]')->text,              'Heart',   'right text';
  is $dom->at('html > div[class~=x]')->text,            'Heart',   'right text';
  is $dom->at('html'),                                  $html,     'right result';
  is $dom->at('#☃x')->parent,                           $html,     'right result';
  is $dom->at('#☃x')->root,                             $html,     'right result';
  is $dom->children('html')->first,                     $html,     'right result';
  is $dom->to_string,                                   $html,     'right result';
  is $dom->content,                                     $html,     'right result';
};

subtest 'Looks remotely like HTML' => sub {
  my $dom = Mojo::DOM->new('<!DOCTYPE H "-/W/D HT 4/E">☃<title class=test>♥</title>☃');
  is $dom->at('title')->text, '♥', 'right text';
  is $dom->at('*')->text,     '♥', 'right text';
  is $dom->at('.test')->text, '♥', 'right text';
};

subtest 'Replace elements' => sub {
  my $dom = Mojo::DOM->new('<div>foo<p>lalala</p>bar</div>');
  is $dom->at('p')->replace('<foo>bar</foo>'), '<div>foo<foo>bar</foo>bar</div>', 'right result';
  is "$dom",                                   '<div>foo<foo>bar</foo>bar</div>', 'right result';
  $dom->at('foo')->replace(Mojo::DOM->new('text'));
  is "$dom", '<div>footextbar</div>', 'right result';
  $dom = Mojo::DOM->new('<div>foo</div><div>bar</div>');
  $dom->find('div')->each(sub { shift->replace('<p>test</p>') });
  is "$dom", '<p>test</p><p>test</p>', 'right result';
  $dom = Mojo::DOM->new('<div>foo<p>lalala</p>bar</div>');
  is $dom->replace('♥'), '♥', 'right result';
  is "$dom",             '♥', 'right result';
  $dom->replace('<div>foo<p>lalala</p>bar</div>');
  is "$dom",                     '<div>foo<p>lalala</p>bar</div>', 'right result';
  is $dom->at('p')->replace(''), '<div>foobar</div>',              'right result';
  is "$dom",                     '<div>foobar</div>',              'right result';
  is $dom->replace(''),          '',                               'no result';
  is "$dom",                     '',                               'no result';
  $dom->replace('<div>foo<p>lalala</p>bar</div>');
  is "$dom", '<div>foo<p>lalala</p>bar</div>', 'right result';
  $dom->find('p')->map(replace => '');
  is "$dom", '<div>foobar</div>', 'right result';
  $dom = Mojo::DOM->new('<div>♥</div>');
  $dom->at('div')->content('☃');
  is "$dom", '<div>☃</div>', 'right result';
  $dom = Mojo::DOM->new('<div>♥</div>');
  $dom->at('div')->content("\x{2603}");
  is $dom->to_string,                            '<div>☃</div>',    'right result';
  is $dom->at('div')->replace('<p>♥</p>')->root, '<p>♥</p>',        'right result';
  is $dom->to_string,                            '<p>♥</p>',        'right result';
  is $dom->replace('<b>whatever</b>')->root,     '<b>whatever</b>', 'right result';
  is $dom->to_string,                            '<b>whatever</b>', 'right result';
  $dom->at('b')->prepend('<p>foo</p>')->append('<p>bar</p>');
  is "$dom",                                                     '<p>foo</p><b>whatever</b><p>bar</p>', 'right result';
  is $dom->find('p')->map('remove')->first->root->at('b')->text, 'whatever',                            'right result';
  is "$dom",                                                     '<b>whatever</b>',                     'right result';
  is $dom->at('b')->strip,                                       'whatever',                            'right result';
  is $dom->strip,                                                'whatever',                            'right result';
  is $dom->remove,                                               '',                                    'right result';
  $dom->replace('A<div>B<p>C<b>D<i><u>E</u></i>F</b>G</p><div>H</div></div>I');
  is $dom->find(':not(div):not(i):not(u)')->map('strip')->first->root, 'A<div>BCD<i><u>E</u></i>FG<div>H</div></div>I',
    'right result';
  is $dom->at('i')->to_string, '<i><u>E</u></i>', 'right result';
  $dom = Mojo::DOM->new('<div><div>A</div><div>B</div>C</div>');
  is $dom->at('div')->at('div')->text, 'A', 'right text';
  $dom->at('div')->find('div')->map('strip');
  is "$dom", '<div>ABC</div>', 'right result';
};

subtest 'Replace element content' => sub {
  my $dom = Mojo::DOM->new('<div>foo<p>lalala</p>bar</div>');
  is $dom->at('p')->content('bar'), '<p>bar</p>',                  'right result';
  is "$dom",                        '<div>foo<p>bar</p>bar</div>', 'right result';
  $dom->at('p')->content(Mojo::DOM->new('text'));
  is "$dom", '<div>foo<p>text</p>bar</div>', 'right result';
  $dom = Mojo::DOM->new('<div>foo</div><div>bar</div>');
  $dom->find('div')->each(sub { shift->content('<p>test</p>') });
  is "$dom", '<div><p>test</p></div><div><p>test</p></div>', 'right result';
  $dom->find('p')->each(sub { shift->content('') });
  is "$dom", '<div><p></p></div><div><p></p></div>', 'right result';
  $dom = Mojo::DOM->new('<div><p id="☃" /></div>');
  $dom->at('#☃')->content('♥');
  is "$dom", '<div><p id="☃">♥</p></div>', 'right result';
  $dom = Mojo::DOM->new('<div>foo<p>lalala</p>bar</div>');
  $dom->content('♥');
  is "$dom",                                          '♥',                              'right result';
  is $dom->content('<div>foo<p>lalala</p>bar</div>'), '<div>foo<p>lalala</p>bar</div>', 'right result';
  is "$dom",                                          '<div>foo<p>lalala</p>bar</div>', 'right result';
  is $dom->content(''),                               '',                               'no result';
  is "$dom",                                          '',                               'no result';
  $dom->content('<div>foo<p>lalala</p>bar</div>');
  is "$dom",                     '<div>foo<p>lalala</p>bar</div>', 'right result';
  is $dom->at('p')->content(''), '<p></p>',                        'right result';
};

subtest 'Mixed search and tree walk' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
  <tr>
    <td>text1</td>
    <td>text2</td>
  </tr>
</table>
EOF
  my @data;
  for my $tr ($dom->find('table tr')->each) {
    for my $td (@{$tr->children}) {
      push @data, $td->tag, $td->all_text;
    }
  }
  is $data[0], 'td',    'right tag';
  is $data[1], 'text1', 'right text';
  is $data[2], 'td',    'right tag';
  is $data[3], 'text2', 'right text';
  is $data[4], undef,   'no tag';
};

subtest 'RSS' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0" encoding="UTF-8"?>
<rss xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
  <channel>
    <title>Test Blog</title>
    <link>http://blog.example.com</link>
    <description>lalala</description>
    <generator>Mojolicious</generator>
    <item>
      <pubDate>Mon, 12 Jul 2010 20:42:00</pubDate>
      <title>Works!</title>
      <link>http://blog.example.com/test</link>
      <guid>http://blog.example.com/test</guid>
      <description>
        <![CDATA[<p>trololololo>]]>
      </description>
      <my:extension foo:id="works">
        <![CDATA[
          [awesome]]
        ]]>
      </my:extension>
    </item>
  </channel>
</rss>
EOF
  ok $dom->xml, 'XML mode detected';
  is $dom->find('rss')->[0]->attr('version'), '2.0', 'right version';
  is_deeply [$dom->at('title')->ancestors->map('tag')->each], [qw(channel rss)], 'right results';
  is $dom->at('extension')->attr('foo:id'), 'works', 'right id';
  like $dom->at('#works')->text,       qr/\[awesome\]\]/, 'right text';
  like $dom->at('[id="works"]')->text, qr/\[awesome\]\]/, 'right text';
  is $dom->find('description')->[1]->text, "\n        <p>trololololo>\n      ", 'right text';
  is $dom->at('pubDate')->text,            'Mon, 12 Jul 2010 20:42:00',         'right text';
  like $dom->at('[id*="ork"]')->text,  qr/\[awesome\]\]/, 'right text';
  like $dom->at('[id*="orks"]')->text, qr/\[awesome\]\]/, 'right text';
  like $dom->at('[id*="work"]')->text, qr/\[awesome\]\]/, 'right text';
  like $dom->at('[id*="or"]')->text,   qr/\[awesome\]\]/, 'right text';
  ok $dom->at('rss')->xml,                     'XML mode active';
  ok $dom->at('extension')->parent->xml,       'XML mode active';
  ok $dom->at('extension')->root->xml,         'XML mode active';
  ok $dom->children('rss')->first->xml,        'XML mode active';
  ok $dom->at('title')->ancestors->first->xml, 'XML mode active';
};

subtest 'Namespace' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0"?>
<bk:book xmlns='uri:default-ns'
         xmlns:bk='uri:book-ns'
         xmlns:isbn='uri:isbn-ns'>
  <bk:title>Programming Perl</bk:title>
  <comment>rocks!</comment>
  <nons xmlns=''>
    <section>Nothing</section>
  </nons>
  <meta xmlns='uri:meta-ns'>
    <isbn:number>978-0596000271</isbn:number>
  </meta>
</bk:book>
EOF
  ok $dom->xml, 'XML mode detected';
  is $dom->namespace,                                       undef,            'no namespace';
  is $dom->at('book comment')->namespace,                   'uri:default-ns', 'right namespace';
  is $dom->at('book comment')->text,                        'rocks!',         'right text';
  is $dom->at('book nons section')->namespace,              '',               'no namespace';
  is $dom->at('book nons section')->text,                   'Nothing',        'right text';
  is $dom->at('book meta number')->namespace,               'uri:isbn-ns',    'right namespace';
  is $dom->at('book meta number')->text,                    '978-0596000271', 'right text';
  is $dom->children('bk\:book')->first->{xmlns},            'uri:default-ns', 'right attribute';
  is $dom->children('book')->first->{xmlns},                'uri:default-ns', 'right attribute';
  is $dom->children('k\:book')->first,                      undef,            'no result';
  is $dom->children('ook')->first,                          undef,            'no result';
  is $dom->at('k\:book'),                                   undef,            'no result';
  is $dom->at('ook'),                                       undef,            'no result';
  is $dom->at('[xmlns\:bk]')->{'xmlns:bk'},                 'uri:book-ns',    'right attribute';
  is $dom->at('[bk]')->{'xmlns:bk'},                        'uri:book-ns',    'right attribute';
  is $dom->at('[bk]')->attr('xmlns:bk'),                    'uri:book-ns',    'right attribute';
  is $dom->at('[bk]')->attr('s:bk'),                        undef,            'no attribute';
  is $dom->at('[bk]')->attr('bk'),                          undef,            'no attribute';
  is $dom->at('[bk]')->attr('k'),                           undef,            'no attribute';
  is $dom->at('[s\:bk]'),                                   undef,            'no result';
  is $dom->at('[k]'),                                       undef,            'no result';
  is $dom->at('number')->ancestors('meta')->first->{xmlns}, 'uri:meta-ns',    'right attribute';
  ok $dom->at('nons')->matches('book > nons'),             'element did match';
  ok !$dom->at('title')->matches('book > nons > section'), 'element did not match';
};

subtest 'Dots' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0"?>
<foo xmlns:foo.bar="uri:first">
  <bar xmlns:fooxbar="uri:second">
    <foo.bar:baz>First</fooxbar:baz>
    <fooxbar:ya.da>Second</foo.bar:ya.da>
  </bar>
</foo>
EOF
  is $dom->at('foo bar baz')->text,    "First\n    ", 'right text';
  is $dom->at('baz')->namespace,       'uri:first',   'right namespace';
  is $dom->at('foo bar ya\.da')->text, "Second\n  ",  'right text';
  is $dom->at('ya\.da')->namespace,    'uri:second',  'right namespace';
  is $dom->at('foo')->namespace,       undef,         'no namespace';
  is $dom->at('[xml\.s]'),             undef,         'no result';
  is $dom->at('b\.z'),                 undef,         'no result';
};

subtest 'Yadis' => sub {
  my $dom = Mojo::DOM->new(<<'EOF');
<?xml version="1.0" encoding="UTF-8"?>
<XRDS xmlns="xri://$xrds">
  <XRD xmlns="xri://$xrd*($v*2.0)">
    <Service>
      <Type>http://o.r.g/sso/2.0</Type>
    </Service>
    <Service>
      <Type>http://o.r.g/sso/1.0</Type>
    </Service>
  </XRD>
</XRDS>
EOF
  ok $dom->xml, 'XML mode detected';
  is $dom->at('XRDS')->namespace, 'xri://$xrds',         'right namespace';
  is $dom->at('XRD')->namespace,  'xri://$xrd*($v*2.0)', 'right namespace';
  my $s = $dom->find('XRDS XRD Service');
  is $s->[0]->at('Type')->text, 'http://o.r.g/sso/2.0', 'right text';
  is $s->[0]->namespace,        'xri://$xrd*($v*2.0)',  'right namespace';
  is $s->[1]->at('Type')->text, 'http://o.r.g/sso/1.0', 'right text';
  is $s->[1]->namespace,        'xri://$xrd*($v*2.0)',  'right namespace';
  is $s->[2],                   undef,                  'no result';
  is $s->size,                  2,                      'right number of elements';
};

subtest 'Yadis (roundtrip with namespace)' => sub {
  my $yadis = <<'EOF';
<?xml version="1.0" encoding="UTF-8"?>
<xrds:XRDS xmlns="xri://$xrd*($v*2.0)" xmlns:xrds="xri://$xrds">
  <XRD>
    <Service>
      <Type>http://o.r.g/sso/3.0</Type>
    </Service>
    <xrds:Service>
      <Type>http://o.r.g/sso/4.0</Type>
    </xrds:Service>
  </XRD>
  <XRD>
    <Service>
      <Type test="23">http://o.r.g/sso/2.0</Type>
    </Service>
    <Service>
      <Type Test="23" test="24">http://o.r.g/sso/1.0</Type>
    </Service>
  </XRD>
</xrds:XRDS>
EOF
  my $dom = Mojo::DOM->new($yadis);
  ok $dom->xml, 'XML mode detected';
  is $dom->at('XRDS')->namespace, 'xri://$xrds',         'right namespace';
  is $dom->at('XRD')->namespace,  'xri://$xrd*($v*2.0)', 'right namespace';
  my $s = $dom->find('XRDS XRD Service');
  is $s->[0]->at('Type')->text,                           'http://o.r.g/sso/3.0', 'right text';
  is $s->[0]->namespace,                                  'xri://$xrd*($v*2.0)',  'right namespace';
  is $s->[1]->at('Type')->text,                           'http://o.r.g/sso/4.0', 'right text';
  is $s->[1]->namespace,                                  'xri://$xrds',          'right namespace';
  is $s->[2]->at('Type')->text,                           'http://o.r.g/sso/2.0', 'right text';
  is $s->[2]->namespace,                                  'xri://$xrd*($v*2.0)',  'right namespace';
  is $s->[3]->at('Type')->text,                           'http://o.r.g/sso/1.0', 'right text';
  is $s->[3]->namespace,                                  'xri://$xrd*($v*2.0)',  'right namespace';
  is $s->[4],                                             undef,                  'no result';
  is $s->size,                                            4,                      'right number of elements';
  is $dom->at('[Test="23"]')->text,                       'http://o.r.g/sso/1.0', 'right text';
  is $dom->at('[test="23"]')->text,                       'http://o.r.g/sso/2.0', 'right text';
  is $dom->find('xrds\:Service > Type')->[0]->text,       'http://o.r.g/sso/4.0', 'right text';
  is $dom->find('xrds\:Service > Type')->[1],             undef,                  'no result';
  is $dom->find('xrds\3AService > Type')->[0]->text,      'http://o.r.g/sso/4.0', 'right text';
  is $dom->find('xrds\3AService > Type')->[1],            undef,                  'no result';
  is $dom->find('xrds\3A Service > Type')->[0]->text,     'http://o.r.g/sso/4.0', 'right text';
  is $dom->find('xrds\3A Service > Type')->[1],           undef,                  'no result';
  is $dom->find('xrds\00003AService > Type')->[0]->text,  'http://o.r.g/sso/4.0', 'right text';
  is $dom->find('xrds\00003AService > Type')->[1],        undef,                  'no result';
  is $dom->find('xrds\00003A Service > Type')->[0]->text, 'http://o.r.g/sso/4.0', 'right text';
  is $dom->find('xrds\00003A Service > Type')->[1],       undef,                  'no result';
  is "$dom",                                              $yadis,                 'successful roundtrip';
};

subtest 'Result and iterator order' => sub {
  my $dom = Mojo::DOM->new('<a><b>1</b></a><b>2</b><b>3</b>');
  my @numbers;
  $dom->find('b')->each(sub { push @numbers, pop, shift->text });
  is_deeply \@numbers, [1, 1, 2, 2, 3, 3], 'right order';
};

subtest 'Attributes on multiple lines' => sub {
  my $dom = Mojo::DOM->new("<div test=23 id='a' \n class='x' foo=bar />");
  is $dom->at('div.x')->attr('test'),        23,  'right attribute';
  is $dom->at('[foo="bar"]')->attr('class'), 'x', 'right attribute';
  is $dom->at('div')->attr(baz => undef)->root->to_string, '<div baz class="x" foo="bar" id="a" test="23"></div>',
    'right result';
};

subtest 'Markup characters in attribute values' => sub {
  my $dom = Mojo::DOM->new(qq{<div id="<a>" \n test='='>Test<div id='><' /></div>});
  is $dom->at('div[id="<a>"]')->attr->{test}, '=',    'right attribute';
  is $dom->at('[id="<a>"]')->text,            'Test', 'right text';
  is $dom->at('[id="><"]')->attr->{id},       '><',   'right attribute';
};

subtest 'Empty attributes' => sub {
  my $dom = Mojo::DOM->new(qq{<div test="" test2='' />});
  is $dom->at('div')->attr->{test},  '',    'empty attribute value';
  is $dom->at('div')->attr->{test2}, '',    'empty attribute value';
  is $dom->at('[test]')->tag,        'div', 'right tag';
  is $dom->at('[test2]')->tag,       'div', 'right tag';
  is $dom->at('[test3]'),            undef, 'no result';
  is $dom->at('[test=""]')->tag,     'div', 'right tag';
  is $dom->at('[test2=""]')->tag,    'div', 'right tag';
  is $dom->at('[test3=""]'),         undef, 'no result';
};

subtest 'Multi-line attribute' => sub {
  my $dom = Mojo::DOM->new(qq{<div class="line1\nline2" />});
  is $dom->at('div')->attr->{class}, "line1\nline2", 'multi-line attribute value';
  is $dom->at('.line1')->tag,        'div',          'right tag';
  is $dom->at('.line2')->tag,        'div',          'right tag';
  is $dom->at('.line3'),             undef,          'no result';
};

subtest 'Entities in attributes' => sub {
  my $dom = Mojo::DOM->new(qq{<a href="/?foo&lt=bar"></a>});
  is $dom->at('a')->{href}, '/?foo&lt=bar', 'right attribute value';
  $dom = Mojo::DOM->new(qq{<a href="/?f&ltoo=bar"></a>});
  is $dom->at('a')->{href}, '/?f&ltoo=bar', 'right attribute value';
  $dom = Mojo::DOM->new(qq{<a href="/?f&lt-oo=bar"></a>});
  is $dom->at('a')->{href}, '/?f<-oo=bar', 'right attribute value';
  $dom = Mojo::DOM->new(qq{<a href="/?foo=&lt"></a>});
  is $dom->at('a')->{href}, '/?foo=<', 'right attribute value';
  $dom = Mojo::DOM->new(qq{<a href="/?f&lt;oo=bar"></a>});
  is $dom->at('a')->{href}, '/?f<oo=bar', 'right attribute value';
};

subtest 'Whitespaces before closing bracket' => sub {
  my $dom = Mojo::DOM->new('<div >content</div>');
  ok $dom->at('div'), 'tag found';
  is $dom->at('div')->text,    'content', 'right text';
  is $dom->at('div')->content, 'content', 'right text';
};

subtest 'Class with hyphen' => sub {
  my $dom = Mojo::DOM->new('<div class="a">A</div><div class="a-1">A1</div>');
  my @div;
  $dom->find('.a')->each(sub { push @div, shift->text });
  is_deeply \@div, ['A'], 'found first element only';
  @div = ();
  $dom->find('.a-1')->each(sub { push @div, shift->text });
  is_deeply \@div, ['A1'], 'found last element only';
};

subtest 'Defined but false text' => sub {
  my $dom = Mojo::DOM->new('<div><div id="a">A</div><div id="b">B</div></div><div id="0">0</div>');
  my @div;
  $dom->find('div[id]')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A B 0)], 'found all div elements with id';
};

subtest 'Empty tags' => sub {
  my $dom = Mojo::DOM->new('<hr /><br/><br id="br"/><br />');
  is "$dom",                  '<hr><br><br id="br"><br>', 'right result';
  is $dom->at('br')->content, '',                         'empty result';
};

subtest 'Inner XML' => sub {
  my $dom = Mojo::DOM->new('<a>xxx<x>x</x>xxx</a>');
  is $dom->at('a')->content, 'xxx<x>x</x>xxx',        'right result';
  is $dom->content,          '<a>xxx<x>x</x>xxx</a>', 'right result';
};

subtest 'Multiple selectors' => sub {
  my $dom = Mojo::DOM->new('<div id="a">A</div><div id="b">B</div><div id="c">C</div><p>D</p>');
  my @div;
  $dom->find('p, div')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A B C D)], 'found all elements';
  @div = ();
  $dom->find('#a, #c')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
  @div = ();
  $dom->find('div#a, div#b')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A B)], 'found all div elements with the right ids';
  @div = ();
  $dom->find('div[id="a"], div[id="c"]')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
  $dom = Mojo::DOM->new('<div id="☃">A</div><div id="b">B</div><div id="♥x">C</div>');
  @div = ();
  $dom->find('#☃, #♥x')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
  @div = ();
  $dom->find('div#☃, div#b')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A B)], 'found all div elements with the right ids';
  @div = ();
  $dom->find('div[id="☃"], div[id="♥x"]')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A C)], 'found all div elements with the right ids';
};

subtest 'Multiple attributes' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<div foo="bar" bar="baz">A</div>
<div foo="bar">B</div>
<div foo="bar" bar="baz">C</div>
<div foo="baz" bar="baz">D</div>
EOF
  my @div;
  $dom->find('div[foo="bar"][bar="baz"]')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A C)], 'found all div elements with the right atributes';
  @div = ();
  $dom->find('div[foo^="b"][foo$="r"]')->each(sub { push @div, shift->text });
  is_deeply \@div, [qw(A B C)], 'found all div elements with the right atributes';
  is $dom->at('[foo="bar"]')->previous,               undef, 'no previous sibling';
  is $dom->at('[foo="bar"]')->next->text,             'B',   'right text';
  is $dom->at('[foo="bar"]')->next->previous->text,   'A',   'right text';
  is $dom->at('[foo="bar"]')->next->next->next->next, undef, 'no next sibling';
};

subtest 'Pseudo-classes' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<form action="/foo">
    <input type="text" name="user" value="test" />
    <input type="checkbox" checked="checked" name="groovy">
    <select name="a">
        <option value="b">b</option>
        <optgroup label="c">
            <option value="d">d</option>
            <option selected="selected" value="e">E</option>
            <option value="f">f</option>
        </optgroup>
        <option value="g">g</option>
        <option selected value="h">H</option>
    </select>
    <input type="submit" value="Ok!" />
    <input type="checkbox" checked name="I">
    <p id="content">test 123</p>
    <p id="no_content"><? test ?><!-- 123 --></p>
</form>
EOF
  is $dom->find(':root')->[0]->tag,                        'form',       'right tag';
  is $dom->find('*:root')->[0]->tag,                       'form',       'right tag';
  is $dom->find('form:root')->[0]->tag,                    'form',       'right tag';
  is $dom->find(':root')->[1],                             undef,        'no result';
  is $dom->find(':checked')->[0]->attr->{name},            'groovy',     'right name';
  is $dom->find('option:checked')->[0]->attr->{value},     'e',          'right value';
  is $dom->find(':checked')->[1]->text,                    'E',          'right text';
  is $dom->find('*:checked')->[1]->text,                   'E',          'right text';
  is $dom->find(':checked')->[2]->text,                    'H',          'right name';
  is $dom->find(':checked')->[3]->attr->{name},            'I',          'right name';
  is $dom->find(':checked')->[4],                          undef,        'no result';
  is $dom->find('option[selected]')->[0]->attr->{value},   'e',          'right value';
  is $dom->find('option[selected]')->[1]->text,            'H',          'right text';
  is $dom->find('option[selected]')->[2],                  undef,        'no result';
  is $dom->find(':checked[value="e"]')->[0]->text,         'E',          'right text';
  is $dom->find('*:checked[value="e"]')->[0]->text,        'E',          'right text';
  is $dom->find('option:checked[value="e"]')->[0]->text,   'E',          'right text';
  is $dom->at('optgroup option:checked[value="e"]')->text, 'E',          'right text';
  is $dom->at('select option:checked[value="e"]')->text,   'E',          'right text';
  is $dom->at('select :checked[value="e"]')->text,         'E',          'right text';
  is $dom->at('optgroup > :checked[value="e"]')->text,     'E',          'right text';
  is $dom->at('select *:checked[value="e"]')->text,        'E',          'right text';
  is $dom->at('optgroup > *:checked[value="e"]')->text,    'E',          'right text';
  is $dom->find(':checked[value="e"]')->[1],               undef,        'no result';
  is $dom->find(':empty')->[0]->attr->{name},              'user',       'right name';
  is $dom->find('input:empty')->[0]->attr->{name},         'user',       'right name';
  is $dom->at(':empty[type^="ch"]')->attr->{name},         'groovy',     'right name';
  is $dom->at('p')->attr->{id},                            'content',    'right attribute';
  is $dom->at('p:empty')->attr->{id},                      'no_content', 'right attribute';
};

subtest 'More pseudo-classes' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<ul>
    <li>A</li>
    <li>B</li>
    <li>C</li>
    <li>D</li>
    <li>E</li>
    <li>F</li>
    <li>G</li>
    <li>H</li>
</ul>
EOF
  my @li;
  $dom->find('li:nth-child(odd)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
  @li = ();
  $dom->find('li:NTH-CHILD(ODD)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
  @li = ();
  $dom->find('li:nth-last-child(odd)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all odd li elements';
  is $dom->find(':nth-child(odd)')->[0]->tag,        'ul', 'right tag';
  is $dom->find(':nth-child(odd)')->[1]->text,       'A',  'right text';
  is $dom->find(':nth-child(1)')->[0]->tag,          'ul', 'right tag';
  is $dom->find(':nth-child(1)')->[1]->text,         'A',  'right text';
  is $dom->find(':nth-last-child(odd)')->[0]->tag,   'ul', 'right tag';
  is $dom->find(':nth-last-child(odd)')->last->text, 'H',  'right text';
  is $dom->find(':nth-last-child(1)')->[0]->tag,     'ul', 'right tag';
  is $dom->find(':nth-last-child(1)')->[1]->text,    'H',  'right text';
  @li = ();
  $dom->find('li:nth-child(2n+1)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
  @li = ();
  $dom->find('li:nth-child(2n + 1)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A C E G)], 'found all odd li elements';
  @li = ();
  $dom->find('li:nth-last-child(2n+1)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all odd li elements';
  @li = ();
  $dom->find('li:nth-child(even)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all even li elements';
  @li = ();
  $dom->find('li:NTH-CHILD(EVEN)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all even li elements';
  @li = ();
  $dom->find('li:nth-last-child( even )')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A C E G)], 'found all even li elements';
  @li = ();
  $dom->find('li:nth-child(2n+2)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all even li elements';
  @li = ();
  $dom->find('li:nTh-chILd(2N+2)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all even li elements';
  @li = ();
  $dom->find('li:nth-child( 2n + 2 )')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(B D F H)], 'found all even li elements';
  @li = ();
  $dom->find('li:nth-last-child(2n+2)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A C E G)], 'found all even li elements';
  @li = ();
  $dom->find('li:nth-child(4n+1)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A E)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-last-child(4n+1)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(D H)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-child(4n+4)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(D H)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-last-child(4n+4)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A E)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-child(4n)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(D H)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-child( 4n )')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(D H)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-last-child(4n)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A E)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-child(5n-2)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(C H)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-child( 5n - 2 )')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(C H)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-last-child(5n-2)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A F)], 'found the right li elements';
  @li = ();
  $dom->find('li:nth-child(-n+3)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C)], 'found first three li elements';
  @li = ();
  $dom->find('li:nth-child( -n + 3 )')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C)], 'found first three li elements';
  @li = ();
  $dom->find('li:nth-last-child(-n+3)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(F G H)], 'found last three li elements';
  @li = ();
  $dom->find('li:nth-child(-1n+3)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C)], 'found first three li elements';
  @li = ();
  $dom->find('li:nth-last-child(-1n+3)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(F G H)], 'found first three li elements';
  @li = ();
  $dom->find('li:nth-child(3n)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(C F)], 'found every third li elements';
  @li = ();
  $dom->find('li:nth-last-child(3n)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(C F)], 'found every third li elements';
  @li = ();
  $dom->find('li:NTH-LAST-CHILD(3N)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(C F)], 'found every third li elements';
  @li = ();
  $dom->find('li:Nth-Last-Child(3N)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(C F)], 'found every third li elements';
  @li = ();
  $dom->find('li:nth-child( 3 )')->each(sub { push @li, shift->text });
  is_deeply \@li, ['C'], 'found third li element';
  @li = ();
  $dom->find('li:nth-last-child( +3 )')->each(sub { push @li, shift->text });
  is_deeply \@li, ['F'], 'found third last li element';
  @li = ();
  $dom->find('li:nth-child(1n+0)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:nth-child(1n-0)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:nth-child(n+0)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:nth-child(n)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:nth-child(n+0)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:NTH-CHILD(N+0)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:Nth-Child(N+0)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:nth-child(n)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A B C D E F G H)], 'found all li elements';
  @li = ();
  $dom->find('li:nth-child(0n+1)')->each(sub { push @li, shift->text });
  is_deeply \@li, [qw(A)], 'found first li element';
  is $dom->find('li:nth-child(0n+0)')->size,     0, 'no results';
  is $dom->find('li:nth-child(0)')->size,        0, 'no results';
  is $dom->find('li:nth-child()')->size,         0, 'no results';
  is $dom->find('li:nth-child(whatever)')->size, 0, 'no results';
  is $dom->find('li:whatever(whatever)')->size,  0, 'no results';
};

subtest 'Even more pseudo-classes' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li class="test ♥">C</li>
    <p>D</p>
    <li>E</li>
    <li>F</li>
    <p>G</p>
    <li>H</li>
    <li>I</li>
</ul>
<div>
    <div class="☃">J</div>
</div>
<div>
    <a href="http://mojolicious.org">Mojo!</a>
    <div class="☃">K</div>
    <a href="http://mojolicious.org">Mojolicious!</a>
</div>
EOF
  my @e;
  $dom->find('ul :nth-child(odd)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A C E G I)], 'found all odd elements';
  @e = ();
  $dom->find('li:nth-of-type(odd)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A E H)], 'found all odd li elements';
  @e = ();
  $dom->find('ul li:not(:first-child, :last-child)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(C E F H)], 'found all li elements but first/last';
  @e = ();
  $dom->find('ul li:is(:first-child, :last-child)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A I)], 'found first/last li elements';
  @e = ();
  $dom->find('li:nth-last-of-type( odd )')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(C F I)], 'found all odd li elements (counting from end)';
  @e = ();
  $dom->find('p:nth-of-type(odd)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(B G)], 'found all odd p elements';
  @e = ();
  $dom->find('p:nth-last-of-type(odd)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(B G)], 'found all odd p elements (counting from end)';
  @e = ();
  $dom->find('ul :nth-child(1)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['A'], 'found first child';
  @e = ();
  $dom->find('ul :first-child')->each(sub { push @e, shift->text });
  is_deeply \@e, ['A'], 'found first child';
  @e = ();
  $dom->find('p:nth-of-type(1)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['B'], 'found first child';
  @e = ();
  $dom->find('p:first-of-type')->each(sub { push @e, shift->text });
  is_deeply \@e, ['B'], 'found first child';
  @e = ();
  $dom->find('li:nth-of-type(1)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['A'], 'found first child';
  @e = ();
  $dom->find('li:first-of-type')->each(sub { push @e, shift->text });
  is_deeply \@e, ['A'], 'found first child';
  @e = ();
  $dom->find('ul :nth-last-child(-n+1)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['I'], 'found last child';
  @e = ();
  $dom->find('ul :last-child')->each(sub { push @e, shift->text });
  is_deeply \@e, ['I'], 'found last child';
  @e = ();
  $dom->find('p:nth-last-of-type(-n+1)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['G'], 'found last child';
  @e = ();
  $dom->find('p:last-of-type')->each(sub { push @e, shift->text });
  is_deeply \@e, ['G'], 'found last child';
  @e = ();
  $dom->find('li:nth-last-of-type(-n+1)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['I'], 'found last child';
  @e = ();
  $dom->find('li:last-of-type')->each(sub { push @e, shift->text });
  is_deeply \@e, ['I'], 'found last child';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(li)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['B'], 'found first p element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):NOT(li)')->each(sub { push @e, shift->text });
  is_deeply \@e, ['B'], 'found first p element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(:first-child)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(B C)], 'found second and third element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(.♥)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A B)], 'found first and second element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not([class$="♥"])')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A B)], 'found first and second element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(li[class$="♥"])')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A B)], 'found first and second element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not([class$="♥"][class^="test"])')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A B)], 'found first and second element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(*[class$="♥"])')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(A B)], 'found first and second element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(:nth-child(-n+2))')->each(sub { push @e, shift->text });
  is_deeply \@e, ['C'], 'found third element';
  @e = ();
  $dom->find('ul :nth-child(-n+3):not(:nth-child(1)):not(:nth-child(2))')->each(sub { push @e, shift->text });
  is_deeply \@e, ['C'], 'found third element';
  @e = ();
  $dom->find(':only-child')->each(sub { push @e, shift->text });
  is_deeply \@e, ['J'], 'found only child';
  @e = ();
  $dom->find('div :only-of-type')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(J K)], 'found only child';
  @e = ();
  $dom->find('div:only-child')->each(sub { push @e, shift->text });
  is_deeply \@e, ['J'], 'found only child';
  @e = ();
  $dom->find('div div:only-of-type')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(J K)], 'found only child';
  @e = ();
  $dom->find('div :nth-child(-n+2)')->each(sub { push @e, shift->text });
  is_deeply \@e, [qw(J Mojo! K)], 'found first two children of each div';
};

subtest 'Links' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<a>A</a>
<a href=/>B</a>
<link rel=C>
<link href=/ rel=D>
<area alt=E>
<area href=/ alt=F>
<div href=borked>very borked</div>
EOF
  is $dom->find(':any-link')->map(sub { $_->tag })->join(','), 'a,link,area', 'right tags';
  is $dom->find(':link')->map(sub { $_->tag })->join(','),     'a,link,area', 'right tags';
  is $dom->find(':visited')->map(sub { $_->tag })->join(','),  'a,link,area', 'right tags';
  is $dom->at('a:link')->text,                                 'B',           'right result';
  is $dom->at('a:any-link')->text,                             'B',           'right result';
  is $dom->at('a:visited')->text,                              'B',           'right result';
  is $dom->at('link:any-link')->{rel},                         'D',           'right result';
  is $dom->at('link:link')->{rel},                             'D',           'right result';
  is $dom->at('link:visited')->{rel},                          'D',           'right result';
  is $dom->at('area:link')->{alt},                             'F',           'right result';
  is $dom->at('area:any-link')->{alt},                         'F',           'right result';
  is $dom->at('area:visited')->{alt},                          'F',           'right result';
};

subtest 'Sibling combinator' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li>C</li>
</ul>
<h1>D</h1>
<p id="♥">E</p>
<p id="☃">F<b>H</b></p>
<div>G</div>
EOF
  is $dom->at('li ~ p')->text,                        'B',   'right text';
  is $dom->at('li + p')->text,                        'B',   'right text';
  is $dom->at('h1 ~ p ~ p')->text,                    'F',   'right text';
  is $dom->at('h1 + p ~ p')->text,                    'F',   'right text';
  is $dom->at('h1 ~ p + p')->text,                    'F',   'right text';
  is $dom->at('h1 + p + p')->text,                    'F',   'right text';
  is $dom->at('h1  +  p+p')->text,                    'F',   'right text';
  is $dom->at('ul > li ~ li')->text,                  'C',   'right text';
  is $dom->at('ul li ~ li')->text,                    'C',   'right text';
  is $dom->at('ul>li~li')->text,                      'C',   'right text';
  is $dom->at('ul li li'),                            undef, 'no result';
  is $dom->at('ul ~ li ~ li'),                        undef, 'no result';
  is $dom->at('ul + li ~ li'),                        undef, 'no result';
  is $dom->at('ul > li + li'),                        undef, 'no result';
  is $dom->at('h1 ~ div')->text,                      'G',   'right text';
  is $dom->at('h1 + div'),                            undef, 'no result';
  is $dom->at('p + div')->text,                       'G',   'right text';
  is $dom->at('ul + h1 + p + p + div')->text,         'G',   'right text';
  is $dom->at('ul + h1 ~ p + div')->text,             'G',   'right text';
  is $dom->at('h1 ~ #♥')->text,                       'E',   'right text';
  is $dom->at('h1 + #♥')->text,                       'E',   'right text';
  is $dom->at('#♥~#☃')->text,                         'F',   'right text';
  is $dom->at('#♥+#☃')->text,                         'F',   'right text';
  is $dom->at('#♥+#☃>b')->text,                       'H',   'right text';
  is $dom->at('#♥ > #☃'),                             undef, 'no result';
  is $dom->at('#♥ #☃'),                               undef, 'no result';
  is $dom->at('#♥ + #☃ + :nth-last-child(1)')->text,  'G',   'right text';
  is $dom->at('#♥ ~ #☃ + :nth-last-child(1)')->text,  'G',   'right text';
  is $dom->at('#♥ + #☃ ~ :nth-last-child(1)')->text,  'G',   'right text';
  is $dom->at('#♥ ~ #☃ ~ :nth-last-child(1)')->text,  'G',   'right text';
  is $dom->at('#♥ + :nth-last-child(2)')->text,       'F',   'right text';
  is $dom->at('#♥ ~ :nth-last-child(2)')->text,       'F',   'right text';
  is $dom->at('#♥ + #☃ + *:nth-last-child(1)')->text, 'G',   'right text';
  is $dom->at('#♥ ~ #☃ + *:nth-last-child(1)')->text, 'G',   'right text';
  is $dom->at('#♥ + #☃ ~ *:nth-last-child(1)')->text, 'G',   'right text';
  is $dom->at('#♥ ~ #☃ ~ *:nth-last-child(1)')->text, 'G',   'right text';
  is $dom->at('#♥ + *:nth-last-child(2)')->text,      'F',   'right text';
  is $dom->at('#♥ ~ *:nth-last-child(2)')->text,      'F',   'right text';
};

subtest 'Scoped selectors' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<p>Zero</p>
<div>
  <p>One</p>
  <p>Two</p>
  <p><a href="#">Link</a></p>
</div>
<div>
  <p>Three</p>
  <p>Four</p>
  <i>Six</i>
</div>
<p>Five</p>
EOF
  is $dom->at('div p')->at(':scope')->text,                     'One',   'right text';
  is $dom->at('div')->at(':scope p')->text,                     'One',   'right text';
  is $dom->at('div')->at(':scope > p')->text,                   'One',   'right text';
  is $dom->at('div')->at('> p')->text,                          'One',   'right text';
  is $dom->at('div p')->at('+ p')->text,                        'Two',   'right text';
  is $dom->at('div p')->at('~ p')->text,                        'Two',   'right text';
  is $dom->at('div p')->at('~ p a')->text,                      'Link',  'right text';
  is $dom->at('div')->at(':scope a')->text,                     'Link',  'right text';
  is $dom->at('div')->at(':scope > a'),                         undef,   'no result';
  is $dom->at('div')->at(':scope > p > a')->text,               'Link',  'right text';
  is $dom->find('div')->last->at(':scope p')->text,             'Three', 'right text';
  is $dom->find('div')->last->at(':scope > p')->text,           'Three', 'right text';
  is $dom->find('div')->last->at('> p')->text,                  'Three', 'right text';
  is $dom->at('div p')->at(':scope + p')->text,                 'Two',   'right text';
  is $dom->at('div')->at(':scope > p:nth-child(2), p a')->text, 'Two',   'right text';
  is $dom->at('div')->at('p, :scope > p:nth-child(2)')->text,   'One',   'right text';
  is $dom->at('div')->at('p:not(:scope > *)')->text,            'Zero',  'right text';
  is $dom->at('div p:nth-child(2)')->at('*:is(:scope)')->text,  'Two',   'right text';
  is $dom->at('div')->at('div p, ~ p')->text,                   'Five',  'right text';
  is $dom->at('> p')->text,                                     'Zero',  'right text';
  is $dom->at(':scope'),                                        undef,   'no result';
  is $dom->at(':scope p')->text,                                'Zero',  'right text';
  is $dom->at(':scope div p')->text,                            'One',   'right text';
  is $dom->at(':scope p a')->text,                              'Link',  'right text';
  is $dom->at('> p')->at('p ~ :scope'),                         undef,   'no result';
  is $dom->at('> p:last-child')->at('p ~ :scope')->text,        'Five',  'righ text';
  is $dom->at('p:has(+ i)')->text,                              'Four',  'right text';
  is $dom->at('p:has(:scope ~ i)')->text,                       'Three', 'right text';
  is $dom->at('div:has(i) p')->text,                            'Three', 'right text';
  is $dom->at('div:has(> i) p')->text,                          'Three', 'right text';
  is $dom->find('div:not(:has(i)) > p')->last->all_text,        'Link',  'right text';
  is $dom->find('div:has(:not(p)) > p')->last->all_text,        'Four',  'right text';
};

subtest 'Text matching' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<p>Zero</p>
<div>
  <p>One&lt;Two&gt;</p>
  <div>Two<!-- Three -->Four</div>
  <p>Five Six<a href="#">Seven</a>Eight</p>
</div>
EOF
  is $dom->at(':text(ero)')->text,              'Zero',               'right text';
  is $dom->at(':text(Zero)')->text,             'Zero',               'right text';
  is $dom->at('p:text(Zero)')->text,            'Zero',               'right text';
  is $dom->at('div:text(Zero)'),                undef,                'no result';
  is $dom->at('p:text(w)')->text,               'One<Two>',           'right text';
  is $dom->at(':text(<Two>)')->text,            'One<Two>',           'right text';
  is $dom->at(':text(Sev)')->text,              'Seven',              'right text';
  is $dom->at(':text(/^Seven$/)')->text,        'Seven',              'right text';
  is $dom->at('p a:text(even)')->text,          'Seven',              'right text';
  is $dom->at(':text(v) :text(e)')->text,       'Seven',              'right text';
  is $dom->at(':text(eight)')->all_text,        'Five SixSevenEight', 'right text';
  is $dom->at(':text(/Ei.ht/)')->all_text,      'Five SixSevenEight', 'right text';
  is $dom->at(':text(/(?i:ei.ht)/)')->all_text, 'Five SixSevenEight', 'right text';
  is $dom->at(':text(v) :text(x)'),             undef,                'no result';
  is $dom->at('div:text(x)'),                   undef,                'no result';
  is $dom->at(':text(three)'),                  undef,                'no result';
  is $dom->at(':text(/three/)'),                undef,                'no result';
  is $dom->at(':text(/zero/)'),                 undef,                'no result';
  is $dom->at(':text(/zero/)'),                 undef,                'no result';
};

subtest 'Adding nodes' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<ul>
    <li>A</li>
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
  $dom->at('li')->append('<p>A1</p>23');
  is "$dom", <<EOF, 'right result';
<ul>
    <li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
  $dom->at('li')->prepend('24')->prepend('<div>A-1</div>25');
  is "$dom", <<EOF, 'right result';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
  is $dom->at('div')->text,                                   'A-1',  'right text';
  is $dom->at('iv'),                                          undef,  'no result';
  is $dom->prepend('l')->prepend('alal')->prepend('a')->type, 'root', 'right type';
  is "$dom",                                                  <<EOF,  'no changes';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
  is $dom->append('lalala')->type, 'root', 'right type';
  is "$dom",                       <<EOF,  'no changes';
<ul>
    24<div>A-1</div>25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>
EOF
  $dom->find('div')->each(sub { shift->append('works') });
  is "$dom", <<EOF, 'right result';
<ul>
    24<div>A-1</div>works25<li>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
  $dom->at('li')->prepend_content('A3<p>A2</p>')->prepend_content('A4');
  is $dom->at('li')->text, 'A4A3A', 'right text';
  is "$dom",               <<EOF,   'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C</li>
</ul>
<div>D</div>works
EOF
  $dom->find('li')->[1]->append_content('<p>C2</p>C3')->append_content(' C4')->append_content('C5');
  is $dom->find('li')->[1]->text, 'CC3 C4C5', 'right text';
  is "$dom",                      <<EOF,      'right result';
<ul>
    24<div>A-1</div>works25<li>A4A3<p>A2</p>A</li><p>A1</p>23
    <p>B</p>
    <li>C<p>C2</p>C3 C4C5</li>
</ul>
<div>D</div>works
EOF
};

subtest 'Optional "head" and "body" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head>
    <title>foo</title>
  <body>bar
EOF
  is $dom->at('html > head > title')->text, 'foo',   'right text';
  is $dom->at('html > body')->text,         "bar\n", 'right text';
};

subtest 'Optional "li" tag' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<ul>
  <li>
    <ol>
      <li>F
      <li>G
    </ol>
  <li>A</li>
  <LI>B
  <li>C</li>
  <li>D
  <li>E
</ul>
EOF
  is $dom->find('ul > li > ol > li')->[0]->text, "F\n      ", 'right text';
  is $dom->find('ul > li > ol > li')->[1]->text, "G\n    ",   'right text';
  is $dom->find('ul > li')->[1]->text,           'A',         'right text';
  is $dom->find('ul > li')->[2]->text,           "B\n  ",     'right text';
  is $dom->find('ul > li')->[3]->text,           'C',         'right text';
  is $dom->find('ul > li')->[4]->text,           "D\n  ",     'right text';
  is $dom->find('ul > li')->[5]->text,           "E\n",       'right text';
};

subtest 'Optional "p" tag' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<div>
  <p>A</p>
  <P>B
  <p>C</p>
  <p>D<div>X</div>
  <p>E<img src="foo.png">
  <p>F<br>G
  <p>H
</div>
EOF
  is $dom->find('div > p')->[0]->text,       'A',       'right text';
  is $dom->find('div > p')->[1]->text,       "B\n  ",   'right text';
  is $dom->find('div > p')->[2]->text,       'C',       'right text';
  is $dom->find('div > p')->[3]->text,       'D',       'right text';
  is $dom->find('div > p')->[4]->text,       "E\n  ",   'right text';
  is $dom->find('div > p')->[5]->text,       "FG\n  ",  'right text';
  is $dom->find('div > p')->[6]->text,       "H\n",     'right text';
  is $dom->find('div > p > p')->[0],         undef,     'no results';
  is $dom->at('div > p > img')->attr->{src}, 'foo.png', 'right attribute';
  is $dom->at('div > div')->text,            'X',       'right text';
};

subtest 'Optional "dt" and "dd" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<dl>
  <dt>A</dt>
  <DD>B
  <dt>C</dt>
  <dd>D
  <dt>E
  <dd>F
</dl>
EOF
  is $dom->find('dl > dt')->[0]->text, 'A',     'right text';
  is $dom->find('dl > dd')->[0]->text, "B\n  ", 'right text';
  is $dom->find('dl > dt')->[1]->text, 'C',     'right text';
  is $dom->find('dl > dd')->[1]->text, "D\n  ", 'right text';
  is $dom->find('dl > dt')->[2]->text, "E\n  ", 'right text';
  is $dom->find('dl > dd')->[2]->text, "F\n",   'right text';
};

subtest 'Optional "rp" and "rt" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<ruby>
  <rp>A</rp>
  <RT>B
  <rp>C</rp>
  <rt>D
  <rp>E
  <rt>F
</ruby>
EOF
  is $dom->find('ruby > rp')->[0]->text, 'A',     'right text';
  is $dom->find('ruby > rt')->[0]->text, "B\n  ", 'right text';
  is $dom->find('ruby > rp')->[1]->text, 'C',     'right text';
  is $dom->find('ruby > rt')->[1]->text, "D\n  ", 'right text';
  is $dom->find('ruby > rp')->[2]->text, "E\n  ", 'right text';
  is $dom->find('ruby > rt')->[2]->text, "F\n",   'right text';
};

subtest 'Optional "optgroup" and "option" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<div>
  <optgroup>A
    <option id="foo">B
    <option>C</option>
    <option>D
  <OPTGROUP>E
    <option>F
  <optgroup>G
    <option>H
</div>
EOF
  is $dom->find('div > optgroup')->[0]->text,          "A\n    \n    ", 'right text';
  is $dom->find('div > optgroup > #foo')->[0]->text,   "B\n    ",       'right text';
  is $dom->find('div > optgroup > option')->[1]->text, 'C',             'right text';
  is $dom->find('div > optgroup > option')->[2]->text, "D\n  ",         'right text';
  is $dom->find('div > optgroup')->[1]->text,          "E\n    ",       'right text';
  is $dom->find('div > optgroup > option')->[3]->text, "F\n  ",         'right text';
  is $dom->find('div > optgroup')->[2]->text,          "G\n    ",       'right text';
  is $dom->find('div > optgroup > option')->[4]->text, "H\n",           'right text';
};

subtest 'Optional "colgroup" tag' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
  <col id=morefail>
  <col id=fail>
  <colgroup>
    <col id=foo>
    <col class=foo>
  <colgroup>
    <col id=bar>
</table>
EOF
  is $dom->find('table > col')->[0]->attr->{id},               'morefail', 'right attribute';
  is $dom->find('table > col')->[1]->attr->{id},               'fail',     'right attribute';
  is $dom->find('table > colgroup > col')->[0]->attr->{id},    'foo',      'right attribute';
  is $dom->find('table > colgroup > col')->[1]->attr->{class}, 'foo',      'right attribute';
  is $dom->find('table > colgroup > col')->[2]->attr->{id},    'bar',      'right attribute';
};

subtest 'Optional "thead", "tbody", "tfoot", "tr", "th" and "td" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
  <thead>
    <tr>
      <th>A</th>
      <th>D
  <tfoot>
    <tr>
      <td>C
  <tbody>
    <tr>
      <td>B
</table>
EOF
  is $dom->at('table > thead > tr > th')->text,        'A',     'right text';
  is $dom->find('table > thead > tr > th')->[1]->text, "D\n  ", 'right text';
  is $dom->at('table > tbody > tr > td')->text,        "B\n",   'right text';
  is $dom->at('table > tfoot > tr > td')->text,        "C\n  ", 'right text';
};

subtest 'Optional "colgroup", "thead", "tbody", "tr", "th" and "td" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
  <col id=morefail>
  <col id=fail>
  <colgroup>
    <col id=foo />
    <col class=foo>
  <colgroup>
    <col id=bar>
  </colgroup>
  <thead>
    <tr>
      <th>A</th>
      <th>D
  <tbody>
    <tr>
      <td>B
  <tbody>
    <tr>
      <td>E
</table>
EOF
  is $dom->find('table > col')->[0]->attr->{id},                     'morefail',   'right attribute';
  is $dom->find('table > col')->[1]->attr->{id},                     'fail',       'right attribute';
  is $dom->find('table > colgroup > col')->[0]->attr->{id},          'foo',        'right attribute';
  is $dom->find('table > colgroup > col')->[1]->attr->{class},       'foo',        'right attribute';
  is $dom->find('table > colgroup > col')->[2]->attr->{id},          'bar',        'right attribute';
  is $dom->at('table > thead > tr > th')->text,                      'A',          'right text';
  is $dom->find('table > thead > tr > th')->[1]->text,               "D\n  ",      'right text';
  is $dom->at('table > tbody > tr > td')->text,                      "B\n  ",      'right text';
  is $dom->find('table > tbody > tr > td')->map('text')->join("\n"), "B\n  \nE\n", 'right text';
};

subtest 'Optional "colgroup", "tbody", "tr", "th" and "td" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
  <colgroup>
    <col id=foo />
    <col class=foo>
  <colgroup>
    <col id=bar>
  </colgroup>
  <tbody>
    <tr>
      <td>B
</table>
EOF
  is $dom->find('table > colgroup > col')->[0]->attr->{id},    'foo', 'right attribute';
  is $dom->find('table > colgroup > col')->[1]->attr->{class}, 'foo', 'right attribute';
  is $dom->find('table > colgroup > col')->[2]->attr->{id},    'bar', 'right attribute';
  is $dom->at('table > tbody > tr > td')->text,                "B\n", 'right text';
};

subtest 'Optional "tr" and "td" tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
    <tr>
      <td>A
      <td>B</td>
    <tr>
      <td>C
    </tr>
    <tr>
      <td>D
</table>
EOF
  is $dom->find('table > tr > td')->[0]->text, "A\n      ", 'right text';
  is $dom->find('table > tr > td')->[1]->text, 'B',         'right text';
  is $dom->find('table > tr > td')->[2]->text, "C\n    ",   'right text';
  is $dom->find('table > tr > td')->[3]->text, "D\n",       'right text';
};

subtest 'Real world table' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head>
    <title>Real World!</title>
  <body>
    <p>Just a test
    <table class=RealWorld>
      <thead>
        <tr>
          <th class=one>One
          <th class=two>Two
          <th class=three>Three
          <th class=four>Four
      <tbody>
        <tr>
          <td class=alpha>Alpha
          <td class=beta>Beta
          <td class=gamma><a href="#gamma">Gamma</a>
          <td class=delta>Delta
        <tr>
          <td class=alpha>Alpha Two
          <td class=beta>Beta Two
          <td class=gamma><a href="#gamma-two">Gamma Two</a>
          <td class=delta>Delta Two
    </table>
EOF
  is $dom->find('html > head > title')->[0]->text,     'Real World!',           'right text';
  is $dom->find('html > body > p')->[0]->text,         "Just a test\n    ",     'right text';
  is $dom->find('p')->[0]->text,                       "Just a test\n    ",     'right text';
  is $dom->find('thead > tr > .three')->[0]->text,     "Three\n          ",     'right text';
  is $dom->find('thead > tr > .four')->[0]->text,      "Four\n      ",          'right text';
  is $dom->find('tbody > tr > .beta')->[0]->text,      "Beta\n          ",      'right text';
  is $dom->find('tbody > tr > .gamma')->[0]->text,     "\n          ",          'no text';
  is $dom->find('tbody > tr > .gamma > a')->[0]->text, 'Gamma',                 'right text';
  is $dom->find('tbody > tr > .alpha')->[1]->text,     "Alpha Two\n          ", 'right text';
  is $dom->find('tbody > tr > .gamma > a')->[1]->text, 'Gamma Two',             'right text';
  my @following
    = $dom->find('tr > td:nth-child(1)')->map(following => ':nth-child(even)')->flatten->map('all_text')->each;
  my $elements = ["Beta\n          ", "Delta\n        ", "Beta Two\n          ", "Delta Two\n    "];
  is_deeply \@following, $elements, 'right results';
};

subtest 'Real world list' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head>
    <title>Real World!</title>
  <body>
    <ul>
      <li>
        Test
        <br>
        123
        <p>

      <li>
        Test
        <br>
        321
        <p>
      <li>
        Test
        3
        2
        1
        <p>
    </ul>
EOF
  is $dom->find('html > head > title')->[0]->text, 'Real World!',                                     'right text';
  is $dom->find('body > ul > li')->[0]->text,      "\n        Test\n        \n        123\n        ", 'right text';
  is $dom->find('body > ul > li > p')->[0]->text,  "\n\n      ",                                      'no text';
  is $dom->find('body > ul > li')->[1]->text,      "\n        Test\n        \n        321\n        ", 'right text';
  is $dom->find('body > ul > li > p')->[1]->text,  "\n      ",                                        'no text';
  is $dom->find('body > ul > li')->[1]->all_text, "\n        Test\n        \n        321\n        \n      ",
    'right text';
  is $dom->find('body > ul > li > p')->[1]->all_text, "\n      ",                                          'no text';
  is $dom->find('body > ul > li')->[2]->text, "\n        Test\n        3\n        2\n        1\n        ", 'right text';
  is $dom->find('body > ul > li > p')->[2]->text,     "\n    ",                                            'no text';
  is $dom->find('body > ul > li')->[2]->all_text,     "\n        Test\n        3\n        2\n        1\n        \n    ";
  is $dom->find('body > ul > li > p')->[2]->all_text, "\n    ", 'no text';
};

subtest 'Advanced whitespace trimming (punctuation)' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head>
    <title>Real World!</title>
  <body>
    <div>foo <strong>bar</strong>.</div>
    <div>foo<strong>, bar</strong>baz<strong>; yada</strong>.</div>
    <div>foo<strong>: bar</strong>baz<strong>? yada</strong>!</div>
EOF
  is $dom->find('html > head > title')->[0]->text, 'Real World!',        'right text';
  is $dom->find('body > div')->[0]->all_text,      'foo bar.',           'right text';
  is $dom->find('body > div')->[1]->all_text,      'foo, barbaz; yada.', 'right text';
  is $dom->find('body > div')->[1]->text,          'foobaz.',            'right text';
  is $dom->find('body > div')->[2]->all_text,      'foo: barbaz? yada!', 'right text';
  is $dom->find('body > div')->[2]->text,          'foobaz!',            'right text';
};

subtest 'Real world JavaScript and CSS' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head>
    <style test=works>#style { foo: style('<test>'); }</style>
    <script>
      if (a < b) {
        alert('<123>');
      }
    </script>
    < sCriPt two="23" >if (b > c) { alert('&<ohoh>') }</scRiPt  >
  <body>Foo!</body>
EOF
  is $dom->find('html > body')->[0]->text,         'Foo!',                             'right text';
  is $dom->find('html > head > style')->[0]->text, "#style { foo: style('<test>'); }", 'right text';
  is $dom->find('html > head > script')->[0]->text, "\n      if (a < b) {\n        alert('<123>');\n      }\n    ",
    'right text';
  is $dom->find('html > head > script')->[1]->text, "if (b > c) { alert('&<ohoh>') }", 'right text';
};

subtest 'More real world JavaScript' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<!DOCTYPE html>
<html>
  <head>
    <title>Foo</title>
    <script src="/js/one.js"></script>
    <script src="/js/two.js"></script>
    <script src="/js/three.js"></script>
  </head>
  <body>Bar</body>
</html>
EOF
  is $dom->at('title')->text,                              'Foo',          'right text';
  is $dom->find('html > head > script')->[0]->attr('src'), '/js/one.js',   'right attribute';
  is $dom->find('html > head > script')->[1]->attr('src'), '/js/two.js',   'right attribute';
  is $dom->find('html > head > script')->[2]->attr('src'), '/js/three.js', 'right attribute';
  is $dom->find('html > head > script')->[2]->text,        '',             'no text';
  is $dom->at('html > body')->text,                        'Bar',          'right text';
};

subtest 'Even more real world JavaScript' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<!DOCTYPE html>
<html>
  <head>
    <title>Foo</title>
    <script src="/js/one.js"></script>
    <script src="/js/two.js"></script>
    <script src="/js/three.js">
  </head>
  <body>Bar</body>
</html>
EOF
  is $dom->at('title')->text,                              'Foo',          'right text';
  is $dom->find('html > head > script')->[0]->attr('src'), '/js/one.js',   'right attribute';
  is $dom->find('html > head > script')->[1]->attr('src'), '/js/two.js',   'right attribute';
  is $dom->find('html > head > script')->[2]->attr('src'), '/js/three.js', 'right attribute';
  is $dom->find('html > head > script')->[2]->text,        "\n  ",         'no text';
  is $dom->at('html > body')->text,                        'Bar',          'right text';
};

subtest 'Inline DTD' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0"?>
<!-- This is a Test! -->
  <!DOCTYPE root [
    <!ELEMENT root (#PCDATA)>
    <!ATTLIST root att CDATA #REQUIRED>
  ]>
<root att="test">
  <![CDATA[<hello>world</hello>]]>
</root>
EOF
  ok $dom->xml, 'XML mode detected';
  is $dom->at('root')->attr('att'), 'test', 'right attribute';
  is $dom->tree->[5][1], ' root [
    <!ELEMENT root (#PCDATA)>
    <!ATTLIST root att CDATA #REQUIRED>
  ]', 'right doctype';
  is $dom->at('root')->text, "\n  <hello>world</hello>\n", 'right text';
  $dom = Mojo::DOM->new(<<EOF);
<!doctype book
  SYSTEM "usr.dtd"
  [
    <!ENTITY test "yeah">
  ]>
<foo />
EOF
  is $dom->tree->[1][1], ' book
  SYSTEM "usr.dtd"
  [
    <!ENTITY test "yeah">
  ]', 'right doctype';
  ok !$dom->xml, 'XML mode not detected';
  is $dom->at('foo'), '<foo></foo>', 'right element';
  $dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0" encoding = 'utf-8'?>
  <!DOCTYPE foo [
    <!ELEMENT foo ANY>
    <!ATTLIST foo xml:lang CDATA #IMPLIED>
    <!ENTITY % e SYSTEM "myentities.ent">
    %myentities;
  ]  >
<foo xml:lang="de">Check!</fOo>
EOF
  ok $dom->xml, 'XML mode detected';
  is $dom->tree->[3][1], ' foo [
    <!ELEMENT foo ANY>
    <!ATTLIST foo xml:lang CDATA #IMPLIED>
    <!ENTITY % e SYSTEM "myentities.ent">
    %myentities;
  ]  ', 'right doctype';
  is $dom->at('foo')->attr->{'xml:lang'}, 'de',       'right attribute';
  is $dom->at('foo')->text,               "Check!\n", 'right text';
  $dom = Mojo::DOM->new(<<EOF);
<!DOCTYPE TESTSUITE PUBLIC "my.dtd" 'mhhh' [
    <!ELEMENT foo ANY>
    <!ATTLIST foo bar ENTITY 'true'>
    <!ENTITY system_entities SYSTEM 'systems.xml'>
    <!ENTITY leertaste '&#32;'>
    <!-- This is a comment -->
    <!NOTATION hmmm SYSTEM "hmmm">
  ]   >
<?check for-nothing?>
<foo bar='false'>&leertaste;!!!</foo>
EOF
  is $dom->tree->[1][1], ' TESTSUITE PUBLIC "my.dtd" \'mhhh\' [
    <!ELEMENT foo ANY>
    <!ATTLIST foo bar ENTITY \'true\'>
    <!ENTITY system_entities SYSTEM \'systems.xml\'>
    <!ENTITY leertaste \'&#32;\'>
    <!-- This is a comment -->
    <!NOTATION hmmm SYSTEM "hmmm">
  ]   ', 'right doctype';
  is $dom->at('foo')->attr('bar'), 'false', 'right attribute';
};

subtest 'Broken "font" block and useless end tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <table>
      <tr><td><font>test</td></font></tr>
      </tr>
    </table>
  </body>
</html>
EOF
  is $dom->at('html > head > title')->text,          'Test', 'right text';
  is $dom->at('html body table tr td > font')->text, 'test', 'right text';
};

subtest 'Different broken "font" block' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <font>
    <table>
      <tr>
        <td>test1<br></td></font>
        <td>test2<br>
    </table>
  </body>
</html>
EOF
  is $dom->at('html > head > title')->text,                         'Test',        'right text';
  is $dom->find('html > body > font > table > tr > td')->[0]->text, 'test1',       'right text';
  is $dom->find('html > body > font > table > tr > td')->[1]->text, "test2\n    ", 'right text';
};

subtest 'Broken "font" and "div" blocks' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <font>
    <div>test1<br>
      <div>test2<br></font>
    </div>
  </body>
</html>
EOF
  is $dom->at('html head title')->text,            'Test',              'right text';
  is $dom->at('html body font > div')->text,       "test1\n      \n  ", 'right text';
  is $dom->at('html body font > div > div')->text, "test2\n    ",       'right text';
};

subtest 'Broken "div" blocks' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
<head><title>Test</title></head>
<body>
  <div>
  <table>
    <tr><td><div>test</td></div></tr>
    </div>
  </table>
</body>
</html>
EOF
  is $dom->at('html head title')->text,                 'Test', 'right text';
  is $dom->at('html body div table tr td > div')->text, 'test', 'right text';
};

subtest 'And another broken "font" block' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head><title>Test</title></head>
  <body>
    <table>
      <tr>
        <td><font><br>te<br>st<br>1</td></font>
        <td>x1<td><img>tes<br>t2</td>
        <td>x2<td><font>t<br>est3</font></td>
      </tr>
    </table>
  </body>
</html>
EOF
  is $dom->at('html > head > title')->text,                   'Test',  'right text';
  is $dom->find('html body table tr > td > font')->[0]->text, 'test1', 'right text';
  is $dom->find('html body table tr > td')->[1]->text,        'x1',    'right text';
  is $dom->find('html body table tr > td')->[2]->text,        'test2', 'right text';
  is $dom->find('html body table tr > td')->[3]->text,        'x2',    'right text';
  is $dom->find('html body table tr > td')->[5],              undef,   'no result';
  is $dom->find('html body table tr > td')->size,             5,       'right number of elements';
  is $dom->find('html body table tr > td > font')->[1]->text, 'test3', 'right text';
  is $dom->find('html body table tr > td > font')->[2],       undef,   'no result';
  is $dom->find('html body table tr > td > font')->size,      2,       'right number of elements';
  is $dom,                                                    <<EOF,   'right result';
<html>
  <head><title>Test</title></head>
  <body>
    <table>
      <tr>
        <td><font><br>te<br>st<br>1</font></td>
        <td>x1</td><td><img>tes<br>t2</td>
        <td>x2</td><td><font>t<br>est3</font></td>
      </tr>
    </table>
  </body>
</html>
EOF
};

subtest 'A collection of wonderful screwups' => sub {
  my $dom = Mojo::DOM->new(<<'EOF');
<!DOCTYPE html>
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
    <b>>la<>la<<>>la<</b>
  </body>
</html>
EOF
  is $dom->at('#screw-up > b')->text,                           '>la<>la<<>>la<', 'right text';
  is $dom->at('#screw-up .ewww > a > img')->attr('src'),        '/test.png',      'right attribute';
  is $dom->find('#screw-up .ewww > a > img')->[1]->attr('src'), '/test2.png',     'right attribute';
  is $dom->find('#screw-up .ewww > a > img')->[2],              undef,            'no result';
  is $dom->find('#screw-up .ewww > a > img')->size,             2,                'right number of elements';
};

subtest 'Broken "br" tag' => sub {
  my $dom = Mojo::DOM->new('<br< abc abc abc abc abc abc abc abc<p>Test</p>');
  is $dom->at('p')->text, 'Test', 'right text';
};

subtest 'Modifying an XML document' => sub {
  my $dom = Mojo::DOM->new(<<'EOF');
<?xml version='1.0' encoding='UTF-8'?>
<XMLTest />
EOF
  ok $dom->xml, 'XML mode detected';
  $dom->at('XMLTest')->content('<Element />');
  my $element = $dom->at('Element');
  is $element->tag, 'Element', 'right tag';
  ok $element->xml, 'XML mode active';
  $element = $dom->at('XMLTest')->children->[0];
  is $element->tag,         'Element', 'right child';
  is $element->parent->tag, 'XMLTest', 'right parent';
  ok $element->root->xml, 'XML mode active';
  $dom->replace('<XMLTest2 /><XMLTest3 just="works" />');
  ok $dom->xml, 'XML mode active';
  $dom->at('XMLTest2')->{foo} = undef;
  is $dom, '<XMLTest2 foo="foo" /><XMLTest3 just="works" />', 'right result';
};

subtest 'Ensure HTML semantics' => sub {
  ok !Mojo::DOM->new->xml(undef)->parse('<?xml version="1.0"?>')->xml, 'XML mode not detected';
  my $dom = Mojo::DOM->new->xml(0)->parse('<?xml version="1.0"?><br><div>Test</div>');
  is $dom->at('div:root')->text, 'Test', 'right text';
};

subtest 'Ensure XML semantics' => sub {
  ok !!Mojo::DOM->new->xml(1)->parse('<foo />')->xml, 'XML mode active';
  my $dom = Mojo::DOM->new(<<'EOF');
<?xml version='1.0' encoding='UTF-8'?>
<script>
  <table>
    <td>
      <tr><thead>foo<thead></tr>
    </td>
    <td>
      <tr><thead>bar<thead></tr>
    </td>
  </table>
</script>
EOF
  is $dom->find('table > td > tr > thead')->[0]->text,          'foo', 'right text';
  is $dom->find('script > table > td > tr > thead')->[1]->text, 'bar', 'right text';
  is $dom->find('table > td > tr > thead')->[2],                undef, 'no result';
  is $dom->find('table > td > tr > thead')->size,               2,     'right number of elements';
};

subtest 'Ensure XML semantics again' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse(<<'EOF');
<table>
  <td>
    <tr><thead>foo<thead></tr>
  </td>
  <td>
    <tr><thead>bar<thead></tr>
  </td>
</table>
EOF
  is $dom->find('table > td > tr > thead')->[0]->text, 'foo', 'right text';
  is $dom->find('table > td > tr > thead')->[1]->text, 'bar', 'right text';
  is $dom->find('table > td > tr > thead')->[2],       undef, 'no result';
  is $dom->find('table > td > tr > thead')->size,      2,     'right number of elements';
};

subtest 'Nested tables' => sub {
  my $dom = Mojo::DOM->new(<<'EOF');
<table id="foo">
  <tr>
    <td>
      <table id="bar">
        <tr>
          <td>baz</td>
        </tr>
      </table>
    </td>
  </tr>
</table>
EOF
  is $dom->find('#foo > tr > td > #bar > tr >td')->[0]->text,   'baz', 'right text';
  is $dom->find('table > tr > td > table > tr >td')->[0]->text, 'baz', 'right text';
};

subtest 'Nested find' => sub {
  my $dom = Mojo::DOM->new->parse(<<EOF);
<c>
  <a>foo</a>
  <b>
    <a>bar</a>
    <c>
      <a>baz</a>
      <d>
        <a>yada</a>
      </d>
    </c>
  </b>
</c>
EOF
  my @results;
  $dom->find('b')->each(sub {
    $_->find('a')->each(sub { push @results, $_->text });
  });
  is_deeply \@results, [qw(bar baz yada)], 'right results';
  @results = ();
  $dom->find('a')->each(sub { push @results, $_->text });
  is_deeply \@results, [qw(foo bar baz yada)], 'right results';
  @results = ();
  $dom->find('b')->each(sub {
    $_->find('c a')->each(sub { push @results, $_->text });
  });
  is_deeply \@results, [qw(baz yada)], 'right results';
  is $dom->at('b')->at('a')->text,   'bar', 'right text';
  is $dom->at('c > b > a')->text,    'bar', 'right text';
  is $dom->at('b')->at('c > b > a'), undef, 'no result';
};

subtest 'Direct hash access to attributes in XML mode' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
  ok $dom->xml, 'XML mode active';
  is $dom->at('a')->{id}, 'one', 'right attribute';
  is_deeply [sort keys %{$dom->at('a')}], ['id'], 'right attributes';
  is $dom->at('a')->at('B')->text, "\n    foo\n    \n    \n  ", 'right text';
  is $dom->at('B')->{class},       'two',                       'right attribute';
  is_deeply [sort keys %{$dom->at('a B')}], [qw(class test)], 'right attributes';
  is $dom->find('a B c')->[0]->text, 'bar',   'right text';
  is $dom->find('a B c')->[0]{id},   'three', 'right attribute';
  is_deeply [sort keys %{$dom->find('a B c')->[0]}], ['id'], 'right attributes';
  is $dom->find('a B c')->[1]->text, 'baz',  'right text';
  is $dom->find('a B c')->[1]{ID},   'four', 'right attribute';
  is_deeply [sort keys %{$dom->find('a B c')->[1]}], ['ID'], 'right attributes';
  is $dom->find('a B c')->[2],  undef, 'no result';
  is $dom->find('a B c')->size, 2,     'right number of elements';
  my @results;
  $dom->find('a B c')->each(sub { push @results, $_->text });
  is_deeply \@results, [qw(bar baz)], 'right results';
  is $dom->find('a B c')->join("\n"), qq{<c id="three">bar</c>\n<c ID="four">baz</c>}, 'right result';
  is_deeply [keys %$dom], [], 'root has no attributes';
  is $dom->find('#nothing')->join, '', 'no result';
};

subtest 'Direct hash access to attributes in HTML mode' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<a id="one">
  <B class="two" test>
    foo
    <c id="three">bar</c>
    <c ID="four">baz</c>
  </B>
</a>
EOF
  ok !$dom->xml, 'XML mode not active';
  is $dom->at('a')->{id}, 'one', 'right attribute';
  is_deeply [sort keys %{$dom->at('a')}], ['id'], 'right attributes';
  is $dom->at('a')->at('b')->text, "\n    foo\n    \n    \n  ", 'right text';
  is $dom->at('b')->{class},       'two',                       'right attribute';
  is_deeply [sort keys %{$dom->at('a b')}], [qw(class test)], 'right attributes';
  is $dom->find('a b c')->[0]->text, 'bar',   'right text';
  is $dom->find('a b c')->[0]{id},   'three', 'right attribute';
  is_deeply [sort keys %{$dom->find('a b c')->[0]}], ['id'], 'right attributes';
  is $dom->find('a b c')->[1]->text, 'baz',  'right text';
  is $dom->find('a b c')->[1]{id},   'four', 'right attribute';
  is_deeply [sort keys %{$dom->find('a b c')->[1]}], ['id'], 'right attributes';
  is $dom->find('a b c')->[2],  undef, 'no result';
  is $dom->find('a b c')->size, 2,     'right number of elements';
  my @results;
  $dom->find('a b c')->each(sub { push @results, $_->text });
  is_deeply \@results, [qw(bar baz)], 'right results';
  is $dom->find('a b c')->join("\n"), qq{<c id="three">bar</c>\n<c id="four">baz</c>}, 'right result';
  is_deeply [keys %$dom], [], 'root has no attributes';
  is $dom->find('#nothing')->join, '', 'no result';
};

subtest 'Append and prepend content' => sub {
  my $dom = Mojo::DOM->new('<a><b>Test<c /></b></a>');
  $dom->at('b')->append_content('<d />');
  is $dom->children->[0]->tag,   'a',    'right tag';
  is $dom->all_text,             'Test', 'right text';
  is $dom->at('c')->parent->tag, 'b',    'right tag';
  is $dom->at('d')->parent->tag, 'b',    'right tag';
  $dom->at('b')->prepend_content('<e>Mojo</e>');
  is $dom->at('e')->parent->tag, 'b',        'right tag';
  is $dom->all_text,             'MojoTest', 'right text';
};

subtest 'Wrap elements' => sub {
  my $dom = Mojo::DOM->new('<a>Test</a>');
  is "$dom",                                                        '<a>Test</a>',        'right result';
  is $dom->wrap('<b></b>')->type,                                   'root',               'right type';
  is "$dom",                                                        '<a>Test</a>',        'no changes';
  is $dom->at('a')->wrap('<b></b>')->type,                          'tag',                'right type';
  is "$dom",                                                        '<b><a>Test</a></b>', 'right result';
  is $dom->at('b')->strip->at('a')->wrap('A')->tag,                 'a',                  'right tag';
  is "$dom",                                                        '<a>Test</a>',        'right result';
  is $dom->at('a')->wrap('<b></b>')->tag,                           'a',                  'right tag';
  is "$dom",                                                        '<b><a>Test</a></b>', 'right result';
  is $dom->at('a')->wrap('C<c><d>D</d><e>E</e></c>F')->parent->tag, 'd',                  'right tag';
  is "$dom", '<b>C<c><d>D<a>Test</a></d><e>E</e></c>F</b>',                               'right result';
};

subtest 'Wrap content' => sub {
  my $dom = Mojo::DOM->new('<a>Test</a>');
  is $dom->at('a')->wrap_content('A')->tag, 'a',                                            'right tag';
  is "$dom",                                '<a>Test</a>',                                  'right result';
  is $dom->wrap_content('<b></b>')->type,   'root',                                         'right type';
  is "$dom",                                '<b><a>Test</a></b>',                           'right result';
  is $dom->at('b')->strip->at('a')->tag('e:a')->wrap_content('1<b c="d"></b>')->tag, 'e:a', 'right tag';
  is "$dom", '<e:a>1<b c="d">Test</b></e:a>',                                               'right result';
  is $dom->at('a')->wrap_content('C<c><d>D</d><e>E</e></c>F')->parent->type, 'root',        'right type';
  is "$dom", '<e:a>C<c><d>D1<b c="d">Test</b></d><e>E</e></c>F</e:a>',                      'right result';
};

subtest 'Broken "div" in "td"' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<table>
  <tr>
    <td><div id="A"></td>
    <td><div id="B"></td>
  </tr>
</table>
EOF
  is $dom->find('table tr td')->[0]->at('div')->{id}, 'A',   'right attribute';
  is $dom->find('table tr td')->[1]->at('div')->{id}, 'B',   'right attribute';
  is $dom->find('table tr td')->[2],                  undef, 'no result';
  is $dom->find('table tr td')->size,                 2,     'right number of elements';
  is "$dom",                                          <<EOF, 'right result';
<table>
  <tr>
    <td><div id="A"></div></td>
    <td><div id="B"></div></td>
  </tr>
</table>
EOF
};

subtest 'Form values' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<form action="/foo">
  <p>Test</p>
  <input type="text" name="a" value="A" />
  <input type="checkbox" name="q">
  <input type="checkbox" checked name="b" value="B">
  <input type="radio" name="r">
  <input type="radio" checked name="c" value="C">
  <input name="s">
  <input type="checkbox" name="t" value="">
  <input type=text name="u">
  <select multiple name="f">
    <option value="F">G</option>
    <optgroup>
      <option>H</option>
      <option selected>I</option>
      <option selected disabled>V</option>
    </optgroup>
    <option value="J" selected>K</option>
    <optgroup disabled>
      <option selected>I2</option>
    </optgroup>
  </select>
  <select name="n"><option>N</option></select>
  <select multiple name="q"><option>Q</option></select>
  <select name="y" disabled>
    <option selected>Y</option>
  </select>
  <select name="d">
    <option selected>R</option>
    <option selected>D</option>
  </select>
  <textarea name="m">M</textarea>
  <button name="o" value="O">No!</button>
  <input type="submit" name="p" value="P" />
</form>
EOF
  is $dom->at('p')->val,                         undef, 'no value';
  is $dom->at('input')->val,                     'A',   'right value';
  is $dom->at('input:checked')->val,             'B',   'right value';
  is $dom->at('input:checked[type=radio]')->val, 'C',   'right value';
  is_deeply $dom->at('select')->val, ['I', 'J'], 'right values';
  is $dom->at('select option')->val,                          'F',   'right value';
  is $dom->at('select optgroup option:not([selected])')->val, 'H',   'right value';
  is $dom->find('select')->[1]->at('option')->val,            'N',   'right value';
  is $dom->find('select')->[1]->val,                          undef, 'no value';
  is $dom->find('select')->[2]->val,                          undef, 'no value';
  is $dom->find('select')->[2]->at('option')->val,            'Q',   'right value';
  is $dom->at('select[disabled]')->val,                       'Y',   'right value';
  is $dom->find('select')->last->val,                         'D',   'right value';
  is $dom->find('select')->last->at('option')->val,           'R',   'right value';
  is $dom->at('textarea')->val,                               'M',   'right value';
  is $dom->at('button')->val,                                 'O',   'right value';
  is $dom->at('form')->find('input')->last->val,              'P',   'right value';
  is $dom->at('input[name=q]')->val,                          'on',  'right value';
  is $dom->at('input[name=r]')->val,                          'on',  'right value';
  is $dom->at('input[name=s]')->val,                          undef, 'no value';
  is $dom->at('input[name=t]')->val,                          '',    'right value';
  is $dom->at('input[name=u]')->val,                          undef, 'no value';
};

subtest 'PoCo example with whitespace-sensitive text' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<?xml version="1.0" encoding="UTF-8"?>
<response>
  <entry>
    <id>1286823</id>
    <displayName>Homer Simpson</displayName>
    <addresses>
      <type>home</type>
      <formatted><![CDATA[742 Evergreen Terrace
Springfield, VT 12345 USA]]></formatted>
    </addresses>
  </entry>
  <entry>
    <id>1286822</id>
    <displayName>Marge Simpson</displayName>
    <addresses>
      <type>home</type>
      <formatted>742 Evergreen Terrace
Springfield, VT 12345 USA</formatted>
    </addresses>
  </entry>
</response>
EOF
  is $dom->find('entry')->[0]->at('displayName')->text,                      'Homer Simpson', 'right text';
  is $dom->find('entry')->[0]->at('id')->text,                               '1286823',       'right text';
  is $dom->find('entry')->[0]->at('addresses')->children('type')->[0]->text, 'home',          'right text';
  is $dom->find('entry')->[0]->at('addresses formatted')->text, "742 Evergreen Terrace\nSpringfield, VT 12345 USA",
    'right text';
  is $dom->find('entry')->[1]->at('displayName')->text,                      'Marge Simpson', 'right text';
  is $dom->find('entry')->[1]->at('id')->text,                               '1286822',       'right text';
  is $dom->find('entry')->[1]->at('addresses')->children('type')->[0]->text, 'home',          'right text';
  is $dom->find('entry')->[1]->at('addresses formatted')->text, "742 Evergreen Terrace\nSpringfield, VT 12345 USA",
    'right text';
  is $dom->find('entry')->[2],  undef, 'no result';
  is $dom->find('entry')->size, 2,     'right number of elements';
};

subtest 'Find attribute with hyphen in name and value' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head><meta http-equiv="content-type" content="text/html"></head>
</html>
EOF
  is $dom->find('[http-equiv]')->[0]{content},                 'text/html', 'right attribute';
  is $dom->find('[http-equiv]')->[1],                          undef,       'no result';
  is $dom->find('[http-equiv="content-type"]')->[0]{content},  'text/html', 'right attribute';
  is $dom->find('[http-equiv="content-type"]')->[1],           undef,       'no result';
  is $dom->find('[http-equiv^="content-"]')->[0]{content},     'text/html', 'right attribute';
  is $dom->find('[http-equiv^="content-"]')->[1],              undef,       'no result';
  is $dom->find('head > [http-equiv$="-type"]')->[0]{content}, 'text/html', 'right attribute';
  is $dom->find('head > [http-equiv$="-type"]')->[1],          undef,       'no result';
};

subtest 'Find "0" attribute value' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<a accesskey="0">Zero</a>
<a accesskey="1">O&gTn&gte</a>
EOF
  is $dom->find('a[accesskey]')->[0]->text,    'Zero',    'right text';
  is $dom->find('a[accesskey]')->[1]->text,    'O&gTn>e', 'right text';
  is $dom->find('a[accesskey]')->[2],          undef,     'no result';
  is $dom->find('a[accesskey=0]')->[0]->text,  'Zero',    'right text';
  is $dom->find('a[accesskey=0]')->[1],        undef,     'no result';
  is $dom->find('a[accesskey^=0]')->[0]->text, 'Zero',    'right text';
  is $dom->find('a[accesskey^=0]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey$=0]')->[0]->text, 'Zero',    'right text';
  is $dom->find('a[accesskey$=0]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey~=0]')->[0]->text, 'Zero',    'right text';
  is $dom->find('a[accesskey~=0]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey*=0]')->[0]->text, 'Zero',    'right text';
  is $dom->find('a[accesskey*=0]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey|=0]')->[0]->text, 'Zero',    'right text';
  is $dom->find('a[accesskey|=0]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey=1]')->[0]->text,  'O&gTn>e', 'right text';
  is $dom->find('a[accesskey=1]')->[1],        undef,     'no result';
  is $dom->find('a[accesskey^=1]')->[0]->text, 'O&gTn>e', 'right text';
  is $dom->find('a[accesskey^=1]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey$=1]')->[0]->text, 'O&gTn>e', 'right text';
  is $dom->find('a[accesskey$=1]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey~=1]')->[0]->text, 'O&gTn>e', 'right text';
  is $dom->find('a[accesskey~=1]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey*=1]')->[0]->text, 'O&gTn>e', 'right text';
  is $dom->find('a[accesskey*=1]')->[1],       undef,     'no result';
  is $dom->find('a[accesskey|=1]')->[0]->text, 'O&gTn>e', 'right text';
  is $dom->find('a[accesskey|=1]')->[1],       undef,     'no result';
  is $dom->at('a[accesskey*="."]'),            undef,     'no result';
};

subtest 'Empty attribute value' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<foo bar=>
  test
</foo>
<bar>after</bar>
EOF
  is $dom->tree->[0],    'root', 'right type';
  is $dom->tree->[1][0], 'tag',  'right type';
  is $dom->tree->[1][1], 'foo',  'right tag';
  is_deeply $dom->tree->[1][2], {bar => ''}, 'right attributes';
  is $dom->tree->[1][4][0], 'text',       'right type';
  is $dom->tree->[1][4][1], "\n  test\n", 'right text';
  is $dom->tree->[3][0],    'tag',        'right type';
  is $dom->tree->[3][1],    'bar',        'right tag';
  is $dom->tree->[3][4][0], 'text',       'right type';
  is $dom->tree->[3][4][1], 'after',      'right text';
  is "$dom",                <<EOF,        'right result';
<foo bar="">
  test
</foo>
<bar>after</bar>
EOF
};

subtest 'Case-insensitive attribute values' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<p class="foo">A</p>
<p class="foo bAr">B</p>
<p class="FOO">C</p>
<p class="foo-bar">D</p>
EOF
  is $dom->find('.foo')->map('text')->join(','),                'A,B',     'right result';
  is $dom->find('.FOO')->map('text')->join(','),                'C',       'right result';
  is $dom->find('[class=foo]')->map('text')->join(','),         'A',       'right result';
  is $dom->find('[class=foo s]')->map('text')->join(','),       'A',       'right result';
  is $dom->find('[class=foo S]')->map('text')->join(','),       'A',       'right result';
  is $dom->find('[class=foo i]')->map('text')->join(','),       'A,C',     'right result';
  is $dom->find('[class="foo" i]')->map('text')->join(','),     'A,C',     'right result';
  is $dom->find('[class="foo" I]')->map('text')->join(','),     'A,C',     'right result';
  is $dom->find('[class="foo bar"]')->size,                     0,         'no results';
  is $dom->find('[class="foo bar s"]')->size,                   0,         'no results';
  is $dom->find('[class="foo bar S"]')->size,                   0,         'no results';
  is $dom->find('[class="foo bar" i]')->map('text')->join(','), 'B',       'right result';
  is $dom->find('[class~=foo]')->map('text')->join(','),        'A,B',     'right result';
  is $dom->find('[class~=foo s]')->map('text')->join(','),      'A,B',     'right result';
  is $dom->find('[class~=foo i]')->map('text')->join(','),      'A,B,C',   'right result';
  is $dom->find('[class*=f]')->map('text')->join(','),          'A,B,D',   'right result';
  is $dom->find('[class*=f s]')->map('text')->join(','),        'A,B,D',   'right result';
  is $dom->find('[class*=f i]')->map('text')->join(','),        'A,B,C,D', 'right result';
  is $dom->find('[class^=F]')->map('text')->join(','),          'C',       'right result';
  is $dom->find('[class^=F S]')->map('text')->join(','),        'C',       'right result';
  is $dom->find('[class^=F i]')->map('text')->join(','),        'A,B,C,D', 'right result';
  is $dom->find('[class^=F I]')->map('text')->join(','),        'A,B,C,D', 'right result';
  is $dom->find('[class$=O]')->map('text')->join(','),          'C',       'right result';
  is $dom->find('[class$=O i]')->map('text')->join(','),        'A,C',     'right result';
  is $dom->find('[class|=foo]')->map('text')->join(','),        'A,D',     'right result';
  is $dom->find('[class|=foo i]')->map('text')->join(','),      'A,C,D',   'right result';
};

subtest 'Nested description lists' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<dl>
  <dt>A</dt>
  <DD>
    <dl>
      <dt>B
      <dd>C
    </dl>
  </dd>
</dl>
EOF
  is $dom->find('dl > dd > dl > dt')->[0]->text, "B\n      ", 'right text';
  is $dom->find('dl > dd > dl > dd')->[0]->text, "C\n    ",   'right text';
  is $dom->find('dl > dt')->[0]->text,           'A',         'right text';
};

subtest 'Nested lists' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<div>
  <ul>
    <li>
      A
      <ul>
        <li>B</li>
        C
      </ul>
    </li>
  </ul>
</div>
EOF
  is $dom->find('div > ul > li')->[0]->text, "\n      A\n      \n    ",       'right text';
  is $dom->find('div > ul > li')->[1],       undef,                           'no result';
  is $dom->find('div > ul li')->[0]->text,   "\n      A\n      \n    ",       'right text';
  is $dom->find('div > ul li')->[1]->text,   'B',                             'right text';
  is $dom->find('div > ul li')->[2],         undef,                           'no result';
  is $dom->find('div > ul ul')->[0]->text,   "\n        \n        C\n      ", 'right text';
  is $dom->find('div > ul ul')->[1],         undef,                           'no result';
};

subtest 'Unusual order' => sub {
  my $dom = Mojo::DOM->new('<a href="http://example.com" id="foo" class="bar">Ok!</a>');
  is $dom->at('a:not([href$=foo])[href^=h]')->text,       'Ok!', 'right text';
  is $dom->at('a:not([href$=example.com])[href^=h]'),     undef, 'no result';
  is $dom->at('a[href^=h]#foo.bar')->text,                'Ok!', 'right text';
  is $dom->at('a[href^=h]#foo.baz'),                      undef, 'no result';
  is $dom->at('a[href^=h]#foo:not(b)')->text,             'Ok!', 'right text';
  is $dom->at('a[href^=h]#foo:not(a)'),                   undef, 'no result';
  is $dom->at('[href^=h].bar:not(b)[href$=m]#foo')->text, 'Ok!', 'right text';
  is $dom->at('[href^=h].bar:not(b)[href$=m]#bar'),       undef, 'no result';
  is $dom->at(':not(b)#foo#foo')->text,                   'Ok!', 'right text';
  is $dom->at(':not(b)#foo#bar'),                         undef, 'no result';
  is $dom->at(':not([href^=h]#foo#bar)')->text,           'Ok!', 'right text';
  is $dom->at(':not([href^=h]#foo#foo)'),                 undef, 'no result';
};

subtest 'Slash between attributes' => sub {
  my $dom = Mojo::DOM->new('<input /type=checkbox / value="/a/" checked/><br/>');
  is_deeply $dom->at('input')->attr, {type => 'checkbox', value => '/a/', checked => undef}, 'right attributes';
  is "$dom", '<input checked type="checkbox" value="/a/"><br>', 'right result';
};

subtest 'Dot and hash in class and id attributes' => sub {
  my $dom = Mojo::DOM->new('<p class="a#b.c">A</p><p id="a#b.c">B</p>');
  is $dom->at('p.a\#b\.c')->text,       'A', 'right text';
  is $dom->at(':not(p.a\#b\.c)')->text, 'B', 'right text';
  is $dom->at('p#a\#b\.c')->text,       'B', 'right text';
  is $dom->at(':not(p#a\#b\.c)')->text, 'A', 'right text';
};

subtest 'Extra whitespace' => sub {
  my $dom = Mojo::DOM->new('< span>a< /span><b >b</b><span >c</ span>');
  is $dom->at('span')->text,     'a',                                    'right text';
  is $dom->at('span + b')->text, 'b',                                    'right text';
  is $dom->at('b + span')->text, 'c',                                    'right text';
  is "$dom",                     '<span>a</span><b>b</b><span>c</span>', 'right result';
};

subtest 'Selectors with leading and trailing whitespace' => sub {
  my $dom = Mojo::DOM->new('<div id=foo><b>works</b></div>');
  is $dom->at(' div   b ')->text,          'works', 'right text';
  is $dom->at('  :not(  #foo  )  ')->text, 'works', 'right text';
};

subtest '"0"' => sub {
  my $dom = Mojo::DOM->new('0');
  is "$dom", '0', 'right result';
  $dom->append_content('☃');
  is "$dom",                       '0☃',            'right result';
  is $dom->parse('<!DOCTYPE 0>'),  '<!DOCTYPE 0>',  'successful roundtrip';
  is $dom->parse('<!--0-->'),      '<!--0-->',      'successful roundtrip';
  is $dom->parse('<![CDATA[0]]>'), '<![CDATA[0]]>', 'successful roundtrip';
  is $dom->parse('<?0?>'),         '<?0?>',         'successful roundtrip';
};

subtest 'Not self-closing' => sub {
  my $dom = Mojo::DOM->new('<div />< div ><pre />test</div >123');
  is $dom->at('div > div > pre')->text, 'test',                                     'right text';
  is "$dom",                            '<div><div><pre>test</pre></div>123</div>', 'right result';
  $dom = Mojo::DOM->new('<p /><svg><circle /><circle /></svg>');
  is $dom->find('p > svg > circle')->size, 2,                                                      'two circles';
  is "$dom",                               '<p><svg><circle></circle><circle></circle></svg></p>', 'right result';
};

subtest 'Auto-close tag' => sub {
  my $dom = Mojo::DOM->new('<p><div />');
  is "$dom", '<p></p><div></div>', 'right result';
};

subtest 'No auto-close in scope' => sub {
  my $dom = Mojo::DOM->new('<p><svg><div /></svg>');
  is "$dom", '<p><svg><div></div></svg></p>', 'with SVG';
  $dom = Mojo::DOM->new('<p><math><div /></math>');
  is "$dom", '<p><math><div></div></math></p>', 'with MathML';
};

subtest 'Auto-close scope' => sub {
  my $dom = Mojo::DOM->new('<p><svg></p>');
  is "$dom", '<p><svg></svg></p>', 'closing tag';
  $dom = Mojo::DOM->new('<p><math>');
  is "$dom", '<p><math></math></p>', 'close eof';
};

subtest '"image"' => sub {
  my $dom = Mojo::DOM->new('<image src="foo.png">test');
  is $dom->at('img')->{src}, 'foo.png',                 'right attribute';
  is "$dom",                 '<img src="foo.png">test', 'right result';
};

subtest '"title"' => sub {
  my $dom = Mojo::DOM->new('<title> <p>test&lt;</title>');
  is $dom->at('title')->text, ' <p>test<',                'right text';
  is "$dom",                  '<title> <p>test<</title>', 'right result';
};

subtest '"textarea"' => sub {
  my $dom = Mojo::DOM->new('<textarea id="a"> <p>test&lt;</textarea>');
  is $dom->at('textarea#a')->text, ' <p>test<',                             'right text';
  is "$dom",                       '<textarea id="a"> <p>test<</textarea>', 'right result';
};

subtest 'Comments' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<!-- HTML5 -->
<!-- bad idea -- HTML5 -->
<!-- HTML4 -- >
<!-- bad idea -- HTML4 -- >
EOF
  is $dom->tree->[1][1], ' HTML5 ',             'right comment';
  is $dom->tree->[3][1], ' bad idea -- HTML5 ', 'right comment';
  is $dom->tree->[5][1], ' HTML4 ',             'right comment';
  is $dom->tree->[7][1], ' bad idea -- HTML4 ', 'right comment';
};

subtest 'Huge number of attributes' => sub {
  my $dom = Mojo::DOM->new('<div ' . ('a=b ' x 32768) . '>Test</div>');
  is $dom->at('div[a=b]')->text, 'Test', 'right text';
};

subtest 'Huge number of nested tags' => sub {
  my $huge = ('<a>' x 100) . 'works' . ('</a>' x 100);
  my $dom  = Mojo::DOM->new($huge);
  is $dom->all_text, 'works', 'right text';
  is "$dom",         $huge,   'right result';
};

subtest 'Namespace' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse(<<EOF);
<tag xmlns:myns="coolns">
  <this>foo</this>
  <myns:this>bar</myns:this>
</tag>
EOF
  my %ns = (cool => 'coolns');
  is_deeply $dom->find('cool|this', %ns)->map('text'), ['bar'],        'right result';
  is_deeply $dom->find('cool|*',    %ns)->map('text'), ['bar'],        'right result';
  is_deeply $dom->find('|this',     %ns)->map('text'), ['foo'],        'right result';
  is_deeply $dom->find('*|this',    %ns)->map('text'), ['foo', 'bar'], 'right result';
  ok !$dom->at('foo|*'), 'no result';
};

subtest 'Namespace declaration on the same tag' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse('<x:tag xmlns:x="ns" foo="bar" />');
  is $dom->at('ns|tag', ns => 'ns')->{foo}, 'bar', 'right result';
};

subtest 'Explicit no namespace' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse('<foo xmlns=""><bar /></foo>');
  ok $dom->at('|bar'), 'result';
};

subtest 'Nested namespaces' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse(<<EOF);
<foo xmlns="ns:foo">
  <tag val="1" />
  <bar xmlns="ns:bar">
    <tag val="2" />
    <baz />
    <yada hreflang="en-US">YADA</yada>
  </bar>
</foo>
EOF
  my %ns = (foons => 'ns:foo', barns => 'ns:bar');
  ok $dom->at('foons|foo',                                          %ns), 'result';
  ok $dom->at('foons|foo:not(barns|*)',                             %ns), 'result';
  ok $dom->at('foo:not(|foo)',                                      %ns), 'result';
  ok $dom->at('foons|foo:root',                                     %ns), 'result';
  ok $dom->at('foo:is(:root, foons|*)',                             %ns), 'result';
  ok !$dom->at('foons|foo:not(:root)',                              %ns), 'no result';
  is $dom->at('foons|tag',                                          %ns)->{val}, 1, 'right value';
  is $dom->at('foons|tag:empty',                                    %ns)->{val}, 1, 'right value';
  ok $dom->at('foons|tag[val="1"]',                                 %ns), 'result';
  ok $dom->at('foons|tag[val="1"]:empty',                           %ns), 'result';
  ok $dom->at('foo > foons|tag[val="1"]',                           %ns), 'result';
  ok $dom->at('foons|foo > foons|tag[val="1"]',                     %ns), 'result';
  ok $dom->at('foo foons|tag[val="1"]',                             %ns), 'result';
  ok $dom->at('foons|foo foons|tag[val="1"]',                       %ns), 'result';
  ok $dom->at('barns|bar',                                          %ns), 'result';
  ok $dom->at('barns|bar:not(foons|*)',                             %ns), 'result';
  ok $dom->at('bar:not(|bar)',                                      %ns), 'result';
  ok $dom->at('bar:is(barns|*)',                                    %ns), 'result';
  ok !$dom->at('barns|bar:root',                                    %ns), 'no result';
  ok $dom->at('barns|bar:not(:root)',                               %ns), 'result';
  ok $dom->at('bar:is(barns|*, :not(:root))',                       %ns), 'result';
  ok $dom->at('foons|foo barns|bar',                                %ns), 'result';
  is $dom->at('barns|tag',                                          %ns)->{val}, 2, 'right value';
  is $dom->at('barns|tag:empty',                                    %ns)->{val}, 2, 'right value';
  ok $dom->at('barns|tag[val="2"]',                                 %ns), 'result';
  ok $dom->at('barns|tag[val="2"]:empty',                           %ns), 'result';
  ok $dom->at('bar > barns|tag[val="2"]',                           %ns), 'result';
  ok $dom->at('barns|bar > barns|tag[val="2"]',                     %ns), 'result';
  ok $dom->at('bar barns|tag[val="2"]',                             %ns), 'result';
  ok $dom->at('barns|bar barns|tag[val="2"]',                       %ns), 'result';
  ok $dom->at('foons|foo barns|bar baz',                            %ns), 'result';
  ok $dom->at('foons|foo barns|bar barns|baz',                      %ns), 'result';
  ok $dom->at('foons|foo barns|bar barns|tag[val="2"] + baz',       %ns), 'result';
  ok $dom->at('foons|foo barns|bar barns|tag[val="2"] + barns|baz', %ns), 'result';
  ok $dom->at('foons|foo barns|bar barns|tag[val="2"] ~ baz',       %ns), 'result';
  ok $dom->at('foons|foo barns|bar barns|tag[val="2"] ~ barns|baz', %ns), 'result';
  ok !$dom->at('foons|bar',                                         %ns), 'no result';
  ok !$dom->at('foons|baz',                                         %ns), 'no result';
  ok $dom->at('baz')->matches('barns|*', %ns), 'match';
  is $dom->at('barns|bar [hreflang|=en]',          %ns)->text, 'YADA', 'right text';
  is $dom->at('barns|bar [hreflang|=en-US]',       %ns)->text, 'YADA', 'right text';
  ok !$dom->at('barns|bar [hreflang|=en-US-yada]', %ns), 'no result';
  ok !$dom->at('barns|bar [hreflang|=e]',          %ns), 'no result';
};

subtest 'No more content' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
  <body>
    <select>
      <option>A
      <option>B
    </select>
    <textarea>C</textarea>
  </body>
EOF
  is $dom->find('body > select > option')->[0]->text, "A\n      ", 'right text';
  is $dom->find('body > select > option')->[1]->text, "B\n    ",   'right text';
  is $dom->at('body > textarea')->text,               'C',         'right text';

  $dom = Mojo::DOM->new(<<EOF);
  <body>
    <select>
      <optgroup>
        <option>A
        <option>B
    </select>
    <textarea>C</textarea>
  </body>
EOF
  is $dom->find('body > select > optgroup > option')->[0]->text, "A\n        ", 'right text';
  is $dom->find('body > select > optgroup > option')->[1]->text, "B\n    ",     'right text';
  is $dom->at('body > textarea')->text,                          'C',           'right text';

  $dom = Mojo::DOM->new(<<EOF);
  <body>
    <ul>
      <li>A
      <li>B
    </ul>
    <textarea>C</textarea>
  </body>
EOF
  is $dom->find('body > ul > li')->[0]->text, "A\n      ", 'right text';
  is $dom->find('body > ul > li')->[1]->text, "B\n    ",   'right text';
  is $dom->at('body > textarea')->text,       'C',         'right text';

  $dom = Mojo::DOM->new(<<EOF);
  <body>
    <dl>
      <dd>A
      <dd>B
    </dl>
    <textarea>C</textarea>
  </body>
EOF
  is $dom->find('body > dl > dd')->[0]->text, "A\n      ", 'right text';
  is $dom->find('body > dl > dd')->[1]->text, "B\n    ",   'right text';
  is $dom->at('body > textarea')->text,       'C',         'right text';

  $dom = Mojo::DOM->new(<<EOF);
  <body>
    <ruby>
      <rp>A
      <rt>B
    </ruby>
    <textarea>C</textarea>
  </body>
EOF
  is $dom->at('body > ruby > rp')->text, "A\n      ", 'right text';
  is $dom->at('body > ruby > rt')->text, "B\n    ",   'right text';
  is $dom->at('body > textarea')->text,  'C',         'right text';

  $dom = Mojo::DOM->new(<<EOF);
  <body>
    <ruby>
      <rt>A
      <rp>B
    </ruby>
    <textarea>C</textarea>
  </body>
EOF
  is $dom->at('body > ruby > rt')->text, "A\n      ", 'right text';
  is $dom->at('body > ruby > rp')->text, "B\n    ",   'right text';
  is $dom->at('body > textarea')->text,  'C',         'right text';
};

subtest 'Exclude "<script>" and "<style>" from text extraction in HTML documents' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
  <html>
    <head>
      <title>Hello</title>
      <script>123</script>
      <style>456</style>
    </head>
    <body>
      <script>123</script>
      <div>Mojo!</div>
      <style>456</style>
    </body>
  <html>
EOF
  like $dom->at('html')->all_text,   qr/Hello.*Mojo!/s, 'title and div';
  unlike $dom->at('html')->all_text, qr/123/,           'no script';
  unlike $dom->at('html')->all_text, qr/456/,           'no style';
  like $dom->at('script')->text,     qr/123/,           'script text';
  like $dom->at('style')->text,      qr/456/,           'style text';

  $dom = Mojo::DOM->new(<<EOF);
  <?xml version="1.0" encoding="UTF-8"?>
  <foo>
    <title>Hello</title>
    <script>123</script>
    <style>456</style>
   </foo>
EOF
  like $dom->at('foo')->all_text, qr/Hello.*123.*456/s, 'everything';
  like $dom->at('script')->text,  qr/123/,              'script text';
  like $dom->at('style')->text,   qr/456/,              'style text';
};

subtest 'Reusing fragments' => sub {
  my $fragment = Mojo::DOM->new('<a><b>C</b></a>');
  my $dom      = Mojo::DOM->new('<div></div>');
  is $fragment, '<a><b>C</b></a>', 'right result';
  $dom->at('div')->append($fragment);
  $dom->at('div')->append($fragment);
  is $dom,      '<div></div><a><b>C</b></a><a><b>C</b></a>', 'right result';
  is $fragment, '<a><b>C</b></a>',                           'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->append_content($fragment);
  $dom->at('div')->append_content($fragment);
  is $dom,      '<div><a><b>C</b></a><a><b>C</b></a></div>', 'right result';
  is $fragment, '<a><b>C</b></a>',                           'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->content($fragment);
  $dom->at('div a')->content($fragment);
  is $dom,      '<div><a><a><b>C</b></a></a></div>', 'right result';
  is $fragment, '<a><b>C</b></a>',                   'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->prepend($fragment);
  $dom->at('div')->prepend($fragment);
  is $dom,      '<a><b>C</b></a><a><b>C</b></a><div></div>', 'right result';
  is $fragment, '<a><b>C</b></a>',                           'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->prepend_content($fragment);
  $dom->at('div')->prepend_content($fragment);
  is $dom,      '<div><a><b>C</b></a><a><b>C</b></a></div>', 'right result';
  is $fragment, '<a><b>C</b></a>',                           'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->replace($fragment);
  $dom->at('b')->replace($fragment);
  is $dom,      '<a><a><b>C</b></a></a>', 'right result';
  is $fragment, '<a><b>C</b></a>',        'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->wrap($fragment);
  $dom->at('b')->wrap($fragment);
  is $dom,      '<a><a><b>C<b>C<div></div></b></b></a></a>', 'right result';
  is $fragment, '<a><b>C</b></a>',                           'right result';
  $dom = Mojo::DOM->new('<div></div>');
  $dom->at('div')->wrap_content($fragment);
  $dom->at('b')->wrap_content($fragment);
  is $dom,      '<div><a><b><a><b>CC</b></a></b></a></div>', 'right result';
  is $fragment, '<a><b>C</b></a>',                           'right result';
};

subtest 'Generate tags' => sub {
  is(Mojo::DOM->new_tag('br')->to_string,                                '<br>',                        'right result');
  is(Mojo::DOM->new_tag('div')->to_string,                               '<div></div>',                 'right result');
  is(Mojo::DOM->new_tag('div', id => 'foo', hidden => undef)->to_string, '<div hidden id="foo"></div>', 'right result');
  is(Mojo::DOM->new_tag('div', 'safe & content'), '<div>safe &amp; content</div>',                      'right result');
  is(Mojo::DOM->new_tag('div', id => 'foo', 'safe & content'), '<div id="foo">safe &amp; content</div>',
    'right result');
  is(
    Mojo::DOM->new_tag('div', id => 'foo', data => {foo => 0, Bar => 'test'}, 'safe & content'),
    '<div data-bar="test" data-foo="0" id="foo">safe &amp; content</div>',
    'right result'
  );
  is(Mojo::DOM->new_tag('div', sub {'unsafe & content'}), '<div>unsafe & content</div>', 'right result');
  is(
    Mojo::DOM->new_tag('div', id => 'foo', sub {'unsafe & content'}),
    '<div id="foo">unsafe & content</div>',
    'right result'
  );
  is(Mojo::DOM->new->new_tag('foo', hidden => undef),         '<foo hidden></foo>',      'right result');
  is(Mojo::DOM->new->xml(1)->new_tag('foo', hidden => undef), '<foo hidden="hidden" />', 'right result');
  my $dom = Mojo::DOM->new('<div>Test</div>');
  my $br  = $dom->new_tag('br');
  $dom->at('div')->append_content($br)->append_content($br);
  is $dom,                                   '<div>Test<br><br></div>', 'right result';
  is tag_to_html('div', id => 'foo', 'bar'), '<div id="foo">bar</div>', 'right result';
};

subtest 'Generate selector' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<html>
  <head>
    <title>Test</title>
  </head>
  <body>
    <p id="a">A</p>
    <p id="b">B</p>
    <p id="c">C</p>
    <p id="d">D</p>
  </body>
<html>
EOF
  is $dom->selector,                               undef,                                       'not a tag';
  is $dom->at('#a')->child_nodes->first->selector, undef,                                       'not a tag';
  is $dom->at('#a')->selector, 'html:nth-child(1) > body:nth-child(2) > p:nth-child(1)',        'right selector';
  is $dom->at($dom->at('#a')->selector)->text, 'A',                                             'right text';
  is $dom->at('#b')->selector, 'html:nth-child(1) > body:nth-child(2) > p:nth-child(2)',        'right selector';
  is $dom->at($dom->at('#b')->selector)->text, 'B',                                             'right text';
  is $dom->at('#c')->selector, 'html:nth-child(1) > body:nth-child(2) > p:nth-child(3)',        'right selector';
  is $dom->at($dom->at('#c')->selector)->text, 'C',                                             'right text';
  is $dom->at('#d')->selector, 'html:nth-child(1) > body:nth-child(2) > p:nth-child(4)',        'right selector';
  is $dom->at($dom->at('#d')->selector)->text, 'D',                                             'right text';
  is $dom->at('title')->selector, 'html:nth-child(1) > head:nth-child(1) > title:nth-child(1)', 'right selector';
  is $dom->at($dom->at('title')->selector)->text, 'Test',                                       'right text';
  is $dom->at('html')->selector,                  'html:nth-child(1)',                          'right selector';
};

subtest 'Reusing partial DOM trees' => sub {
  my $dom = Mojo::DOM->new->parse('<div><b>Test</b></div>');
  is $dom->at('div')->prepend($dom->at('b'))->root, '<b>Test</b><div><b>Test</b></div>', 'right result';
};

subtest 'Real world table with optional elements' => sub {
  my $dom = Mojo::DOM->new->parse(<<EOF);
<!DOCTYPE html>
<html lang="en">
  <body>
    <table class="table table-striped">
      <thead>
        <tr>
          <th>key</th>
          <th>secret</th>
          <th>expires</th>
          <th>action</th>
      </thead>
      <tbody>
        <tr id="api_key_4">
          <td class="key">PERCIVALKEY01</td>
          <td class="secret">PERCIVALSECRET01</td>
          <td class="expiration">2020-06-18 11:12:03 +0000</td>
        <tr id="api_key_5">
          <td class="key">PERCIVALKEY02</td>
          <td class="secret">PERCIVALSECRET02</td>
          <td class="expiration">never</td>
      </tbody>
    </table>
  </body>
</html>
EOF
  is $dom->at('thead tr th')->text,            'key',                       'right text';
  is $dom->at('#api_key_4 .key')->text,        'PERCIVALKEY01',             'right text';
  is $dom->at('#api_key_4 .secret')->text,     'PERCIVALSECRET01',          'right text';
  is $dom->at('#api_key_4 .expiration')->text, '2020-06-18 11:12:03 +0000', 'right text';
  is $dom->at('#api_key_5 .expiration')->text, 'never',                     'right text';
};

subtest 'Root pseudo-class' => sub {
  my $dom = Mojo::DOM->new('<html><head></head><body><div><div>x</div></div></body></html>');
  is $dom->find('body > :first-child > :first-child')->first->text, 'x',   'right text';
  is $dom->at(':scope:first-child'),                                undef, 'no result';
};

subtest 'Runaway "<"' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
    <table>
      <tr>
        <td>
          <div class="test" data-id="123" data-score="3">works</div>
          TEST 123<br />
          Test  12-34-5 test  >= 75% and < 85%  test<br />
          Test  12-34-5  -test foo >= 5% and < 30% test<br />
          Test  12-23-4 n/a >=13% and = 1% and < 5% test tset<br />
          Test  12-34-5  test >= 1% and < 5%   foo, bar, baz<br />
          Test foo, bar, baz  123-456-78  test < 1%  foo, bar, baz yada, foo, bar and baz, yada
        </td>
      </tr>
    </table>
EOF
  is $dom->at('.test')->text, 'works', 'right text';
};

subtest 'XML name characters' => sub {
  my $dom = Mojo::DOM->new->xml(1)->parse('<Foo><1a>foo</1a></Foo>');
  is $dom->at('Foo')->text, '<1a>foo</1a>',                        'right text';
  is "$dom",                '<Foo>&lt;1a&gt;foo&lt;/1a&gt;</Foo>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<Foo><.a>foo</.a></Foo>');
  is $dom->at('Foo')->text, '<.a>foo</.a>',                        'right text';
  is "$dom",                '<Foo>&lt;.a&gt;foo&lt;/.a&gt;</Foo>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<Foo><.>foo</.></Foo>');
  is $dom->at('Foo')->text, '<.>foo</.>',                        'right text';
  is "$dom",                '<Foo>&lt;.&gt;foo&lt;/.&gt;</Foo>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<Foo><-a>foo</-a></Foo>');
  is $dom->at('Foo')->text, '<-a>foo</-a>',                        'right text';
  is "$dom",                '<Foo>&lt;-a&gt;foo&lt;/-a&gt;</Foo>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<Foo><a1>foo</a1></Foo>');
  is $dom->at('Foo a1')->text, 'foo',                     'right text';
  is "$dom",                   '<Foo><a1>foo</a1></Foo>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<Foo><a .b -c 1>foo</a></Foo>');
  is $dom->at('Foo')->text, '<a .b -c 1>foo',                  'right text';
  is "$dom",                '<Foo>&lt;a .b -c 1&gt;foo</Foo>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<😄 😄="😄">foo</😄>');
  is $dom->at('😄')->text, 'foo',              'right text';
  is "$dom",              '<😄 😄="😄">foo</😄>', 'right result';

  $dom = Mojo::DOM->new->xml(1)->parse('<こんにちは こんにちは="こんにちは">foo</こんにちは>');
  is $dom->at('こんにちは')->text, 'foo',                              'right text';
  is "$dom",                  '<こんにちは こんにちは="こんにちは">foo</こんにちは>', 'right result';
};

subtest 'Script end tags' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
    <!DOCTYPE html>
    <h1>Welcome to HTML</h1>
    <script>
        console.log('< /script> is safe');
        /* <div>XXX this is not a div element</div> */
    </script>
EOF
  like $dom->at('script')->text, qr/console\.log.+< \/script>.+this is not a div element/s, 'right text';

  $dom = Mojo::DOM->new(<<EOF);
    <!DOCTYPE html>
    <h1>Welcome to HTML</h1>
    <script>
        console.log('this is a script element and should be executed');
    // </script asdf> <p>
        console.log('this is not a script');
        // <span data-wtf="</script>">:-)</span>
EOF
  like $dom->at('script')->text, qr/console\.log.+executed.+\/\//s,       'right text';
  like $dom->at('p')->text,      qr/console\.log.+this is not a script/s, 'right text';
  is $dom->at('span')->text, ':-)', 'right text';

  $dom = Mojo::DOM->new(<<EOF);
    <!DOCTYPE html>
    <h1>Welcome to HTML</h1>
    <div>
      <script> console.log('</scriptxyz is safe'); </script>
    </div>
EOF
  like $dom->at('script')->text, qr/console\.log.+scriptxyz is safe/s, 'right text';
  like $dom->at('div')->text,    qr/^\s+$/s,                           'right text';
};

subtest 'Unknown CSS selector' => sub {
  my $dom = Mojo::DOM->new('<html><head></head><body><div><div>x</div></div></body></html>');
  eval { $dom->at('div[') };
  like $@, qr/Unknown CSS selector: div\[/, 'right error';
  eval { $dom->find('p[') };
  like $@, qr/Unknown CSS selector: p\[/, 'right error';
};

subtest 'Handle tab in selector' => sub {
  my $dom = Mojo::DOM->new(<<EOF);
<!DOCTYPE html>
<ul> <li>Ax1</li> </ul>
EOF
  for my $selector ("ul li", "ul\tli", "ul \tli", "ul\t li") {
    is_deeply $dom->find($selector)->map(sub { $_->to_string })->to_array, ['<li>Ax1</li>'],
      'selector "' . $selector =~ s/\t/\\t/r . '"';
  }
};

done_testing();
