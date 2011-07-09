package Mojo::HTML;
use Mojo::Base -base;
use overload
  '%{}'    => sub { shift->attrs },
  'bool'   => sub {1},
  '""'     => sub { shift->to_xml },
  fallback => 1;

use Carp 'croak';
use Mojo::Util qw/decode encode html_unescape xml_escape/;
use Scalar::Util 'weaken';

# Regex
my $XML_ATTR_RE = qr/
  \s*
  ([^=\s>]+)       # Key
  (?:
    \s*
    =
    \s*
    (?:
      "([^"]*?)"   # Quotation marks
      |
      '([^']*?)'   # Apostrophes
      |
      ([^>\s]+)    # Unquoted
    )
  )?
  \s*
/x;
my $XML_END_RE   = qr/^\s*\/\s*(.+)\s*/;
my $XML_START_RE = qr/([^\s\/]+)([\s\S]*)/;
my $XML_TOKEN_RE = qr/
  ([^<]*)                                           # Text
  (?:
    <\?(.*?)\?>                                     # Processing Instruction
    |
    <\!--(.*?)-->                                   # Comment
    |
    <\!\[CDATA\[(.*?)\]\]>                          # CDATA
    |
    <!DOCTYPE(
      \s+\w+
      (?:(?:\s+\w+)?(?:\s+(?:"[^"]*"|'[^']*'))+)?   # External ID
      (?:\s+\[.+?\])?                               # Int Subset
      \s*
    )>
    |
    <(
      \s*
      [^>\s]+                                       # Tag
      (?:$XML_ATTR_RE)*                             # Attributes
    )>
  )??
/xis;

# Optional HTML tags
my @OPTIONAL_TAGS =
  qw/body colgroup dd head li optgroup option p rt rp tbody td tfoot th/;
my %HTML_OPTIONAL;
$HTML_OPTIONAL{$_}++ for @OPTIONAL_TAGS;

# Tags that break HTML paragraphs
my @PARAGRAPH_TAGS = (
  qw/address article aside blockquote dir div dl fieldset footer form h1 h2/,
  qw/h3 h4 h5 h6 header hgroup hr menu nav ol p pre section table or ul/
);
my %HTML_PARAGRAPH;
$HTML_PARAGRAPH{$_}++ for @PARAGRAPH_TAGS;

# HTML table tags
my @TABLE_TAGS = qw/col colgroup tbody td th thead tr/;
my %HTML_TABLE;
$HTML_TABLE{$_}++ for @TABLE_TAGS;

# HTML5 void tags
my @VOID_TAGS = (
  qw/area base br col command embed hr img input keygen link meta param/,
  qw/source track wbr/
);
my %HTML_VOID;
$HTML_VOID{$_}++ for @VOID_TAGS;

# HTML5 block tags + "<head>" + "<html>"
my @BLOCK_TAGS = (
  qw/article aside blockquote body br button canvas caption col colgroup dd/,
  qw/div dl dt embed fieldset figcaption figure footer form h1 h2 h3 h4 h5/,
  qw/h6 head header hgroup hr html li map object ol output p pre progress/,
  qw/section table tbody textarea tfooter th thead tr ul video/
);
my %HTML_BLOCK;
$HTML_BLOCK{$_}++ for @BLOCK_TAGS;

sub AUTOLOAD {
  my $self = shift;

  # Method
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;

  # Search children
  my $children = $self->children($method);
  return @$children > 1 ? $children : $children->[0] if @$children;
  croak qq/Can't locate object method "$method" via package "$package"/;
}

sub DESTROY { }

sub new {
  my $class = shift;
  my $self = bless [], ref $class || $class;

  # Input
  my $xml;
  $xml = shift if @_ % 2;

  # Attributes
  my %attrs = (@_);
  $self->[0] = exists $attrs{tree} ? $attrs{tree} : ['root'];
  $self->[1] = $attrs{charset} if exists $attrs{charset};
  $self->[2] = $attrs{xml}     if exists $attrs{xml};

  # Parse right away
  $self->parse($xml) if defined $xml;

  return $self;
}

sub all_text {
  my $self = shift;

  # Walk tree
  my $text  = '';
  my $tree  = $self->tree;
  my $start = $tree->[0] eq 'root' ? 1 : 4;
  my @stack = @$tree[$start .. $#$tree];
  while (my $e = shift @stack) {
    my $type = $e->[0];

    # Add children of nested tag to stack
    unshift @stack, @$e[4 .. $#$e] and next if $type eq 'tag';

    # Text
    my $content = '';
    if ($type eq 'text') {
      $content = $self->_trim($e->[1], $text =~ /\S$/);
    }

    # CDATA or raw text
    elsif ($type eq 'cdata' || $type eq 'raw') { $content = $e->[1] }

    # Ignore whitespace blocks
    $text .= $content if $content =~ /\S+/;
  }

  return $text;
}

sub append { shift->_add(1, @_) }

sub append_content {
  my ($self, $new) = @_;
  my $tree = $self->tree;
  push @$tree, @{_parent($self->_parse_xml("$new"), $tree->[3])};
  return $self;
}

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
  return $self->[1] if @_ == 0;
  $self->[1] = shift;
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
      $self->new(charset => $self->charset, tree => $e, xml => $self->xml);
  }

  return \@children;
}

sub content_xml {
  my $self = shift;

  # Walk tree
  my $result = '';
  my $tree   = $self->tree;
  my $start  = $tree->[0] eq 'root' ? 1 : 4;
  for my $e (@$tree[$start .. $#$tree]) {
    $result .= $self->_render($e);
  }

  # Encode
  my $charset = $self->charset;
  encode $charset, $result if $charset;

  return $result;
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
  return $self->new(
    charset => $self->charset,
    tree    => $tree->[3],
    xml     => $self->xml
  );
}

sub parse {
  my ($self, $xml) = @_;
  $self->charset(undef) if utf8::is_utf8 $xml;
  return $self->tree($self->_parse_xml($xml));
}

sub prepend { shift->_add(0, @_) }

sub prepend_content {
  my ($self, $new) = @_;
  my $tree = $self->tree;
  splice @$tree, $tree->[0] eq 'root' ? 1 : 4, 0,
    @{_parent($self->_parse_xml("$new"), $tree->[3])};
  return $self;
}

sub replace {
  my ($self, $new) = @_;

  # Parse
  my $tree = $self->tree;
  $self->xml(undef) if my $r = $tree->[0] eq 'root';
  $new = $self->_parse_xml("$new");
  return $self->tree($new) if $r;

  # Find
  my $parent = $tree->[3];
  my $i = $parent->[0] eq 'root' ? 1 : 4;
  for my $e (@$parent[$i .. $#$parent]) {
    last if $e == $tree;
    $i++;
  }

  # Replace
  splice @$parent, $i, 1, @{_parent($new, $parent)};

  return $self;
}

sub replace_content {
  my ($self, $new) = @_;

  # Parse
  $new = $self->_parse_xml("$new");

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

  return $self->new(
    charset => $self->charset,
    tree    => $root,
    xml     => $self->xml
  );
}

sub text {
  my $self = shift;

  # Walk stack
  my $text = '';
  for my $e (@{$self->tree}) {
    next unless ref $e eq 'ARRAY';
    my $type = $e->[0];

    # Text
    my $content = '';
    if ($type eq 'text') {
      $content = $self->_trim($e->[1], $text =~ /\S$/);
    }

    # CDATA or raw text
    elsif ($type eq 'cdata' || $type eq 'raw') { $content = $e->[1] }

    # Ignore whitespace blocks
    $text .= $content if $content =~ /\S+/;
  }

  return $text;
}

sub to_xml {
  my $self    = shift;
  my $result  = $self->_render($self->tree);
  my $charset = $self->charset;
  encode $charset, $result if $charset;
  return $result;
}

sub tree {
  my $self = shift;
  return $self->[0] if @_ == 0;
  $self->[0] = shift;
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

sub xml {
  my $self = shift;
  return $self->[2] if @_ == 0;
  $self->[2] = shift;
  return $self;
}

sub _add {
  my ($self, $offset, $new) = @_;

  # Parse
  $new = $self->_parse_xml("$new");

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

# "Woah! God is so in your face!
#  Yeah, he's my favorite fictional character."
sub _cdata {
  my ($self, $cdata, $current) = @_;
  push @$$current, ['cdata', $cdata];
}

sub _close {
  my ($self, $current, $tags, $stop) = @_;
  $tags ||= \%HTML_TABLE;
  $stop ||= 'table';

  # Check if parents need to be closed
  my $parent = $$current;
  while ($parent) {
    last if $parent->[0] eq 'root' || $parent->[1] eq $stop;

    # Close
    $tags->{$parent->[1]} and $self->_end($parent->[1], $current);

    # Try next
    $parent = $parent->[3];
  }
}

sub _comment {
  my ($self, $comment, $current) = @_;
  push @$$current, ['comment', $comment];
}

sub _doctype {
  my ($self, $doctype, $current) = @_;
  push @$$current, ['doctype', $doctype];
}

sub _end {
  my ($self, $end, $current) = @_;

  # Not a tag
  return if $$current->[0] eq 'root';

  # Search stack for start tag
  my $found = 0;
  my $next  = $$current;
  while ($next) {
    last if $next->[0] eq 'root';

    # Right tag
    ++$found and last if $next->[1] eq $end;

    # Don't cross block tags that are not optional tags
    return
      if !$self->xml
        && $HTML_BLOCK{$next->[1]}
        && !$HTML_OPTIONAL{$next->[1]};

    # Parent
    $next = $next->[3];
  }

  # Ignore useless end tag
  return unless $found;

  # Walk backwards
  $next = $$current;
  while ($$current = $next) {
    last if $$current->[0] eq 'root';
    $next = $$current->[3];

    # Match
    if ($end eq $$current->[1]) { return $$current = $$current->[3] }

    # Optional tags
    elsif ($HTML_OPTIONAL{$$current->[1]}) {
      $self->_end($$current->[1], $current);
    }

    # Table
    elsif ($end eq 'table') { $self->_close($current) }

    # Missing end tag
    $self->_end($$current->[1], $current);
  }
}

sub _parent {
  my ($children, $parent) = @_;
  my @new;
  for my $e (@$children[1 .. $#$children]) {
    $e->[3] = $parent if $e->[0] eq 'tag';
    push @new, $e;
  }
  return \@new;
}

sub _parse_xml {
  my ($self, $xml) = @_;

  # Decode
  my $charset = $self->charset;
  decode $charset, $xml if $charset && !utf8::is_utf8 $xml;

  # Tokenize
  my $tree    = ['root'];
  my $current = $tree;
  while ($xml =~ m/\G$XML_TOKEN_RE/gcs) {
    my $text    = $1;
    my $pi      = $2;
    my $comment = $3;
    my $cdata   = $4;
    my $doctype = $5;
    my $tag     = $6;

    # Text
    if (length $text) {
      html_unescape $text if (index $text, '&') >= 0;
      $self->_text($text, \$current);
    }

    # DOCTYPE
    if ($doctype) { $self->_doctype($doctype, \$current) }

    # Comment
    elsif ($comment) {
      $self->_comment($comment, \$current);
    }

    # CDATA
    elsif ($cdata) { $self->_cdata($cdata, \$current) }

    # Processing instruction
    elsif ($pi) { $self->_pi($pi, \$current) }

    next unless $tag;

    # End
    my $cs = $self->xml;
    if ($tag =~ /$XML_END_RE/) {
      if (my $end = $cs ? $1 : lc($1)) { $self->_end($end, \$current) }
    }

    # Start
    elsif ($tag =~ /$XML_START_RE/) {
      my $start = $cs ? $1 : lc($1);
      my $attr = $2;

      # Attributes
      my $attrs = {};
      while ($attr =~ /$XML_ATTR_RE/g) {
        my $key = $cs ? $1 : lc($1);
        my $value = $2;
        $value = $3 unless defined $value;
        $value = $4 unless defined $value;

        # Empty tag
        next if $key eq '/';

        # Add unescaped value
        html_unescape $value if $value && (index $value, '&') >= 0;
        $attrs->{$key} = $value;
      }

      # Start
      $self->_start($start, $attrs, \$current);

      # Empty tag
      $self->_end($start, \$current)
        if (!$self->xml && $HTML_VOID{$start}) || $attr =~ /\/\s*$/;

      # Relaxed "script" or "style"
      if ($start eq 'script' || $start eq 'style') {
        if ($xml =~ /\G(.*?)<\s*\/\s*$start\s*>/gcsi) {
          $self->_raw($1, \$current);
          $self->_end($start, \$current);
        }
      }
    }
  }

  return $tree;
}

# Try to detect XML from processing instructions
sub _pi {
  my ($self, $pi, $current) = @_;
  $self->xml(1) if !defined $self->xml && $pi =~ /xml/i;
  push @$$current, ['pi', $pi];
}

sub _raw {
  my ($self, $raw, $current) = @_;
  push @$$current, ['raw', $raw];
}

sub _render {
  my ($self, $tree) = @_;

  # Text (escaped)
  my $e = $tree->[0];
  if ($e eq 'text') {
    my $escaped = $tree->[1];
    xml_escape $escaped;
    return $escaped;
  }

  # Raw text
  return $tree->[1] if $e eq 'raw';

  # DOCTYPE
  return "<!DOCTYPE" . $tree->[1] . ">" if $e eq 'doctype';

  # Comment
  return "<!--" . $tree->[1] . "-->" if $e eq 'comment';

  # CDATA
  return "<![CDATA[" . $tree->[1] . "]]>" if $e eq 'cdata';

  # Processing instruction
  return "<?" . $tree->[1] . "?>" if $e eq 'pi';

  # Offset
  my $start = $e eq 'root' ? 1 : 2;

  # Start tag
  my $content = '';
  if ($e eq 'tag') {

    # Offset
    $start = 4;

    # Open tag
    $content .= '<' . $tree->[1];

    # Attributes
    my @attrs;
    for my $key (sort keys %{$tree->[2]}) {
      my $value = $tree->[2]->{$key};

      # No value
      push @attrs, $key and next unless defined $value;

      # Key and value
      xml_escape $value;
      push @attrs, qq/$key="$value"/;
    }
    my $attrs = join ' ', @attrs;
    $content .= " $attrs" if $attrs;

    # Empty tag
    return "$content />" unless $tree->[4];

    # Close tag
    $content .= '>';
  }

  # Walk tree
  $content .= $self->_render($tree->[$_]) for $start .. $#$tree;

  # End tag
  $content .= '</' . $tree->[1] . '>' if $e eq 'tag';

  return $content;
}

# "It's not important to talk about who got rich off of whom,
#  or who got exposed to tainted what..."
sub _start {
  my ($self, $start, $attrs, $current) = @_;

  # Autoclose optional HTML tags
  if (!$self->xml && $$current->[0] ne 'root') {

    # "<li>"
    if ($start eq 'li') { $self->_close($current, {li => 1}, 'ul') }

    # "<p>"
    elsif ($HTML_PARAGRAPH{$start}) { $self->_end('p', $current) }

    # "<head>"
    elsif ($start eq 'body') { $self->_end('head', $current) }

    # "<optgroup>"
    elsif ($start eq 'optgroup') { $self->_end('optgroup', $current) }

    # "<option>"
    elsif ($start eq 'option' || $start eq 'optgroup') {
      $self->_end('option', $current);
      $self->_end('optgroup', $current) if $start eq 'optgroup';
    }

    # "<colgroup>"
    elsif ($start eq 'colgroup') { $self->_close($current) }

    # "<thead>"
    elsif ($start eq 'thead') { $self->_close($current) }

    # "<tbody>"
    elsif ($start eq 'tbody') { $self->_close($current) }

    # "<tfoot>"
    elsif ($start eq 'tfoot') { $self->_close($current) }

    # "<tr>"
    elsif ($start eq 'tr') { $self->_end('tr', $current) }

    # "<th>" and "<td>"
    elsif ($start eq 'th' || $start eq 'td') {
      $self->_end('th', $current);
      $self->_end('td', $current);
    }

    # "<dt>" and "<dd>"
    elsif ($start eq 'dt' || $start eq 'dd') {
      $self->_end('dt', $current);
      $self->_end('dd', $current);
    }

    # "<rt>" and "<rp>"
    elsif ($start eq 'rt' || $start eq 'rp') {
      $self->_end('rt', $current);
      $self->_end('rp', $current);
    }
  }

  # New
  my $new = ['tag', $start, $attrs, $$current];
  weaken $new->[3];
  push @$$current, $new;
  $$current = $new;
}

sub _text {
  my ($self, $text, $current) = @_;
  push @$$current, ['text', $text];
}

sub _trim {
  my ($self, $text, $ws) = @_;

  # Trim whitespace
  $text =~ s/^\s*\n+\s*//;
  $text =~ s/\s*\n+\s*$//;
  $text =~ s/\s*\n+\s*/\ /g;

  # Add leading whitespace if punctuation allows it
  $text = " $text" if $ws && $text =~ /^[^\.\!\?\,\;\:]/;

  return $text;
}

1;
__END__

=head1 NAME

Mojo::HTML - Relaxed HTML5/XML Parser

=head1 SYNOPSIS

  use Mojo::HTML;

  # Parse
  my $html = Mojo::HTML->new('<div><p id="a">A</p><p id="b">B</p></div>');

  # Walk
  print $html->div->p->[0]->text;
  print $html->div->p->[1]->{id};

  # Modify
  $html->div->p->[1]->append('<p id="c">C</p>');

  # Render
  print $html;

=head1 DESCRIPTION

L<Mojo::HTML> is a relaxed HTML5/XML parser and the foundation of
L<Mojo::DOM>.

=head1 METHODS

L<Mojo::HTML> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $html = Mojo::HTML->new;
  my $html = Mojo::HTML->new(xml => 1);
  my $html = Mojo::HTML->new('<foo bar="baz">test</foo>');
  my $html = Mojo::HTML->new('<foo bar="baz">test</foo>', xml => 1);

Construct a new L<Mojo::HTML> object.

=head2 C<all_text>

  my $text = $html->all_text;

Extract all text content from element and child eleemnts.

=head2 C<append>

  $html = $html->append('<p>Hi!</p>');

Append to element.

  # "<div><h1>A</h1><h2>B</h2></div>"
  $html->parse('<div><h1>A</h1></div>')->at('h1')->append('<h2>B</h2>');

=head2 C<append_content>

  $html = $html->append_content('<p>Hi!</p>');

Append to element content.

  # "<div><h1>AB</h1></div>"
  $html->parse('<div><h1>A</h1></div>')->at('h1')->append_content('B');

=head2 C<attrs>

  my $attrs = $html->attrs;
  my $foo   = $html->attrs('foo');
  $html     = $html->attrs({foo => 'bar'});
  $html     = $html->attrs(foo => 'bar');

Element attributes.

  # Direct hash access to attributes is also available
  print $html->{foo};
  print $html->div->{id};

=head2 C<charset>

  my $charset = $html->charset;
  $html       = $html->charset('UTF-8');

Charset used for decoding and encoding XML.

=head2 C<children>

  my $children = $html->children;
  my $children = $html->children('div')

Return an array containing the child elements of this element.

  # Child elements are also automatically available as object methods
  print $html->div->text;
  print $html->div->[23]->text;

=head2 C<content_xml>

  my $xml = $html->content_xml;

Render content of this element to XML.

=head2 C<namespace>

  my $namespace = $html->namespace;

Find element namespace.

=head2 C<parent>

  my $parent = $html->parent;

Parent of element.

=head2 C<parse>

  $html = $html->parse('<foo bar="baz">test</foo>');

Parse XML document.

=head2 C<prepend>

  $html = $html->prepend('<p>Hi!</p>');

Prepend to element.

  # "<div><h1>A</h1><h2>B</h2></div>"
  $html->parse('<div><h2>B</h2></div>')->at('h2')->prepend('<h1>A</h1>');

=head2 C<prepend_content>

  $html = $html->prepend_content('<p>Hi!</p>');

Prepend to element content.

  # "<div><h2>AB</h2></div>"
  $html->parse('<div><h2>B</h2></div>')->at('h2')->prepend_content('A');

=head2 C<replace>

  $html = $html->replace('<div>test</div>');

Replace elements.

  # "<div><h2>B</h2></div>"
  $html->parse('<div><h1>A</h1></div>')->at('h1')->replace('<h2>B</h2>');

=head2 C<replace_content>

  $html = $html->replace_content('test');

Replace element content.

  # "<div><h1>B</h1></div>"
  $html->parse('<div><h1>A</h1></div>')->at('h1')->replace_content('B');

=head2 C<root>

  my $root = $html->root;

Find root element.

=head2 C<text>

  my $text = $html->text;

Extract text content from element only, not including child elements.

=head2 C<to_xml>

  my $xml = $html->to_xml;

Render element and child elements to XML.

=head2 C<tree>

  my $tree = $html->tree;
  $html    = $html->tree(['root', ['text', 'lalala']]);

HTML5/XML tree.

=head2 C<type>

  my $type = $html->type;
  $html    = $html->type('title');

Element type.

=head2 C<xml>

  my $xml = $html->xml;
  $html   = $html->xml(1);

Disable HTML5 semantics in parser and activate case sensitivity, defaults to
auto detection based on processing instructions.
Note that this method is EXPERIMENTAL and might change without warning!

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
