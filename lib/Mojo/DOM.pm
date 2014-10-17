package Mojo::DOM;
use Mojo::Base -strict;
use overload
  '@{}'    => sub { shift->contents },
  '%{}'    => sub { shift->attr },
  bool     => sub {1},
  '""'     => sub { shift->to_string },
  fallback => 1;

# "Fry: This snow is beautiful. I'm glad global warming never happened.
#  Leela: Actually, it did. But thank God nuclear winter canceled it out."
use Carp 'croak';
use List::Util 'first';
use Mojo::Collection;
use Mojo::DOM::CSS;
use Mojo::DOM::HTML;
use Mojo::Util 'squish';
use Scalar::Util qw(blessed weaken);

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^(.+)::(.+)$/;
  croak "Undefined subroutine &${package}::$method called"
    unless blessed $self && $self->isa(__PACKAGE__);

  # Search children of current element
  my $children = $self->children($method);
  return @$children > 1 ? $children : $children->[0] if @$children;
  croak qq{Can't locate object method "$method" via package "$package"};
}

sub DESTROY { }

sub all_contents { $_[0]->_collect(_all(_nodes($_[0]->tree))) }

sub all_text { shift->_all_text(1, @_) }

sub ancestors { _select($_[0]->_collect($_[0]->_ancestors), $_[1]) }

sub append { shift->_add(1, @_) }

sub append_content { shift->_content(1, 0, @_) }

sub at {
  my $self = shift;
  return undef unless my $result = $self->_css->select_one(@_);
  return _build($self, $result, $self->xml);
}

sub attr {
  my $self = shift;

  # Hash
  my $tree = $self->tree;
  my $attrs = $tree->[0] ne 'tag' ? {} : $tree->[2];
  return $attrs unless @_;

  # Get
  return $attrs->{$_[0]} // '' unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  @$attrs{keys %$values} = values %$values;

  return $self;
}

sub children {
  my $self = shift;
  return _select(
    $self->_collect(grep { $_->[0] eq 'tag' } _nodes($self->tree)), @_);
}

sub content {
  my $self = shift;

  my $node = $self->node;
  if ($node eq 'root' || $node eq 'tag') {
    return $self->_content(0, 1, @_) if @_;
    my $html = Mojo::DOM::HTML->new(xml => $self->xml);
    return join '', map { $html->tree($_)->render } _nodes($self->tree);
  }

  return $self->tree->[1] unless @_;
  $self->tree->[1] = shift;
  return $self;
}

sub contents { $_[0]->_collect(_nodes($_[0]->tree)) }

sub find { $_[0]->_collect(@{$_[0]->_css->select($_[1])}) }

sub match { $_[0]->_css->match($_[1]) ? $_[0] : undef }

sub namespace {
  my $self = shift;

  return '' if (my $tree = $self->tree)->[0] ne 'tag';

  # Extract namespace prefix and search parents
  my $ns = $tree->[1] =~ /^(.*?):/ ? "xmlns:$1" : undef;
  for my $n ($tree, $self->_ancestors) {

    # Namespace for prefix
    my $attrs = $n->[2];
    if ($ns) { /^\Q$ns\E$/ and return $attrs->{$_} for keys %$attrs }

    # Namespace attribute
    elsif (defined $attrs->{xmlns}) { return $attrs->{xmlns} }
  }

  return '';
}

sub new {
  my $class = shift;
  my $self = bless \Mojo::DOM::HTML->new, ref $class || $class;
  return @_ ? $self->parse(@_) : $self;
}

sub next         { _maybe($_[0], $_[0]->_siblings(1)->[1]) }
sub next_sibling { _maybe($_[0], $_[0]->_siblings->[1]) }

sub node { shift->tree->[0] }

sub parent {
  my $self = shift;
  return undef if $self->tree->[0] eq 'root';
  return _build($self, $self->_parent, $self->xml);
}

sub parse { shift->_delegate(parse => shift) }

sub prepend { shift->_add(0, @_) }

sub prepend_content { shift->_content(0, 0, @_) }

sub previous         { _maybe($_[0], $_[0]->_siblings(1)->[0]) }
sub previous_sibling { _maybe($_[0], $_[0]->_siblings->[0]) }

sub remove { shift->replace('') }

