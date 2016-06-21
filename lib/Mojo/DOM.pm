package Mojo::DOM;
use Mojo::Base -strict;
use overload
  '@{}'    => sub { shift->child_nodes },
  '%{}'    => sub { shift->attr },
  bool     => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

# "Fry: This snow is beautiful. I'm glad global warming never happened.
#  Leela: Actually, it did. But thank God nuclear winter canceled it out."
use Carp 'croak';
use Mojo::Collection;
use Mojo::DOM::CSS;
use Mojo::DOM::HTML;
use Scalar::Util qw(blessed weaken);

sub all_text { _text([_nodes(shift->tree)], 1) }

sub ancestors { _select($_[0]->_collect($_[0]->_ancestors), $_[1]) }

sub append { shift->_add(1, @_) }
sub append_content { shift->_content(1, 0, @_) }

sub at {
  my $self = shift;
  return undef unless my $result = $self->_css->select_one(@_);
  return $self->_build($result, $self->xml);
}

sub attr {
  my $self = shift;

  # Hash
  my $tree = $self->tree;
  my $attrs = $tree->[0] ne 'tag' ? {} : $tree->[2];
  return $attrs unless @_;

  # Get
  return $attrs->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  @$attrs{keys %$values} = values %$values;

  return $self;
}

sub child_nodes { $_[0]->_collect(_nodes($_[0]->tree)) }

sub children { _select($_[0]->_collect(_nodes($_[0]->tree, 1)), $_[1]) }

sub content {
  my $self = shift;

  my $type = $self->type;
  if ($type eq 'root' || $type eq 'tag') {
    return $self->_content(0, 1, @_) if @_;
    my $html = Mojo::DOM::HTML->new(xml => $self->xml);
    return join '', map { $html->tree($_)->render } _nodes($self->tree);
  }

  return $self->tree->[1] unless @_;
  $self->tree->[1] = shift;
  return $self;
}

sub descendant_nodes { $_[0]->_collect(_all(_nodes($_[0]->tree))) }

sub find { $_[0]->_collect(@{$_[0]->_css->select($_[1])}) }

sub following { _select($_[0]->_collect(@{$_[0]->_siblings(1)->[1]}), $_[1]) }
sub following_nodes { $_[0]->_collect(@{$_[0]->_siblings->[1]}) }

sub matches { shift->_css->matches(@_) }

sub namespace {
  my $self = shift;

  return undef if (my $tree = $self->tree)->[0] ne 'tag';

  # Extract namespace prefix and search parents
  my $ns = $tree->[1] =~ /^(.*?):/ ? "xmlns:$1" : undef;
  for my $node ($tree, $self->_ancestors) {

    # Namespace for prefix
    my $attrs = $node->[2];
    if ($ns) { $_ eq $ns and return $attrs->{$_} for keys %$attrs }

    # Namespace attribute
    elsif (defined $attrs->{xmlns}) { return $attrs->{xmlns} }
  }

  return undef;
}

sub new {
  my $class = shift;
  my $self = bless \Mojo::DOM::HTML->new, ref $class || $class;
  return @_ ? $self->parse(@_) : $self;
}

sub next      { $_[0]->_maybe($_[0]->_siblings(1, 0)->[1]) }
sub next_node { $_[0]->_maybe($_[0]->_siblings(0, 0)->[1]) }

sub parent {
  my $self = shift;
  return undef if $self->tree->[0] eq 'root';
  return $self->_build($self->_parent, $self->xml);
}

sub parse { shift->_delegate(parse => @_) }

sub preceding { _select($_[0]->_collect(@{$_[0]->_siblings(1)->[0]}), $_[1]) }
sub preceding_nodes { $_[0]->_collect(@{$_[0]->_siblings->[0]}) }

sub prepend { shift->_add(0, @_) }
sub prepend_content { shift->_content(0, 0, @_) }

sub previous      { $_[0]->_maybe($_[0]->_siblings(1, -1)->[0]) }
sub previous_node { $_[0]->_maybe($_[0]->_siblings(0, -1)->[0]) }

sub remove { shift->replace('') }

sub replace {
  my ($self, $new) = @_;
  return $self->parse($new) if (my $tree = $self->tree)->[0] eq 'root';
  return $self->_replace($self->_parent, $tree, _nodes($self->_parse($new)));
}

