package Mojo::DOM;
use Mojo::Base -strict;
use overload
  '%{}'    => sub { shift->attrs },
  'bool'   => sub {1},
  '""'     => sub { shift->to_xml },
  fallback => 1;

use Carp 'croak';
use Mojo::Collection;
use Mojo::DOM::CSS;
use Mojo::DOM::HTML;
use Scalar::Util qw(blessed weaken);

sub AUTOLOAD {
  my $self = shift;

  # Method
  my ($package, $method) = our $AUTOLOAD =~ /^([\w:]+)\:\:(\w+)$/;
  croak qq[Undefined subroutine &${package}::$method called]
    unless blessed $self && $self->isa(__PACKAGE__);

  # Search children
  my $children = $self->children($method);
  return @$children > 1 ? $children : $children->[0] if @$children;
  croak qq{Can't locate object method "$method" via package "$package"};
}

sub DESTROY { }

# "How are the kids supposed to get home?
#  I dunno. Internet?"
sub new {
  my $class = shift;
  my $self = bless [Mojo::DOM::HTML->new], ref $class || $class;
  return @_ ? $self->parse(@_) : $self;
}

sub all_text {
  my ($self, $trim) = @_;
  my $tree = $self->tree;
  return _text(_elements($tree), 1, _trim($tree, $trim));
}

sub append { shift->_add(1, @_) }

sub append_content {
  my ($self, $new) = @_;
  my $tree = $self->tree;
  push @$tree, @{_parent($self->_parse("$new"), $tree)};
  return $self;
}

sub at { shift->find(@_)->[0] }

sub attrs {
  my $self = shift;

  # Not a tag
  return {} if (my $tree = $self->tree)->[0] eq 'root';

  # Hash
  my $attrs = $tree->[2];
  return $attrs unless @_;

  # Get
  return $attrs->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  %$attrs = (%$attrs, %{ref $_[0] ? $_[0] : {@_}});

  return $self;
}

sub charset {
  my $self = shift;
  return $self->[0]->charset unless @_;
  $self->[0]->charset(shift);
  return $self;
}

# "Oh boy! Sleep! That's when I'm a Viking!"
sub children {
  my ($self, $type) = @_;

  # Walk tree
  my @children;
  my $tree = $self->tree;
  my $start = $tree->[0] eq 'root' ? 1 : 4;
  for my $e (@$tree[$start .. $#$tree]) {

    # Make sure child is a tag
    next unless $e->[0] eq 'tag';
    next if defined $type && $e->[1] ne $type;

    # Add child
    push @children,
      $self->new->charset($self->charset)->tree($e)->xml($self->xml);
  }

  return Mojo::Collection->new(@children);
}

sub content_xml {
  my $self = shift;

  # Walk tree
  my $result = '';
  my $tree   = $self->tree;
  my $start  = $tree->[0] eq 'root' ? 1 : 4;
  for my $e (@$tree[$start .. $#$tree]) {
    $result .= Mojo::DOM::HTML->new(
      charset => $self->charset,
      tree    => $e,
      xml     => $self->xml
    )->render;
  }

  return $result;
}

# "But I was going to loot you a present."
sub find {
  my ($self, $selector) = @_;

  # Match selector against tree
  my $results = Mojo::DOM::CSS->new(tree => $self->tree)->select($selector);

  # Upgrade results
  @$results
    = map { $self->new->charset($self->charset)->tree($_)->xml($self->xml) }
    @$results;

  return Mojo::Collection->new(@$results);
}

sub namespace {
  my $self = shift;

  # Prefix
  return if (my $current = $self->tree)->[0] eq 'root';
  my $prefix = '';
  if ($current->[1] =~ /^(.*?)\:/) { $prefix = $1 }

  # Walk tree
  while ($current) {
    return if $current->[0] eq 'root';
    my $attrs = $current->[2];

    # Namespace for prefix
    if ($prefix) {
      for my $key (keys %$attrs) {
        return $attrs->{$key} if $key =~ /^xmlns\:$prefix$/;
      }
    }

    # Namespace attribute
    elsif (defined $attrs->{xmlns}) { return $attrs->{xmlns} || undef }

    # Parent
    $current = $current->[3];
  }
}

sub parent {
  my $self = shift;

  # Not a tag
  return if (my $tree = $self->tree)->[0] eq 'root';

  # Parent
  return $self->new->charset($self->charset)->tree($tree->[3])
    ->xml($self->xml);
}

sub parse {
  my $self = shift;
  $self->[0]->parse(@_);
  return $self;
}

sub prepend { shift->_add(0, @_) }

sub prepend_content {
  my ($self, $new) = @_;
  my $tree = $self->tree;
  splice @$tree, $tree->[0] eq 'root' ? 1 : 4, 0,
    @{_parent($self->_parse("$new"), $tree)};
  return $self;
}

sub replace {
  my ($self, $new) = @_;

  # Parse
  my $tree = $self->tree;
  if ($tree->[0] eq 'root') {
    $self->xml(undef);
    return $self->parse($new);
  }
  else { $new = $self->_parse("$new") }

  # Find and replace
  my $parent = $tree->[3];
  my $i = $parent->[0] eq 'root' ? 1 : 4;
  for my $e (@$parent[$i .. $#$parent]) {
    last if $e == $tree;
    $i++;
  }
  splice @$parent, $i, 1, @{_parent($new, $parent)};

  return $self;
}

sub replace_content {
  my ($self, $new) = @_;

  # Parse
  $new = $self->_parse("$new");

  # Replacements
  my $tree = $self->tree;
  my @new;
  for my $e (@$new[1 .. $#$new]) {
    $e->[3] = $tree if $e->[0] eq 'tag';
    push @new, $e;
  }

  # Replace
  my $start = $tree->[0] eq 'root' ? 1 : 4;
  splice @$tree, $start, $#$tree, @new;

  return $self;
}

sub root {
  my $self = shift;

  # Find root
  my $root = $self->tree;
  while ($root->[0] eq 'tag') {
    last unless my $parent = $root->[3];
    $root = $parent;
  }

  return $self->new->charset($self->charset)->tree($root)->xml($self->xml);
}

sub text {
  my ($self, $trim) = @_;
  my $tree = $self->tree;
  return _text(_elements($tree), 0, _trim($tree, $trim));
}

sub text_after {
  my ($self, $trim) = @_;

  # Find following text elements
  return '' if (my $tree = $self->tree)->[0] eq 'root';
  my (@elements, $started);
  for my $e (@{_elements($tree->[3])}) {
    ++$started and next if $e eq $tree;
    next unless $started;
    last if $e->[0] eq 'tag';
    push @elements, $e;
  }

  return _text(\@elements, 0, _trim($tree->[3], $trim));
}

sub text_before {
  my ($self, $trim) = @_;

  # Find preceding text elements
  return '' if (my $tree = $self->tree)->[0] eq 'root';
  my @elements;
  for my $e (@{_elements($tree->[3])}) {
    last if $e eq $tree;
    push @elements, $e;
    @elements = () if $e->[0] eq 'tag';
  }

  return _text(\@elements, 0, _trim($tree->[3], $trim));
}

sub to_xml { shift->[0]->render }

sub tree {
  my $self = shift;
  return $self->[0]->tree unless @_;
  $self->[0]->tree(shift);
  return $self;
}

sub type {
  my ($self, $type) = @_;

  # Not a tag
  return if (my $tree = $self->tree)->[0] eq 'root';

  # Get
  return $tree->[1] unless $type;

  # Set
  $tree->[1] = $type;

  return $self;
}

# "I want to set the record straight, I thought the cop was a prostitute."
sub xml {
  my $self = shift;
  return $self->[0]->xml unless @_;
  $self->[0]->xml(shift);
  return $self;
}

sub _add {
  my ($self, $offset, $new) = @_;

  # Parse
  $new = $self->_parse("$new");

  # Not a tag
  return $self if (my $tree = $self->tree)->[0] eq 'root';

  # Find
  my $parent = $tree->[3];
  my $i = $parent->[0] eq 'root' ? 1 : 4;
  for my $e (@$parent[$i .. $#$parent]) {
    last if $e == $tree;
    $i++;
  }

  # Add
  splice @$parent, $i + $offset, 0, @{_parent($new, $parent)};

  return $self;
}

sub _elements {
  my $e = shift;
  return [@$e[($e->[0] eq 'root' ? 1 : 4) .. $#$e]];
}

sub _parent {
  my ($children, $parent) = @_;
  my @new;
  for my $e (@$children[1 .. $#$children]) {
    if ($e->[0] eq 'tag') {
      $e->[3] = $parent;
      weaken $e->[3];
    }
    push @new, $e;
  }
  return \@new;
}

sub _parse {
  my $self = shift;
  Mojo::DOM::HTML->new(charset => $self->charset, xml => $self->xml)
    ->parse(shift)->tree;
}

sub _text {
  my ($elements, $recurse, $trim) = @_;

  # Walk tree
  my $text = '';
  for my $e (@$elements) {
    my $type = $e->[0];

    # Nested tag
    my $content = '';
    if ($type eq 'tag' && $recurse) {
      $content = _text(_elements($e), 1, _trim($e, $trim));
    }

    # Text
    elsif ($type eq 'text') {
      $content = $e->[1];

      # Trim whitespace
      if ($trim) {
        $content =~ s/^\s*\n+\s*//;
        $content =~ s/\s*\n+\s*$//;
        $content =~ s/\s*\n+\s*/\ /g;
      }
    }

    # CDATA or raw text
    elsif ($type eq 'cdata' || $type eq 'raw') { $content = $e->[1] }

    # Add leading whitespace if punctuation allows it
    $content = " $content" if $text =~ /\S\z/ && $content =~ /^[^.!?,;:\s]+/;

    # Trim whitespace blocks
    $text .= $content if $content =~ /\S+/ || !$trim;
  }

  return $text;
}

sub _trim {
  my ($e, $trim) = @_;

  # Disabled
  return 0 unless $trim = defined $trim ? $trim : 1;

  # Detect "pre" tag
  while ($e->[0] eq 'tag') {
    return 0 if $e->[1] eq 'pre';
    last unless $e = $e->[3];
  }

  return 1;
}

1;

=head1 NAME

Mojo::DOM - Minimalistic HTML5/XML DOM parser with CSS3 selectors

=head1 SYNOPSIS

  use Mojo::DOM;

  # Parse
  my $dom = Mojo::DOM->new('<div><p id="a">A</p><p id="b">B</p></div>');

  # Find
  my $b = $dom->at('#b');
  say $b->text;

  # Walk
  say $dom->div->p->[0]->text;
  say $dom->div->children('p')->first->{id};

  # Iterate
  $dom->find('p[id]')->each(sub { say shift->{id} });

  # Loop
  for my $e ($dom->find('p[id]')->each) {
    say $e->text;
  }

  # Modify
  $dom->div->p->[1]->append('<p id="c">C</p>');

  # Render
  say $dom;

=head1 DESCRIPTION

L<Mojo::DOM> is a minimalistic and relaxed HTML5/XML DOM parser with CSS3
selector support. It will even try to interpret broken XML, so you should not
use it for validation.

=head1 CASE SENSITIVITY

L<Mojo::DOM> defaults to HTML5 semantics, that means all tags and attributes
are lowercased and selectors need to be lowercase as well.

  my $dom = Mojo::DOM->new('<P ID="greeting">Hi!</P>');
  say $dom->at('p')->text;
  say $dom->p->{id};

If XML processing instructions are found, the parser will automatically switch
into XML mode and everything becomes case sensitive.

  my $dom = Mojo::DOM->new('<?xml version="1.0"?><P ID="greeting">Hi!</P>');
  say $dom->at('P')->text;
  say $dom->P->{ID};

XML detection can also be disabled with the C<xml> method.

  # Force XML semantics
  $dom->xml(1);

  # Force HTML5 semantics
  $dom->xml(0);

=head1 METHODS

L<Mojo::DOM> implements the following methods.

=head2 C<new>

  my $dom = Mojo::DOM->new;
  my $dom = Mojo::DOM->new('<foo bar="baz">test</foo>');

Construct a new L<Mojo::DOM> object.

=head2 C<all_text>

  my $trimmed   = $dom->all_text;
  my $untrimmed = $dom->all_text(0);

Extract all text content from DOM structure, smart whitespace trimming is
enabled by default.

  # "foo bar baz"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->all_text;

  # "foo\nbarbaz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->all_text(0);

=head2 C<append>

  $dom = $dom->append('<p>Hi!</p>');

Append to element.

  # "<div><h1>A</h1><h2>B</h2></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->append('<h2>B</h2>');

=head2 C<append_content>

  $dom = $dom->append_content('<p>Hi!</p>');

Append to element content.

  # "<div><h1>AB</h1></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->append_content('B');

=head2 C<at>

  my $result = $dom->at('html title');

Find a single element with CSS3 selectors. All selectors from
L<Mojo::DOM::CSS> are supported.

  # Find first element with "svg" namespace definition
  my $namespace = $dom->at('[xmlns\:svg]')->{'xmlns:svg'};

=head2 C<attrs>

  my $attrs = $dom->attrs;
  my $foo   = $dom->attrs('foo');
  $dom      = $dom->attrs({foo => 'bar'});
  $dom      = $dom->attrs(foo => 'bar');

Element attributes.

=head2 C<charset>

  my $charset = $dom->charset;
  $dom        = $dom->charset('UTF-8');

Alias for L<Mojo::DOM::HTML/"charset">.

=head2 C<children>

  my $collection = $dom->children;
  my $collection = $dom->children('div');

Return a L<Mojo::Collection> object containing the children of this element,
similar to C<find>.

  # Show type of random child element
  say $dom->children->shuffle->first->type;

=head2 C<content_xml>

  my $xml = $dom->content_xml;

Render content of this element to XML.

  # "<b>test</b>"
  $dom->parse('<div><b>test</b></div>')->div->content_xml;

=head2 C<find>

  my $collection = $dom->find('html title');

Find elements with CSS3 selectors and return a L<Mojo::Collection> object. All
selectors from L<Mojo::DOM::CSS> are supported.

  # Find a specific element and extract information
  my $id = $dom->find('div')->[23]{id};

  # Extract information from multiple elements
  my @headers = $dom->find('h1, h2, h3')->map(sub { shift->text })->each;

=head2 C<namespace>

  my $namespace = $dom->namespace;

Find element namespace.

   # Find namespace for an element with namespace prefix
   my $namespace = $dom->at('svg > svg\:circle')->namespace;

   # Find namespace for an element that may or may not have a namespace prefix
   my $namespace = $dom->at('svg > circle')->namespace;

=head2 C<parent>

  my $parent = $dom->parent;

Parent of element.

=head2 C<parse>

  $dom = $dom->parse('<foo bar="baz">test</foo>');

Alias for L<Mojo::DOM::HTML/"parse">.

  # Parse UTF-8 encoded XML
  my $dom = Mojo::DOM->new->charset('UTF-8')->xml(1)->parse($xml);

=head2 C<prepend>

  $dom = $dom->prepend('<p>Hi!</p>');

Prepend to element.

  # "<div><h1>A</h1><h2>B</h2></div>"
  $dom->parse('<div><h2>B</h2></div>')->at('h2')->prepend('<h1>A</h1>');

=head2 C<prepend_content>

  $dom = $dom->prepend_content('<p>Hi!</p>');

Prepend to element content.

  # "<div><h2>AB</h2></div>"
  $dom->parse('<div><h2>B</h2></div>')->at('h2')->prepend_content('A');

=head2 C<replace>

  $dom = $dom->replace('<div>test</div>');

Replace elements.

  # "<div><h2>B</h2></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->replace('<h2>B</h2>');

=head2 C<replace_content>

  $dom = $dom->replace_content('test');

Replace element content.

  # "<div><h1>B</h1></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->replace_content('B');

=head2 C<root>

  my $root = $dom->root;

Find root node.

=head2 C<text>

  my $trimmed   = $dom->text;
  my $untrimmed = $dom->text(0);

Extract text content from element only (not including child elements), smart
whitespace trimming is enabled by default.

  # "foo baz"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->text;

  # "foo\nbaz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->text(0);

=head2 C<text_after>

  my $trimmed   = $dom->text_after;
  my $untrimmed = $dom->text_after(0);

Extract text content immediately following element, smart whitespace trimming
is enabled by default.

  # "baz"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->p->text_after;

  # "baz\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->p->text_after(0);

=head2 C<text_before>

  my $trimmed   = $dom->text_before;
  my $untrimmed = $dom->text_before(0);

Extract text content immediately preceding element, smart whitespace trimming
is enabled by default.

  # "foo"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->p->text_before;

  # "foo\n"
  $dom->parse("<div>foo\n<p>bar</p>baz\n</div>")->div->p->text_before(0);

=head2 C<to_xml>

  my $xml = $dom->to_xml;

Render this element and its content to XML.

  # "<div><b>test</b></div>"
  $dom->parse('<div><b>test</b></div>')->div->to_xml;

=head2 C<tree>

  my $tree = $dom->tree;
  $dom     = $dom->tree(['root', [qw(text lalala)]]);

Alias for L<Mojo::DOM::HTML/"tree">.

=head2 C<type>

  my $type = $dom->type;
  $dom     = $dom->type('div');

Element type.

  # List types of child elements
  $dom->children->each(sub { say $_->type });

=head2 C<xml>

  my $xml = $dom->xml;
  $dom    = $dom->xml(1);

Alias for L<Mojo::DOM::HTML/"xml">.

=head1 CHILD ELEMENTS

In addition to the methods above, many child elements are also automatically
available as object methods, which return a L<Mojo::DOM> or
L<Mojo::Collection> object, depending on number of children.

  say $dom->p->text;
  say $dom->div->[23]->text;
  $dom->div->each(sub { say $_->text });

=head1 ELEMENT ATTRIBUTES

Direct hash reference access to element attributes is also possible.

  say $dom->{foo};
  say $dom->div->{id};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