sub replace {
  my ($self, $new) = @_;
  return $self->parse($new) if (my $tree = $self->tree)->[0] eq 'root';
  return $self->_replace($self->_parent, $tree, $self->_parse("$new"));
}

sub root {
  my $self = shift;
  return $self unless my $tree = $self->_ancestors(1);
  return _build($self, $tree, $self->xml);
}

sub siblings { _select($_[0]->_collect(@{_siblings($_[0], 1, 1)}), $_[1]) }

sub strip {
  my $self = shift;
  return $self if (my $tree = $self->tree)->[0] ne 'tag';
  return $self->_replace($tree->[3], $tree, ['root', _nodes($tree)]);
}

sub tap { shift->Mojo::Base::tap(@_) }

sub text { shift->_all_text(0, @_) }

sub to_string { shift->_delegate('render') }

sub tree { shift->_delegate(tree => @_) }

sub type {
  my ($self, $type) = @_;
  return '' if (my $tree = $self->tree)->[0] ne 'tag';
  return $tree->[1] unless $type;
  $tree->[1] = $type;
  return $self;
}

sub val {
  my $self = shift;

  # "option"
  my $type = $self->type;
  return Mojo::Collection->new($self->{value} // $self->text)
    if $type eq 'option';

  # "select"
  return $self->find('option[selected]')->val->flatten if $type eq 'select';

  # "textarea"
  return Mojo::Collection->new($self->text) if $type eq 'textarea';

  # "input" or "button"
  return Mojo::Collection->new($self->{value} // ());
}

sub wrap         { shift->_wrap(0, @_) }
sub wrap_content { shift->_wrap(1, @_) }

sub xml { shift->_delegate(xml => @_) }

sub _add {
  my ($self, $offset, $new) = @_;

  return $self if (my $tree = $self->tree)->[0] eq 'root';

  my $parent = $self->_parent;
  splice @$parent, _offset($parent, $tree) + $offset, 0,
    _link($self->_parse("$new"), $parent);

  return $self;
}

sub _all {
  map { $_->[0] eq 'tag' ? ($_, _all(_nodes($_))) : ($_) } @_;
}

sub _all_text {
  my ($self, $recurse, $trim) = @_;

  # Detect "pre" tag
  my $tree = $self->tree;
  if (!defined $trim || $trim) {
    $trim = 1;
    $_->[1] eq 'pre' and $trim = 0 for $self->_ancestors, $tree;
  }

  return _text([_nodes($tree)], $recurse, $trim);
}

sub _ancestors {
  my ($self, $root) = @_;

  return if $self->node eq 'root';

  my @ancestors;
  my $tree = $self->_parent;
  do { push @ancestors, $tree }
    while ($tree->[0] eq 'tag') && ($tree = $tree->[3]);
  return $root ? $ancestors[-1] : @ancestors[0 .. $#ancestors - 1];
}

sub _build { shift->new->tree(shift)->xml(shift) }

sub _collect {
  my $self = shift;
  my $xml  = $self->xml;
  return Mojo::Collection->new(map { _build($self, $_, $xml) } @_);
}

sub _content {
  my ($self, $start, $offset, $new) = @_;

  my $tree = $self->tree;
  unless ($tree->[0] eq 'root' || $tree->[0] eq 'tag') {
    my $old = $self->content;
    return $self->content($start ? "$old$new" : "$new$old");
  }

  $start  = $start  ? ($#$tree + 1) : _start($tree);
  $offset = $offset ? $#$tree       : 0;
  splice @$tree, $start, $offset, _link($self->_parse("$new"), $tree);

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
  my ($children, $parent) = @_;

  # Link parent to children
  my @new;
  for my $n (@$children[1 .. $#$children]) {
    push @new, $n;
    my $offset = $n->[0] eq 'tag' ? 3 : 2;
    $n->[$offset] = $parent;
    weaken $n->[$offset];
  }

  return @new;
}

sub _maybe { $_[1] ? _build($_[0], $_[1], $_[0]->xml) : undef }

sub _nodes {
  return unless my $tree = shift;
  return @$tree[_start($tree) .. $#$tree];
}

sub _offset {
  my ($parent, $child) = @_;
  my $i = _start($parent);
  $_ eq $child ? last : $i++ for @$parent[$i .. $#$parent];
  return $i;
}

sub _parent { $_[0]->tree->[$_[0]->node eq 'tag' ? 3 : 2] }

sub _parse { Mojo::DOM::HTML->new(xml => shift->xml)->parse(shift)->tree }

sub _replace {
  my ($self, $parent, $tree, $new) = @_;
  splice @$parent, _offset($parent, $tree), 1, _link($new, $parent);
  return $self->parent;
}

sub _select {
  my ($collection, $selector) = @_;
  return $collection unless $selector;
  return $collection->new(grep { $_->match($selector) } @$collection);
}

sub _siblings {
  my ($self, $tags, $all) = @_;

  return [] unless my $parent = $self->parent;

  my $tree = $self->tree;
  my (@before, @after, $match);
  for my $node (_nodes($parent->tree)) {
    ++$match and next if !$match && $node eq $tree;
    next if $tags && $node->[0] ne 'tag';
    $match ? push @after, $node : push @before, $node;
  }

  return $all ? [@before, @after] : [$before[-1], $after[0]];
}

sub _start { $_[0][0] eq 'root' ? 1 : 4 }

sub _text {
  my ($nodes, $recurse, $trim) = @_;

  # Merge successive text nodes
  my $i = 0;
  while (my $next = $nodes->[$i + 1]) {
    ++$i and next unless $nodes->[$i][0] eq 'text' && $next->[0] eq 'text';
    splice @$nodes, $i, 2, ['text', $nodes->[$i][1] . $next->[1]];
  }

  my $text = '';
  for my $n (@$nodes) {
    my $type = $n->[0];

    # Nested tag
    my $content = '';
    if ($type eq 'tag' && $recurse) {
      no warnings 'recursion';
      $content = _text([_nodes($n)], 1, $n->[1] eq 'pre' ? 0 : $trim);
    }

    # Text
    elsif ($type eq 'text') { $content = $trim ? squish($n->[1]) : $n->[1] }

    # CDATA or raw text
    elsif ($type eq 'cdata' || $type eq 'raw') { $content = $n->[1] }

    # Add leading whitespace if punctuation allows it
    $content = " $content" if $text =~ /\S\z/ && $content =~ /^[^.!?,;:\s]+/;

    # Trim whitespace blocks
    $text .= $content if $content =~ /\S+/ || !$trim;
  }

  return $text;
}

sub _wrap {
  my ($self, $content, $new) = @_;

  $content = 1 if (my $tree = $self->tree)->[0] eq 'root';
  $content = 0 if $tree->[0] ne 'root' && $tree->[0] ne 'tag';

  # Find innermost tag
  my $current;
  my $first = $new = $self->_parse("$new");
  $current = $first while $first = first { $_->[0] eq 'tag' } _nodes($first);
  return $self unless $current;

  # Wrap content
  if ($content) {
    push @$current, _link(['root', _nodes($tree)], $current);
    splice @$tree, _start($tree), $#$tree, _link($new, $tree);
    return $self;
  }

  # Wrap element
  $self->_replace($self->_parent, $tree, $new);
  push @$current, _link(['root', $tree], $current);
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
  say $dom->find('p')->text;
  say $dom->find('[id]')->attr('id');

  # Walk
  say $dom->div->p->[0]->text;
  say $dom->div->children('p')->first->{id};

  # Iterate
  $dom->find('p[id]')->reverse->each(sub { say $_->{id} });

  # Loop
  for my $e ($dom->find('p[id]')->each) {
    say $e->{id}, ':', $e->text;
  }

  # Modify
  $dom->div->p->last->append('<p id="c">456</p>');
  $dom->find(':not(p)')->strip;

  # Render
  say "$dom";

=head1 DESCRIPTION

L<Mojo::DOM> is a minimalistic and relaxed HTML/XML DOM parser with CSS
selector support. It will even try to interpret broken XML, so you should not
use it for validation.

=head1 CASE SENSITIVITY

L<Mojo::DOM> defaults to HTML semantics, that means all tags and attributes
are lowercased and selectors need to be lowercase as well.

  my $dom = Mojo::DOM->new('<P ID="greeting">Hi!</P>');
  say $dom->at('p')->text;
  say $dom->p->{id};

If XML processing instructions are found, the parser will automatically switch
into XML mode and everything becomes case sensitive.

  my $dom = Mojo::DOM->new('<?xml version="1.0"?><P ID="greeting">Hi!</P>');
  say $dom->at('P')->text;
  say $dom->P->{ID};

XML detection can also be disabled with the L</"xml"> method.

  # Force XML semantics
  $dom->xml(1);

  # Force HTML semantics
  $dom->xml(0);

=head1 METHODS

L<Mojo::DOM> implements the following methods.

=head2 all_contents

  my $collection = $dom->all_contents;

Return a L<Mojo::Collection> object containing all nodes in DOM structure as
L<Mojo::DOM> objects.

  # "<p><b>123</b></p>"
  $dom->parse('<p><!-- Test --><b>123<!-- 456 --></b></p>')
    ->all_contents->grep(sub { $_->node eq 'comment' })->remove->first;

=head2 all_text

  my $trimmed   = $dom->all_text;
  my $untrimmed = $dom->all_text(0);

Extract all text content from DOM structure, smart whitespace trimming is
enabled by default.

  # "foo bar baz"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->all_text;

  # "foo\nbarbaz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->all_text(0);

=head2 ancestors

  my $collection = $dom->ancestors;
  my $collection = $dom->ancestors('div > p');

Find all ancestors of this node matching the CSS selector and return a
L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # List types of ancestor elements
  say $dom->ancestors->type;

=head2 append

  $dom = $dom->append('<p>I ♥ Mojolicious!</p>');

Append HTML/XML fragment to this node.

  # "<div><h1>Test</h1><h2>123</h2></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')
    ->append('<h2>123</h2>')->root;

  # "<p>Test 123</p>"
  $dom->parse('<p>Test</p>')->at('p')->contents->first->append(' 123')->root;

=head2 append_content

  $dom = $dom->append_content('<p>I ♥ Mojolicious!</p>');

Append HTML/XML fragment (for C<root> and C<tag> nodes) or raw content to this
node's content.

  # "<div><h1>Test123</h1></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')
    ->append_content('123')->root;

  # "<!-- Test 123 --><br>"
  $dom->parse('<!-- Test --><br>')
    ->contents->first->append_content('123 ')->root;

  # "<p>Test<i>123</i></p>"
  $dom->parse('<p>Test</p>')->at('p')->append_content('<i>123</i>')->root;

=head2 at

  my $result = $dom->at('html title');

Find first element in DOM structure matching the CSS selector and return it as
a L<Mojo::DOM> object or return C<undef> if none could be found. All selectors
from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # Find first element with "svg" namespace definition
  my $namespace = $dom->at('[xmlns\:svg]')->{'xmlns:svg'};

=head2 attr

  my $hash = $dom->attr;
  my $foo  = $dom->attr('foo');
  $dom     = $dom->attr({foo => 'bar'});
  $dom     = $dom->attr(foo => 'bar');

This element's attributes.

  # List id attributes
  say $dom->find('*')->attr('id')->compact;

=head2 children

  my $collection = $dom->children;
  my $collection = $dom->children('div > p');

Find all children of this element matching the CSS selector and return a
L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # Show type of random child element
  say $dom->children->shuffle->first->type;

=head2 content

  my $str = $dom->content;
  $dom    = $dom->content('<p>I ♥ Mojolicious!</p>');

Return this node's content or replace it with HTML/XML fragment (for C<root>
and C<tag> nodes) or raw content.

  # "<b>Test</b>"
  $dom->parse('<div><b>Test</b></div>')->div->content;

  # "<div><h1>123</h1></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->content('123')->root;

  # "<p><i>123</i></p>"
  $dom->parse('<p>Test</p>')->at('p')->content('<i>123</i>')->root;

  # "<div><h1></h1></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->content('')->root;

  # " Test "
  $dom->parse('<!-- Test --><br>')->contents->first->content;

  # "<div><!-- 123 -->456</div>"
  $dom->parse('<div><!-- Test -->456</div>')->at('div')
    ->contents->first->content(' 123 ')->root;

=head2 contents

  my $collection = $dom->contents;

Return a L<Mojo::Collection> object containing the child nodes of this element
as L<Mojo::DOM> objects.

  # "<p><b>123</b></p>"
  $dom->parse('<p>Test<b>123</b></p>')->at('p')->contents->first->remove;

  # "<!-- Test -->"
  $dom->parse('<!-- Test --><b>123</b>')->contents->first;

=head2 find

  my $collection = $dom->find('html title');

Find all elements in DOM structure matching the CSS selector and return a
L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # Find a specific element and extract information
  my $id = $dom->find('div')->[23]{id};

  # Extract information from multiple elements
  my @headers = $dom->find('h1, h2, h3')->text->each;

  # Count all the different tags
  my $hash = $dom->find('*')->type->reduce(sub { $a->{$b}++; $a }, {});

  # Find elements with a class that contains dots
  my @divs = $dom->find('div.foo\.bar')->each;

=head2 match

  my $result = $dom->match('html title');

Match the CSS selector against this element and return it as a L<Mojo::DOM>
object or return C<undef> if it didn't match. All selectors from
L<Mojo::DOM::CSS/"SELECTORS"> are supported.

=head2 namespace

  my $namespace = $dom->namespace;

Find this element's namespace.

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

Return L<Mojo::DOM> object for next sibling element or C<undef> if there are
no more siblings.

  # "<h2>123</h2>"
  $dom->parse('<div><h1>Test</h1><h2>123</h2></div>')->at('h1')->next;

=head2 next_sibling

  my $sibling = $dom->next_sibling;

Return L<Mojo::DOM> object for next sibling node or C<undef> if there are no
more siblings.

  # "456"
  $dom->parse('<p><b>123</b><!-- Test -->456</p>')->at('b')
    ->next_sibling->next_sibling;

=head2 node

  my $type = $dom->node;

This node's type, usually C<cdata>, C<comment>, C<doctype>, C<pi>, C<raw>,
C<root>, C<tag> or C<text>.

=head2 parent

  my $parent = $dom->parent;

Return L<Mojo::DOM> object for parent of this node or C<undef> if this node
has no parent.

=head2 parse

  $dom = $dom->parse('<foo bar="baz">I ♥ Mojolicious!</foo>');

Parse HTML/XML fragment with L<Mojo::DOM::HTML>.

  # Parse XML
  my $dom = Mojo::DOM->new->xml(1)->parse($xml);

=head2 prepend

  $dom = $dom->prepend('<p>I ♥ Mojolicious!</p>');

Prepend HTML/XML fragment to this node.

  # "<div><h1>Test</h1><h2>123</h2></div>"
  $dom->parse('<div><h2>123</h2></div>')->at('h2')
    ->prepend('<h1>Test</h1>')->root;

  # "<p>Test 123</p>"
  $dom->parse('<p>123</p>')->at('p')->contents->first->prepend('Test ')->root;

=head2 prepend_content

  $dom = $dom->prepend_content('<p>I ♥ Mojolicious!</p>');

Prepend HTML/XML fragment (for C<root> and C<tag> nodes) or raw content to
this node's content.

  # "<div><h2>Test123</h2></div>"
  $dom->parse('<div><h2>123</h2></div>')->at('h2')
    ->prepend_content('Test')->root;

  # "<!-- Test 123 --><br>"
  $dom->parse('<!-- 123 --><br>')
    ->contents->first->prepend_content(' Test')->root;

  # "<p><i>123</i>Test</p>"
  $dom->parse('<p>Test</p>')->at('p')->prepend_content('<i>123</i>')->root;

=head2 previous

  my $sibling = $dom->previous;

Return L<Mojo::DOM> object for previous sibling element or C<undef> if there
are no more siblings.

  # "<h1>Test</h1>"
  $dom->parse('<div><h1>Test</h1><h2>123</h2></div>')->at('h2')->previous;

=head2 previous_sibling

  my $sibling = $dom->previous_sibling;

Return L<Mojo::DOM> object for previous sibling node or C<undef> if there are
no more siblings.

  # "123"
  $dom->parse('<p>123<!-- Test --><b>456</b></p>')->at('b')
    ->previous_sibling->previous_sibling;

=head2 remove

  my $parent = $dom->remove;

Remove this node and return L</"parent">.

  # "<div></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->remove;

  # "<p><b>456</b></p>"
  $dom->parse('<p>123<b>456</b></p>')->at('p')->contents->first->remove->root;

=head2 replace

  my $parent = $dom->replace('<div>I ♥ Mojolicious!</div>');

Replace this node with HTML/XML fragment and return L</"parent">.

  # "<div><h2>123</h2></div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->replace('<h2>123</h2>');

  # "<p><b>123</b></p>"
  $dom->parse('<p>Test</p>')->at('p')
    ->contents->[0]->replace('<b>123</b>')->root;

=head2 root

  my $root = $dom->root;

Return L<Mojo::DOM> object for root node.

=head2 siblings

  my $collection = $dom->siblings;
  my $collection = $dom->siblings('div > p');

Find all sibling elements of this node matching the CSS selector and return a
L<Mojo::Collection> object containing these elements as L<Mojo::DOM> objects.
All selectors from L<Mojo::DOM::CSS/"SELECTORS"> are supported.

  # List types of sibling elements
  say $dom->siblings->type;

=head2 strip

  my $parent = $dom->strip;

Remove this element while preserving its content and return L</"parent">.

  # "<div>Test</div>"
  $dom->parse('<div><h1>Test</h1></div>')->at('h1')->strip;

=head2 tap

  $dom = $dom->tap(sub {...});

Alias for L<Mojo::Base/"tap">.

=head2 text

  my $trimmed   = $dom->text;
  my $untrimmed = $dom->text(0);

Extract text content from this element only (not including child elements),
smart whitespace trimming is enabled by default.

  # "foo baz"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->text;

  # "foo\nbaz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->text(0);

=head2 to_string

  my $str = $dom->to_string;

Render this node and its content to HTML/XML.

  # "<b>Test</b>"
  $dom->parse('<div><b>Test</b></div>')->div->b->to_string;

=head2 tree

  my $tree = $dom->tree;
  $dom     = $dom->tree(['root']);

Document Object Model. Note that this structure should only be used very
carefully since it is very dynamic.

=head2 type

  my $type = $dom->type;
  $dom     = $dom->type('div');

This element's type.

  # List types of child elements
  say $dom->children->type;

=head2 val

  my $collection = $dom->val;

Extract values from C<button>, C<input>, C<option>, C<select> or C<textarea>
element and return a L<Mojo::Collection> object containing these values. In
the case of C<select>, find all C<option> elements it contains that have a
C<selected> attribute and extract their values.

  # "b"
  $dom->parse('<input name="a" value="b">')->at('input')->val;

  # "c"
  $dom->parse('<option value="c">Test</option>')->at('option')->val;

  # "d"
  $dom->parse('<option>d</option>')->at('option')->val;

=head2 wrap

  $dom = $dom->wrap('<div></div>');

Wrap HTML/XML fragment around this node, placing it as the last child of the
first innermost element.

  # "<p>123<b>Test</b></p>"
  $dom->parse('<b>Test</b>')->at('b')->wrap('<p>123</p>')->root;

  # "<div><p><b>Test</b></p>123</div>"
  $dom->parse('<b>Test</b>')->at('b')->wrap('<div><p></p>123</div>')->root;

  # "<p><b>Test</b></p><p>123</p>"
  $dom->parse('<b>Test</b>')->at('b')->wrap('<p></p><p>123</p>')->root;

  # "<p><b>Test</b></p>"
  $dom->parse('<p>Test</p>')->at('p')->contents->first->wrap('<b>')->root;

=head2 wrap_content

  $dom = $dom->wrap_content('<div></div>');

Wrap HTML/XML fragment around this node's content, placing it as the last
children of the first innermost element.

  # "<p><b>123Test</b></p>"
  $dom->parse('<p>Test<p>')->at('p')->wrap_content('<b>123</b>')->root;

  # "<p><b>Test</b></p><p>123</p>"
  $dom->parse('<b>Test</b>')->wrap_content('<p></p><p>123</p>');

=head2 xml

  my $bool = $dom->xml;
  $dom     = $dom->xml($bool);

Disable HTML semantics in parser and activate case sensitivity, defaults to
auto detection based on processing instructions.

=head1 AUTOLOAD

In addition to the L</"METHODS"> above, many child elements are also
automatically available as object methods, which return a L<Mojo::DOM> or
L<Mojo::Collection> object, depending on number of children. For more power
and consistent results you can also use L</"children">.

  # "Test"
  $dom->parse('<p>Test</p>')->p->text;

  # "123"
  $dom->parse('<div>Test</div><div>123</div>')->div->[2]->text;

  # "Test"
  $dom->parse('<div>Test</div>')->div->text;

=head1 OPERATORS

L<Mojo::DOM> overloads the following operators.

=head2 array

  my @nodes = @$dom;

Alias for L</"contents">.

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

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