sub root {
  my $self = shift;
  return $self unless my $tree = $self->_ancestors(1);
  return $self->_build($tree, $self->xml);
}

sub strip {
  my $self = shift;
  return $self if (my $tree = $self->tree)->[0] ne 'tag';
  return $self->_replace($tree->[3], $tree, _nodes($tree));
}

sub tag {
  my ($self, $tag) = @_;
  return undef if (my $tree = $self->tree)->[0] ne 'tag';
  return $tree->[1] unless $tag;
  $tree->[1] = $tag;
  return $self;
}

sub tap { shift->Mojo::Base::tap(@_) }

sub text { _text([_nodes(shift->tree)], 0) }

sub to_string { shift->_delegate('render') }

sub tree { shift->_delegate(tree => @_) }

sub type { shift->tree->[0] }

sub val {
  my $self = shift;

  # "option"
  return $self->{value} // $self->text if (my $tag = $self->tag) eq 'option';

  # "input" ("type=checkbox" and "type=radio")
  my $type = $self->{type} // '';
  return $self->{value} // 'on'
    if $tag eq 'input' && ($type eq 'radio' || $type eq 'checkbox');

  # "textarea", "input" or "button"
  return $tag eq 'textarea' ? $self->text : $self->{value} if $tag ne 'select';

  # "select"
  my $v = $self->find('option:checked')->map('val');
  return exists $self->{multiple} ? $v->size ? $v->to_array : undef : $v->last;
}

sub wrap         { shift->_wrap(0, @_) }
sub wrap_content { shift->_wrap(1, @_) }

sub xml { shift->_delegate(xml => @_) }

sub _add {
  my ($self, $offset, $new) = @_;

  return $self if (my $tree = $self->tree)->[0] eq 'root';

  my $parent = $self->_parent;
  splice @$parent, _offset($parent, $tree) + $offset, 0,
    _link($parent, _nodes($self->_parse($new)));

  return $self;
}

sub _all {
  map { $_->[0] eq 'tag' ? ($_, _all(_nodes($_))) : ($_) } @_;
}

