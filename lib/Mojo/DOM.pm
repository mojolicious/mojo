package Mojo::DOM;
use Mojo::Base -base;
use overload
  '%{}'    => sub { shift->attrs },
  'bool'   => sub {1},
  '""'     => sub { shift->to_xml },
  fallback => 1;

use Carp 'croak';
use Mojo::Collection;
use Mojo::DOM::CSS;
use Mojo::DOM::HTML;
use Scalar::Util qw/blessed weaken/;

sub AUTOLOAD {
  my $self = shift;

  # Method
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;
  croak qq/Undefined subroutine &${package}::$method called/
    unless blessed $self && $self->isa(__PACKAGE__);

  # Search children
  my $children = $self->children($method);
  return @$children > 1 ? $children : $children->[0] if @$children;
  croak qq/Can't locate object method "$method" via package "$package"/;
}

sub DESTROY { }

# "How are the kids supposed to get home?
#  I dunno. Internet?"
sub new {
  my $class = shift;
  my $self = bless [Mojo::DOM::HTML->new], ref $class || $class;

  # DEPRECATED in Leaf Fluttering In Wind!
  my $input;
  $input = shift if @_ % 2;
  warn "Mojo::DOM->new with arguments is DEPRECATED!\n" if @_;
  my %attrs = (@_);
  exists($attrs{$_}) and $self->$_($attrs{$_}) for qw/tree charset xml/;

  # Parse right away
  $self->parse($input) if defined $input;

  return $self;
}

# DEPRECATED in Smiling Face With Sunglasses!
sub add_after {
  warn "Mojo::DOM->add_after is DEPRECATED in favor of Mojo::DOM->append!\n";
  shift->append(@_);
}

# DEPRECATED in Smiling Face With Sunglasses!
sub add_before {
  warn
    "Mojo::DOM->add_before is DEPRECATED in favor of Mojo::DOM->prepend!\n";
  shift->prepend(@_);
}

sub all_text {
  my ($self, $trim) = @_;
  return $self->_text($self->tree, 1, defined $trim ? $trim : 1);
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
  my $tree = $self->tree;
  return {} if $tree->[0] eq 'root';

  # Hash
  my $attrs = $tree->[2];
  return $attrs unless @_;

  # Get
  return $attrs->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  for my $key (keys %$values) {
    $attrs->{$key} = $values->{$key};
  }

  return $self;
}

sub charset {
  my $self = shift;
  return $self->[0]->charset if @_ == 0;
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
  @$results =
    map { $self->new->charset($self->charset)->tree($_)->xml($self->xml) }
    @$results;

  return Mojo::Collection->new(@$results);
}

# DEPRECATED in Smiling Face With Sunglasses!
sub inner_xml {
  warn <<EOF;
Mojo::DOM->inner_xml is DEPRECATED in favor of Mojo::DOM->content_xml!
EOF
  shift->content_xml(@_);
}