sub _ancestors {
  my ($self, $root) = @_;

  return () unless my $tree = $self->_parent;
  my @ancestors;
  do { push @ancestors, $tree }
    while ($tree->[0] eq 'tag') && ($tree = $tree->[3]);
  return $root ? $ancestors[-1] : @ancestors[0 .. $#ancestors - 1];
}

sub _build { shift->new->tree(shift)->xml(shift) }

sub _collect {
  my $self = shift;
  my $xml  = $self->xml;
  return Mojo::Collection->new(map { $self->_build($_, $xml) } @_);
}

sub _content {
  my ($self, $start, $offset, $new) = @_;

  my $tree = $self->tree;
  unless ($tree->[0] eq 'root' || $tree->[0] eq 'tag') {
    my $old = $self->content;
    return $self->content($start ? $old . $new : $new . $old);
  }

  $start  = $start  ? ($#$tree + 1) : _start($tree);
  $offset = $offset ? $#$tree       : 0;
  splice @$tree, $start, $offset, _link($tree, _nodes($self->_parse($new)));

  return $self;
}

sub _css { Mojo::DOM::CSS->new(tree => shift->tree) }

sub _delegate {
  my ($self, $method) = (shift, shift);
  return $$self->$method unless @_;
  $$self->$method(@_);
  return $self;
}

sub _link {
  my ($parent, @children) = @_;

  # Link parent to children
  for my $node (@children) {
    my $offset = $node->[0] eq 'tag' ? 3 : 2;
    $node->[$offset] = $parent;
    weaken $node->[$offset];
  }

  return @children;
}

sub _maybe { $_[1] ? $_[0]->_build($_[1], $_[0]->xml) : undef }

sub _nodes {
  return () unless my $tree = shift;
  my @nodes = @$tree[_start($tree) .. $#$tree];
  return shift() ? grep { $_->[0] eq 'tag' } @nodes : @nodes;
}

sub _offset {
  my ($parent, $child) = @_;
  my $i = _start($parent);
  $_ eq $child ? last : $i++ for @$parent[$i .. $#$parent];
  return $i;
}

sub _parent { $_[0]->tree->[$_[0]->type eq 'tag' ? 3 : 2] }

sub _parse { Mojo::DOM::HTML->new(xml => shift->xml)->parse(shift)->tree }

sub _replace {
  my ($self, $parent, $child, @nodes) = @_;
  splice @$parent, _offset($parent, $child), 1, _link($parent, @nodes);
  return $self->parent;
}

sub _select {
  my ($collection, $selector) = @_;
  return $collection unless $selector;
  return $collection->new(grep { $_->matches($selector) } @$collection);
}

sub _siblings {
  my ($self, $tags, $i) = @_;

  return [] unless my $parent = $self->parent;

  my $tree = $self->tree;
  my (@before, @after, $match);
  for my $node (_nodes($parent->tree)) {
    ++$match and next if !$match && $node eq $tree;
    next if $tags && $node->[0] ne 'tag';
    $match ? push @after, $node : push @before, $node;
  }

  return defined $i ? [$before[$i], $after[$i]] : [\@before, \@after];
}

sub _start { $_[0][0] eq 'root' ? 1 : 4 }

sub _text {
  my ($nodes, $all) = @_;

  my $text = '';
  while (my $node = shift @$nodes) {
    my $type = $node->[0];

    # Text
    if ($type eq 'text' || $type eq 'cdata' || $type eq 'raw') {
      $text .= $node->[1];
    }

    # Nested tag
    elsif ($type eq 'tag' && $all) { unshift @$nodes, _nodes($node) }
  }

  return $text;
}

sub _wrap {
  my ($self, $content, $new) = @_;

  return $self if (my $tree = $self->tree)->[0] eq 'root' && !$content;
  return $self if $tree->[0] ne 'root' && $tree->[0] ne 'tag' && $content;

  # Find innermost tag
  my $current;
  my $first = $new = $self->_parse($new);
  $current = $first while $first = (_nodes($first, 1))[0];
  return $self unless $current;

  # Wrap content
  if ($content) {
    push @$current, _link($current, _nodes($tree));
    splice @$tree, _start($tree), $#$tree, _link($tree, _nodes($new));
    return $self;
  }

  # Wrap element
  $self->_replace($self->_parent, $tree, _nodes($new));
  push @$current, _link($current, $tree);
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::DOM - Minimalistic HTML/XML DOM parser with CSS selectors

=head1 SYNOPSIS

  use Mojo::DOM;

  # Parse
  my $dom = Mojo::DOM->new('<div><p id="a">Test</p><p id="b">123</p></div>');

  # Find
  say $dom->at('#b')->text;
  say $dom->find('p')->map('text')->join("\n");
  say $dom->find('[id]')->map(attr => 'id')->join("\n");

  # Iterate
  $dom->find('p[id]')->reverse->each(sub { say $_->{id} });

  # Loop
  for my $e ($dom->find('p[id]')->each) {
    say $e->{id}, ':', $e->text;
  }

  # Modify
  $dom->find('div p')->last->append('<p id="c">456</p>');
  $dom->find(':not(p)')->map('strip');

  # Render
  say "$dom";

=head1 DESCRIPTION

L<Mojo::DOM> is a minimalistic and relaxed HTML/XML DOM parser with CSS
selector support. It will even try to interpret broken HTML and XML, so you
should not use it for validation.

=head1 NODES AND ELEMENTS

When we parse an HTML/XML fragment, it gets turned into a tree of nodes.

  <!DOCTYPE html>
  <html>
    <head><title>Hello</title></head>
    <body>World!</body>
  </html>

There are currently eight different kinds of nodes, C<cdata>, C<comment>,
C<doctype>, C<pi>, C<raw>, C<root>, C<tag> and C<text>. Elements are nodes of
the type C<tag>.

  root
  |- doctype (html)
  +- tag (html)
     |- tag (head)
     |  +- tag (title)
     |     +- raw (Hello)
     +- tag (body)
        +- text (World!)

While all node types are represented as L<Mojo::DOM> objects, some methods like
L</"attr"> and L</"namespace"> only apply to elements.

=head1 CASE-SENSITIVITY

L<Mojo::DOM> defaults to HTML semantics, that means all tags and attribute
names are lowercased and selectors need to be lowercase as well.

  # HTML semantics
  my $dom = Mojo::DOM->new('<P ID="greeting">Hi!</P>');
  say $dom->at('p[id]')->text;

If an XML declaration is found, the parser will automatically switch into XML
mode and everything becomes case-sensitive.

  # XML semantics
  my $dom = Mojo::DOM->new('<?xml version="1.0"?><P ID="greeting">Hi!</P>');
  say $dom->at('P[ID]')->text;

XML detection can also be disabled with the L</"xml"> method.

  # Force XML semantics
  my $dom = Mojo::DOM->new->xml(1)->parse('<P ID="greeting">Hi!</P>');
  say $dom->at('P[ID]')->text;

  # Force HTML semantics
  my $dom = Mojo::DOM->new->xml(0)->parse('<P ID="greeting">Hi!</P>');
  say $dom->at('p[id]')->text;

=head1 METHODS

L<Mojo::DOM> implements the following methods.

=head2 all_text

  my $text = $dom->all_text;

Extract text content from all descendant nodes of this element.

  # "foo\nbarbaz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->at('div')->all_text;

=head2 ancestors

  my $collection = $dom->ancestors;
  my $collection = $dom->ancestors('div ~ p');

Find all ancestor elements of this node matching the CSS selector and return a
L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # List tag names of ancestor elements
  say $dom->ancestors->map('tag')->join("\n");

=head2 append

  $dom = $dom->append('<p>I ♥ Mojolicious!</p>');

Append HTML/XML fragment to this node (for all node types other than C<root>).

  # "<div><h1>Test</h1><h2>123</h2></div>"
  $dom->parse('<div><h1>Test</h1></div>')
    ->at('h1')->append('<h2>123</h2>')->root;

  # "<p>Test 123</p>"
  $dom->parse('<p>Test</p>')->at('p')
    ->child_nodes->first->append(' 123')->root;

=head2 append_content

  $dom = $dom->append_content('<p>I ♥ Mojolicious!</p>');

Append HTML/XML fragment (for C<root> and C<tag> nodes) or raw content to this
node's content.

  # "<div><h1>Test123</h1></div>"
  $dom->parse('<div><h1>Test</h1></div>')
    ->at('h1')->append_content('123')->root;

  # "<!-- Test 123 --><br>"
  $dom->parse('<!-- Test --><br>')
    ->child_nodes->first->append_content('123 ')->root;

  # "<p>Test<i>123</i></p>"
  $dom->parse('<p>Test</p>')->at('p')->append_content('<i>123</i>')->root;

=head2 at

  my $result = $dom->at('div ~ p');

Find first descendant element of this element matching the CSS selector and
return it as a L<Mojo::DOM> object, or C<undef> if none could be found. All
selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # Find first element with "svg" namespace definition
  my $namespace = $dom->at('[xmlns\:svg]')->{'xmlns:svg'};

=head2 attr

  my $hash = $dom->attr;
  my $foo  = $dom->attr('foo');
  $dom     = $dom->attr({foo => 'bar'});
  $dom     = $dom->attr(foo => 'bar');

This element's attributes.

  # Remove an attribute
  delete $dom->attr->{id};

  # Attribute without value
  $dom->attr(selected => undef);

  # List id attributes
  say $dom->find('*')->map(attr => 'id')->compact->join("\n");

=head2 child_nodes

  my $collection = $dom->child_nodes;

Return a L<Mojo::Collection> object containing all child nodes of this element
as L<Mojo::DOM> objects.

  # "<p><b>123</b></p>"
  $dom->parse('<p>Test<b>123</b></p>')->at('p')->child_nodes->first->remove;

  # "<!DOCTYPE html>"
  $dom->parse('<!DOCTYPE html><b>123</b>')->child_nodes->first;

  # " Test "
  $dom->parse('<b>123</b><!-- Test -->')->child_nodes->last->content;

=head2 children

  my $collection = $dom->children;
  my $collection = $dom->children('div ~ p');

Find all child elements of this element matching the CSS selector and return a
L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # Show tag name of random child element
  say $dom->children->shuffle->first->tag;

=head2 content

  my $str = $dom->content;
  $dom    = $dom->content('<p>I ♥ Mojolicious!</p>');

Return this node's content or replace it with HTML/XML fragment (for C<root>
and C<tag> nodes) or raw content.

  # "<b>Test</b>"
  $dom->parse('<div><b>Test</b></div>')->at('div')->content;

  # "<div><h1>123</h1></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->content('123')->root;

  # "<p><i>123</i></p>"
  $dom->parse('<p>Test</p>')->at('p')->content('<i>123</i>')->root;

  # "<div><h1></h1></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->content('')->root;

  # " Test "
  $dom->parse('<!-- Test --><br>')->child_nodes->first->content;

  # "<div><!-- 123 -->456</div>"
  $dom->parse('<div><!-- Test -->456</div>')
    ->at('div')->child_nodes->first->content(' 123 ')->root;

=head2 descendant_nodes

  my $collection = $dom->descendant_nodes;

Return a L<Mojo::Collection> object containing all descendant nodes of this
element as L<Mojo::DOM> objects.

  # "<p><b>123</b></p>"
  $dom->parse('<p><!-- Test --><b>123<!-- 456 --></b></p>')
    ->descendant_nodes->grep(sub { $_->type eq 'comment' })
    ->map('remove')->first;

  # "<p><b>test</b>test</p>"
  $dom->parse('<p><b>123</b>456</p>')
    ->at('p')->descendant_nodes->grep(sub { $_->type eq 'text' })
    ->map(content => 'test')->first->root;

=head2 find

  my $collection = $dom->find('div ~ p');

Find all descendant elements of this element matching the CSS selector and
return a L<Mojo::Collection> object containing these elements as L<Mojo::DOM>
objects. All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # Find a specific element and extract information
  my $id = $dom->find('div')->[23]{id};

  # Extract information from multiple elements
  my @headers = $dom->find('h1, h2, h3')->map('text')->each;

  # Count all the different tags
  my $hash = $dom->find('*')->reduce(sub { $a->{$b->tag}++; $a }, {});

  # Find elements with a class that contains dots
  my @divs = $dom->find('div.foo\.bar')->each;

=head2 following

  my $collection = $dom->following;
  my $collection = $dom->following('div ~ p');

Find all sibling elements after this node matching the CSS selector and return
a L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # List tags of sibling elements after this node
  say $dom->following->map('tag')->join("\n");

=head2 following_nodes

  my $collection = $dom->following_nodes;

Return a L<Mojo::Collection> object containing all sibling nodes after this
node as L<Mojo::DOM> objects.

  # "C"
  $dom->parse('<p>A</p><!-- B -->C')->at('p')->following_nodes->last->content;

=head2 matches

  my $bool = $dom->matches('div ~ p');

Check if this element matches the CSS selector. All selectors from
L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # True
  $dom->parse('<p class="a">A</p>')->at('p')->matches('.a');
  $dom->parse('<p class="a">A</p>')->at('p')->matches('p[class]');

  # False
  $dom->parse('<p class="a">A</p>')->at('p')->matches('.b');
  $dom->parse('<p class="a">A</p>')->at('p')->matches('p[id]');

=head2 namespace

  my $namespace = $dom->namespace;

Find this element's namespace, or return C<undef> if none could be found.

  # Find namespace for an element with namespace prefix
  my $namespace = $dom->at('svg > svg\:circle')->namespace;

  # Find namespace for an element that may or may not have a namespace prefix
  my $namespace = $dom->at('svg > circle')->namespace;

=head2 new

  my $dom = Mojo::DOM->new;
  my $dom = Mojo::DOM->new('<foo bar="baz">I ♥ Mojolicious!</foo>');

Construct a new scalar-based L<Mojo::DOM> object and L</"parse"> HTML/XML
fragment if necessary.

=head2 next

  my $sibling = $dom->next;

Return L<Mojo::DOM> object for next sibling element, or C<undef> if there are no
more siblings.

  # "<h2>123</h2>"
  $dom->parse('<div><h1>Test</h1><h2>123</h2></div>')->at('h1')->next;

=head2 next_node

  my $sibling = $dom->next_node;

Return L<Mojo::DOM> object for next sibling node, or C<undef> if there are no
more siblings.

  # "456"
  $dom->parse('<p><b>123</b><!-- Test -->456</p>')
    ->at('b')->next_node->next_node;

  # " Test "
  $dom->parse('<p><b>123</b><!-- Test -->456</p>')
    ->at('b')->next_node->content;

=head2 parent

  my $parent = $dom->parent;

Return L<Mojo::DOM> object for parent of this node, or C<undef> if this node has
no parent.

  # "<b><i>Test</i></b>"
  $dom->parse('<p><b><i>Test</i></b></p>')->at('i')->parent;

=head2 parse

  $dom = $dom->parse('<foo bar="baz">I ♥ Mojolicious!</foo>');

Parse HTML/XML fragment with L<Mojo::DOM::HTML>.

  # Parse XML
  my $dom = Mojo::DOM->new->xml(1)->parse('<foo>I ♥ Mojolicious!</foo>');

=head2 preceding

  my $collection = $dom->preceding;
  my $collection = $dom->preceding('div ~ p');

Find all sibling elements before this node matching the CSS selector and return
a L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # List tags of sibling elements before this node
  say $dom->preceding->map('tag')->join("\n");

=head2 preceding_nodes

  my $collection = $dom->preceding_nodes;

Return a L<Mojo::Collection> object containing all sibling nodes before this
node as L<Mojo::DOM> objects.

  # "A"
  $dom->parse('A<!-- B --><p>C</p>')->at('p')->preceding_nodes->first->content;

=head2 prepend

  $dom = $dom->prepend('<p>I ♥ Mojolicious!</p>');

Prepend HTML/XML fragment to this node (for all node types other than C<root>).

  # "<div><h1>Test</h1><h2>123</h2></div>"
  $dom->parse('<div><h2>123</h2></div>')
    ->at('h2')->prepend('<h1>Test</h1>')->root;

  # "<p>Test 123</p>"
  $dom->parse('<p>123</p>')
    ->at('p')->child_nodes->first->prepend('Test ')->root;

=head2 prepend_content

  $dom = $dom->prepend_content('<p>I ♥ Mojolicious!</p>');

Prepend HTML/XML fragment (for C<root> and C<tag> nodes) or raw content to this
node's content.

  # "<div><h2>Test123</h2></div>"
  $dom->parse('<div><h2>123</h2></div>')
    ->at('h2')->prepend_content('Test')->root;

  # "<!-- Test 123 --><br>"
  $dom->parse('<!-- 123 --><br>')
    ->child_nodes->first->prepend_content(' Test')->root;

  # "<p><i>123</i>Test</p>"
  $dom->parse('<p>Test</p>')->at('p')->prepend_content('<i>123</i>')->root;

=head2 previous

  my $sibling = $dom->previous;

Return L<Mojo::DOM> object for previous sibling element, or C<undef> if there
are no more siblings.

  # "<h1>Test</h1>"
  $dom->parse('<div><h1>Test</h1><h2>123</h2></div>')->at('h2')->previous;

=head2 previous_node

  my $sibling = $dom->previous_node;

Return L<Mojo::DOM> object for previous sibling node, or C<undef> if there are
no more siblings.

  # "123"
  $dom->parse('<p>123<!-- Test --><b>456</b></p>')
    ->at('b')->previous_node->previous_node;

  # " Test "
  $dom->parse('<p>123<!-- Test --><b>456</b></p>')
    ->at('b')->previous_node->content;

=head2 remove

  my $parent = $dom->remove;

Remove this node and return L</"root"> (for C<root> nodes) or L</"parent">.

  # "<div></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->remove;

  # "<p><b>456</b></p>"
  $dom->parse('<p>123<b>456</b></p>')
    ->at('p')->child_nodes->first->remove->root;

=head2 replace

  my $parent = $dom->replace('<div>I ♥ Mojolicious!</div>');

Replace this node with HTML/XML fragment and return L</"root"> (for C<root>
nodes) or L</"parent">.

  # "<div><h2>123</h2></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->replace('<h2>123</h2>');

  # "<p><b>123</b></p>"
  $dom->parse('<p>Test</p>')
    ->at('p')->child_nodes->[0]->replace('<b>123</b>')->root;

=head2 root

  my $root = $dom->root;

Return L<Mojo::DOM> object for C<root> node.

=head2 strip

  my $parent = $dom->strip;

Remove this element while preserving its content and return L</"parent">.

  # "<div>Test</div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->strip;

=head2 tag

  my $tag = $dom->tag;
  $dom    = $dom->tag('div');

This element's tag name.

  # List tag names of child elements
  say $dom->children->map('tag')->join("\n");

=head2 tap

  $dom = $dom->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 text

  my $text = $dom->text;

Extract text content from this element only (not including child elements).

  # "bar"
  $dom->parse("<div>foo<p>bar</p>baz</div>")->at('p')->text;

  # "foo\nbaz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->at('div')->text;

=head2 to_string

  my $str = $dom->to_string;

Render this node and its content to HTML/XML.

  # "<b>Test</b>"
  $dom->parse('<div><b>Test</b></div>')->at('div b')->to_string;

=head2 tree

  my $tree = $dom->tree;
  $dom     = $dom->tree(['root']);

Document Object Model. Note that this structure should only be used very
carefully since it is very dynamic.

=head2 type

  my $type = $dom->type;

This node's type, usually C<cdata>, C<comment>, C<doctype>, C<pi>, C<raw>,
C<root>, C<tag> or C<text>.

  # "cdata"
  $dom->parse('<![CDATA[Test]]>')->child_nodes->first->type;

  # "comment"
  $dom->parse('<!-- Test -->')->child_nodes->first->type;

  # "doctype"
  $dom->parse('<!DOCTYPE html>')->child_nodes->first->type;

  # "pi"
  $dom->parse('<?xml version="1.0"?>')->child_nodes->first->type;

  # "raw"
  $dom->parse('<title>Test</title>')->at('title')->child_nodes->first->type;

  # "root"
  $dom->parse('<p>Test</p>')->type;

  # "tag"
  $dom->parse('<p>Test</p>')->at('p')->type;

  # "text"
  $dom->parse('<p>Test</p>')->at('p')->child_nodes->first->type;

=head2 val

  my $value = $dom->val;

Extract value from form element (such as C<button>, C<input>, C<option>,
C<select> and C<textarea>), or return C<undef> if this element has no value. In
the case of C<select> with C<multiple> attribute, find C<option> elements with
C<selected> attribute and return an array reference with all values, or C<undef>
if none could be found.

  # "a"
  $dom->parse('<input name=test value=a>')->at('input')->val;

  # "b"
  $dom->parse('<textarea>b</textarea>')->at('textarea')->val;

  # "c"
  $dom->parse('<option value="c">Test</option>')->at('option')->val;

  # "d"
  $dom->parse('<select><option selected>d</option></select>')
    ->at('select')->val;

  # "e"
  $dom->parse('<select multiple><option selected>e</option></select>')
    ->at('select')->val->[0];

  # "on"
  $dom->parse('<input name=test type=checkbox>')->at('input')->val;

=head2 wrap

  $dom = $dom->wrap('<div></div>');

Wrap HTML/XML fragment around this node (for all node types other than C<root>),
placing it as the last child of the first innermost element.

  # "<p>123<b>Test</b></p>"
  $dom->parse('<b>Test</b>')->at('b')->wrap('<p>123</p>')->root;

  # "<div><p><b>Test</b></p>123</div>"
  $dom->parse('<b>Test</b>')->at('b')->wrap('<div><p></p>123</div>')->root;

  # "<p><b>Test</b></p><p>123</p>"
  $dom->parse('<b>Test</b>')->at('b')->wrap('<p></p><p>123</p>')->root;

  # "<p><b>Test</b></p>"
  $dom->parse('<p>Test</p>')->at('p')->child_nodes->first->wrap('<b>')->root;

=head2 wrap_content

  $dom = $dom->wrap_content('<div></div>');

Wrap HTML/XML fragment around this node's content (for C<root> and C<tag>
nodes), placing it as the last children of the first innermost element.

  # "<p><b>123Test</b></p>"
  $dom->parse('<p>Test<p>')->at('p')->wrap_content('<b>123</b>')->root;

  # "<p><b>Test</b></p><p>123</p>"
  $dom->parse('<b>Test</b>')->wrap_content('<p></p><p>123</p>');

=head2 xml

  my $bool = $dom->xml;
  $dom     = $dom->xml($bool);

Disable HTML semantics in parser and activate case-sensitivity, defaults to
auto-detection based on XML declarations.

=head1 OPERATORS

L<Mojo::DOM> overloads the following operators.

=head2 array

  my @nodes = @$dom;

Alias for L</"child_nodes">.

  # "<!-- Test -->"
  $dom->parse('<!-- Test --><b>123</b>')->[0];

=head2 bool

  my $bool = !!$dom;

Always true.

=head2 hash

  my %attrs = %$dom;

Alias for L</"attr">.

  # "test"
  $dom->parse('<div id="test">Test</div>')->at('div')->{id};

=head2 stringify

  my $str = "$dom";

Alias for L</"to_string">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