sub namespace {
  my $self = shift;

  # Prefix
  my $current = $self->tree;
  return if $current->[0] eq 'root';
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
  my $tree = $self->tree;
  return if $tree->[0] eq 'root';

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

# DEPRECATED in Smiling Face With Sunglasses!
sub replace_inner {
  warn <<EOF;
Mojo::DOM->replace_inner is DEPRECATED in favor of
Mojo::DOM->replace_content!
EOF
  shift->content_xml(@_);
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
  return $self->_text($self->tree, 0, defined $trim ? $trim : 1);
}

sub to_xml { shift->[0]->render }

sub tree {
  my $self = shift;
  return $self->[0]->tree if @_ == 0;
  $self->[0]->tree(shift);
  return $self;
}

sub type {
  my ($self, $type) = @_;

  # Not a tag
  my $tree = $self->tree;
  return if $tree->[0] eq 'root';

  # Get
  return $tree->[1] unless $type;

  # Set
  $tree->[1] = $type;

  return $self;
}

# "I want to set the record straight, I thought the cop was a prostitute."
sub xml {
  my $self = shift;
  return $self->[0]->xml if @_ == 0;
  $self->[0]->xml(shift);
  return $self;
}

sub _add {
  my ($self, $offset, $new) = @_;

  # Parse
  $new = $self->_parse("$new");

  # Not a tag
  my $tree = $self->tree;
  return $self if $tree->[0] eq 'root';

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
  my ($self, $tree, $recurse, $trim) = @_;

  # Don't trim preformatted text
  my $start = 4;
  if ($tree->[0] eq 'root') { $start = 1 }
  elsif ($trim) {
    my $parent = $tree;
    while ($parent->[0] eq 'tag') {
      $trim = 0 if $parent->[1] eq 'pre';
      last unless $parent = $parent->[3];
    }
  }

  # Walk tree
  my $text = '';
  for my $e (@$tree[$start .. $#$tree]) {
    my $type = $e->[0];

    # Nested tag
    my $content = '';
    if ($type eq 'tag' && $recurse) { $content = $self->_text($e, 1, $trim) }

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
    $content = " $content"
      if $text =~ /\S\z/ && $content =~ /^[^\.\!\?\,\;\:\s]+/;

    # Trim whitespace blocks
    $text .= $content if $content =~ /\S+/ || !$trim;
  }

  return $text;
}

1;
__END__

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
  say $dom->div->p->[1]->{id};

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
selector support.
It will even try to interpret broken XML, so you should not use it for
validation.

=head1 CASE SENSITIVITY

L<Mojo::DOM> defaults to HTML5 semantics, that means all tags and attributes
are lowercased and selectors need to be lowercase as well.

  my $dom = Mojo::DOM->new('<P ID="greeting">Hi!</P>');
  say $dom->at('p')->text;
  say $dom->p->{id};

If XML processing instructions are found, the parser will automatically
switch into XML mode and everything becomes case sensitive.

  my $dom = Mojo::DOM->new('<?xml version="1.0"?><P ID="greeting">Hi!</P>');
  say $dom->at('P')->text;
  say $dom->P->{ID};

XML detection can be also deactivated with the C<xml> method.

  # XML sematics
  $dom->xml(1);

  # HTML5 semantics
  $dom->xml(0);

=head1 METHODS

L<Mojo::DOM> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $dom = Mojo::DOM->new;
  my $dom = Mojo::DOM->new('<foo bar="baz">test</foo>');

Construct a new L<Mojo::DOM> object.

=head2 C<all_text>

  my $trimmed   = $dom->all_text;
  my $untrimmed = $dom->all_text(0);

Extract all text content from DOM structure, smart whitespace trimming is
activated by default.
Note that the trim argument of this method is EXPERIMENTAL and might change
without warning!

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

Find a single element with CSS3 selectors.
All selectors from L<Mojo::DOM::CSS> are supported.

=head2 C<attrs>

  my $attrs = $dom->attrs;
  my $foo   = $dom->attrs('foo');
  $dom      = $dom->attrs({foo => 'bar'});
  $dom      = $dom->attrs(foo => 'bar');

Element attributes.

  # Direct hash access to attributes is also available
  say $dom->{foo};
  say $dom->div->{id};

=head2 C<charset>

  my $charset = $dom->charset;
  $dom        = $dom->charset('UTF-8');

Alias for L<Mojo::DOM::HTML/"charset">.

=head2 C<children>

  my $collection = $dom->children;
  my $collection = $dom->children('div')

Return a L<Mojo::Collection> object containing the children of this element,
similar to C<find>.

  # Child elements are also automatically available as object methods
  say $dom->div->text;
  say $dom->div->[23]->text;
  $dom->div->each(sub { say $_->text });

=head2 C<content_xml>

  my $xml = $dom->content_xml;

Render content of this element to XML.

=head2 C<find>

  my $collection = $dom->find('html title');

Find elements with CSS3 selectors and return a L<Mojo::Collection> object.
All selectors from L<Mojo::DOM::CSS> are supported.

  # Find a specific element and extract information
  my $id = $dom->find('div')->[23]->{id};

  # Extract information from multiple elements
  my @headers = $dom->find('h1, h2, h3')->map(sub { shift->text })->each;

=head2 C<namespace>

  my $namespace = $dom->namespace;

Find element namespace.

=head2 C<parent>

  my $parent = $dom->parent;

Parent of element.

=head2 C<parse>

  $dom = $dom->parse('<foo bar="baz">test</foo>');

Alias for L<Mojo::DOM::HTML/"parse">.

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
whitespace trimming is activated by default.
Note that the trim argument of this method is EXPERIMENTAL and might change
without warning!

=head2 C<to_xml>

  my $xml = $dom->to_xml;

Render DOM to XML.

=head2 C<tree>

  my $tree = $dom->tree;
  $dom     = $dom->tree(['root', ['text', 'lalala']]);

Alias for L<Mojo::DOM::HTML/"tree">.

=head2 C<type>

  my $type = $dom->type;
  $dom     = $dom->type('html');

Element type.

=head2 C<xml>

  my $xml = $dom->xml;
  $dom    = $dom->xml(1);

Alias for L<Mojo::DOM::HTML/"xml">.
Note that this method is EXPERIMENTAL and might change without warning!

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
