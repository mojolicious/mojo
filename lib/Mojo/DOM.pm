package Mojo::DOM;
use Mojo::Base -base;
use overload 'bool' => sub {1}, fallback => 1;
use overload '""' => sub { shift->to_xml }, fallback => 1;
use overload '%{}' => sub { shift->attrs };

use Carp 'croak';
use Mojo::Util qw/decode encode html_unescape xml_escape/;
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_DOM_DEBUG} || 0;

# Regex
my $CSS_ESCAPE_RE = qr/\\[^0-9a-fA-F]|\\[0-9a-fA-F]{1,6}/;
my $CSS_ATTR_RE   = qr/
  \[
  ((?:$CSS_ESCAPE_RE|\w)+)        # Key
  (?:
    (\W)?                         # Operator
    =
    (?:"((?:\\"|[^"])+)"|(\S+))   # Value
  )?
  \]
/x;
my $CSS_CLASS_ID_RE = qr/
  (?:
    (?:\.((?:\\\.|[^\#\.])+))   # Class
  |
    (?:\#((?:\\\#|[^\.\#])+))   # ID
  )
/x;
my $CSS_ELEMENT_RE      = qr/^((?:\\\.|\\\#|[^\.\#])+)/;
my $CSS_PSEUDO_CLASS_RE = qr/(?:\:([\w\-]+)(?:\(((?:\([^\)]+\)|[^\)])+)\))?)/;
my $CSS_TOKEN_RE        = qr/
  (\s*,\s*)?                                # Separator
  ((?:[^\[\\\:\s\,]|$CSS_ESCAPE_RE\s?)+)?   # Element
  ($CSS_PSEUDO_CLASS_RE*)?                  # Pseudoclass
  ((?:$CSS_ATTR_RE)*)?                      # Attributes
  (?:
  \s*
  ([\>\+\~])                                # Combinator
  )?
/x;
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

# "How are the kids supposed to get home?
#  I dunno. Internet?"
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

# DEPRECATED in Smiling Face With Sunglasses!
sub add_after {
  warn <<EOF;
Mojo::DOM->add_after is DEPRECATED in favor of Mojo::DOM->append!!!
EOF
  shift->append(@_);
}

# DEPRECATED in Smiling Face With Sunglasses!
sub add_before {
  warn <<EOF;
Mojo::DOM->add_before is DEPRECATED in favor of Mojo::DOM->prepend!!!
EOF
  shift->prepend(@_);
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

sub append_inner {
  my ($self, $new) = @_;
  my $tree = $self->tree;
  push @$tree, @{_parent($self->_parse_xml("$new"), $tree->[3])};
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
  return $self->[1] if @_ == 0;
  $self->[1] = shift;
  return $self;
}

sub children {
  my ($self, $type) = @_;

  # Walk tree
  my @children;
  my $tree = $self->tree;
  my $start = $tree->[0] eq 'root' ? 1 : 4;
  for my $e (@$tree[$start .. $#$tree]) {

    # Tag
    next unless $e->[0] eq 'tag';
    next if defined $type && $e->[1] ne $type;

    # Add child
    push @children,
      $self->new(charset => $self->charset, tree => $e, xml => $self->xml);
  }

  # Collection
  return bless \@children, 'Mojo::DOM::_Collection';
}

sub find {
  my ($self, $css) = @_;

  # Parse CSS selectors
  my $pattern = $self->_parse_css($css);

  # Filter tree
  return $self->_match_tree($self->tree, $pattern);
}

sub inner_xml {
  my $self = shift;

  # Walk tree
  my $tree   = $self->tree;
  my $result = '';
  my $start  = $tree->[0] eq 'root' ? 1 : 4;
  for my $e (@$tree[$start .. $#$tree]) {

    # Render
    $result .= $self->_render($e);
  }

  # Encode
  my $charset = $self->charset;
  encode $charset, $result if $charset;

  return $result;
}

sub namespace {
  my $self = shift;

  my $current = $self->tree;
  return if $current->[0] eq 'root';

  # Prefix
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

  # Detect Perl characters
  $self->charset(undef) if utf8::is_utf8 $xml;

  # Parse
  $self->tree($self->_parse_xml($xml));
}

sub prepend { shift->_add(0, @_) }

sub prepend_inner {
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

sub replace_inner {
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

  my $text = '';

  # Walk stack
  for my $e (@{$self->tree}) {

    # Meta data
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
  my $self = shift;

  # Render
  my $result = $self->_render($self->tree);

  # Encode
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

  # Default to table tags
  $tags ||= \%HTML_TABLE;

  # Default to table tag
  $stop ||= 'table';

  # Check parents
  my $parent = $$current;
  while ($parent) {
    last if $parent->[0] eq 'root' || $parent->[1] eq $stop;

    # Match
    $tags->{$parent->[1]} and $self->_end($parent->[1], $current);

    # Next
    $parent = $parent->[3];
  }
}

sub _comment {
  my ($self, $comment, $current) = @_;
  push @$$current, ['comment', $comment];
}

sub _css_equation {
  my ($self, $equation) = @_;
  my $num = [1, 1];

  # "even"
  if ($equation =~ /^even$/i) { $num = [2, 2] }

  # "odd"
  elsif ($equation =~ /^odd$/i) { $num = [2, 1] }

  # Equation
  elsif ($equation =~ /(?:(\-?(?:\d+)?)?(n))?\s*\+?\s*(\-?\s*\d+)?\s*$/i) {
    $num->[0] = $1;
    $num->[0] = $2 ? 1 : 0 unless defined($num->[0]) && length($num->[0]);
    $num->[0] = -1 if $num->[0] eq '-';
    $num->[1] = $3 || 0;
    $num->[1] =~ s/\s+//g;
  }

  return $num;
}

sub _css_regex {
  my ($self, $op, $value) = @_;

  return unless $value;
  $value = quotemeta $self->_css_unescape($value);

  my $regex;

  # "~=" (word)
  if ($op eq '~') { $regex = qr/(?:^|.*\s+)$value(?:\s+.*|$)/ }

  # "*=" (contains)
  elsif ($op eq '*') { $regex = qr/$value/ }

  # "^=" (begins with)
  elsif ($op eq '^') { $regex = qr/^$value/ }

  # "$=" (ends with)
  elsif ($op eq '$') { $regex = qr/$value$/ }

  # Everything else
  else { $regex = qr/^$value$/ }

  return $regex;
}

sub _css_unescape {
  my ($self, $value) = @_;

  # Remove escaped newlines
  $value =~ s/\\\n//g;

  # Unescape unicode characters
  $value =~ s/\\([0-9a-fA-F]{1,6})\s?/pack('U', hex $1)/gex;

  # Remove backslash
  $value =~ s/\\//g;

  return $value;
}

sub _doctype {
  my ($self, $doctype, $current) = @_;
  push @$$current, ['doctype', $doctype];
}

sub _end {
  my ($self, $end, $current) = @_;

  warn "END $end\n" if DEBUG;

  # Not a tag
  return if $$current->[0] eq 'root';

  # Search stack for start tag
  my $found = 0;
  my $next  = $$current;
  while ($next) {
    last if $next->[0] eq 'root';

    # Found
    ++$found and last if $next->[1] eq $end;

    # Don't cross block tags that are not optional tags
    return
      if !$self->xml
        && $HTML_BLOCK{$next->[1]}
        && !$HTML_OPTIONAL{$next->[1]};

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

sub _match_element {
  my ($self, $candidate, $selectors) = @_;

  my @selectors  = reverse @$selectors;
  my $first      = 2;
  my $parentonly = 0;
  my $tree       = $self->tree;
  my ($current, $marker, $snapback, $siblings);

  # Match
  for (my $i = 0; $i <= $#selectors; $i++) {
    my $selector = $selectors[$i];

    # Combinator
    $parentonly-- if $parentonly > 0;
    if ($selector->[0] eq 'combinator') {

      # Combinator
      my $c = $selector->[1];

      # Parent only ">"
      if ($c eq '>') {
        $parentonly += 2;

        # Can't go back to the first
        unless ($first) {
          $marker   = $i       unless defined $marker;
          $snapback = $current unless $snapback;
        }
      }

      # Preceding siblings "~" and "+"
      elsif ($c eq '~' || $c eq '+') {
        my $parent = $current->[3];
        my $start = $parent->[0] eq 'root' ? 1 : 4;
        $siblings = [];

        # Siblings
        for my $i ($start .. $#$parent) {
          my $sibling = $parent->[$i];
          next unless $sibling->[0] eq 'tag';

          # Reached current
          if ($sibling eq $current) {
            @$siblings = ($siblings->[-1]) if $c eq '+';
            last;
          }
          push @$siblings, $sibling;
        }
      }

      # Move on
      next;
    }

    # Walk backwards
    while (1) {
      $first-- if $first > 0;

      # Next sibling
      if ($siblings) {

        # Last sibling
        unless ($current = shift @$siblings) {
          $siblings = undef;
          return;
        }
      }

      # Next parent
      else {
        return
          unless $current = $current ? $current->[3] : $candidate;

        # Don't search beyond the current tree
        return if $current eq $tree;
      }

      # Not a tag
      return if $current->[0] ne 'tag';

      # Compare part to element
      if ($self->_match_selector($selector, $current)) {
        $siblings = undef;
        last;
      }

      # First selector needs to match
      return if $first;

      # Parent only
      if ($parentonly) {

        # First parent needs to match
        return unless defined $marker;

        # Reset
        $i        = $marker - 2;
        $current  = $snapback;
        $snapback = undef;
        $marker   = undef;
        last;
      }
    }
  }

  return 1;
}

sub _match_selector {
  my ($self, $selector, $current) = @_;

  # Selectors
  for my $c (@$selector[1 .. $#$selector]) {
    my $type = $c->[0];

    # Tag
    if ($type eq 'tag') {
      my $type = $c->[1];

      # Wildcard
      next if $type eq '*';

      # Type (ignore namespace prefix)
      next if $current->[1] =~ /(?:^|\:)$type$/;
    }

    # Attribute
    elsif ($type eq 'attribute') {
      my $key   = $c->[1];
      my $regex = $c->[2];
      my $attrs = $current->[2];

      # Find attributes (ignore namespace prefix)
      my $found = 0;
      for my $name (keys %$attrs) {
        if ($name =~ /\:?$key$/) {
          ++$found and last
            if !$regex || ($attrs->{$name} || '') =~ /$regex/;
        }
      }
      next if $found;
    }

    # Pseudo class
    elsif ($type eq 'pseudoclass') {
      my $class = lc $c->[1];
      my $args  = $c->[2];

      # "first-*"
      if ($class =~ /^first\-(?:(child)|of-type)$/) {
        $class = defined $1 ? 'nth-child' : 'nth-of-type';
        $args = 1;
      }

      # "last-*"
      elsif ($class =~ /^last\-(?:(child)|of-type)$/) {
        $class = defined $1 ? 'nth-last-child' : 'nth-last-of-type';
        $args = '-n+1';
      }

      # ":checked"
      if ($class eq 'checked') {
        my $attrs = $current->[2];
        next if ($attrs->{checked}  || '') eq 'checked';
        next if ($attrs->{selected} || '') eq 'selected';
      }

      # ":empty"
      elsif ($class eq 'empty') { next unless exists $current->[4] }

      # ":root"
      elsif ($class eq 'root') {
        if (my $parent = $current->[3]) {
          next if $parent->[0] eq 'root';
        }
      }

      # "not"
      elsif ($class eq 'not') {
        next unless $self->_match_selector($args, $current);
      }

      # "nth-*"
      elsif ($class =~ /^nth-/) {

        # Numbers
        $args = $c->[2] = $self->_css_equation($args)
          unless ref $args;

        # Parent
        my $parent = $current->[3];

        # Siblings
        my $start = $parent->[0] eq 'root' ? 1 : 4;
        my @siblings;
        my $type = $class =~ /of-type$/ ? $current->[1] : undef;
        for my $j ($start .. $#$parent) {
          my $sibling = $parent->[$j];
          next unless $sibling->[0] eq 'tag';
          next if defined $type && $type ne $sibling->[1];
          push @siblings, $sibling;
        }

        # Reverse
        @siblings = reverse @siblings if $class =~ /^nth-last/;

        # Find
        my $found = 0;
        for my $i (0 .. $#siblings) {
          my $result = $args->[0] * $i + $args->[1];
          next if $result < 1;
          last unless my $sibling = $siblings[$result - 1];
          if ($sibling eq $current) {
            $found = 1;
            last;
          }
        }
        next if $found;
      }

      # "only-*"
      elsif ($class =~ /^only-(?:child|(of-type))$/) {
        my $type = $1 ? $current->[1] : undef;

        # Parent
        my $parent = $current->[3];

        # Siblings
        my $start = $parent->[0] eq 'root' ? 1 : 4;
        for my $j ($start .. $#$parent) {
          my $sibling = $parent->[$j];
          next unless $sibling->[0] eq 'tag';
          next if $sibling eq $current;
          next if defined $type && $sibling->[1] ne $type;
          return if $sibling ne $current;
        }

        # No siblings
        next;
      }
    }

    return;
  }

  return 1;
}

sub _match_tree {
  my ($self, $tree, $pattern) = @_;

  # Walk tree
  my @results;
  my @queue = ($tree);
  while (my $current = shift @queue) {
    my $type = $current->[0];

    # Root
    if ($type eq 'root') {

      # Fill queue
      unshift @queue, @$current[1 .. $#$current];
      next;
    }

    # Tag
    elsif ($type eq 'tag') {

      # Fill queue
      unshift @queue, @$current[4 .. $#$current];

      # Parts
      for my $part (@$pattern) {

        # Match
        push(@results, $current) and last
          if $self->_match_element($current, $part);
      }
    }
  }

  # Upgrade results
  @results = map {
    $self->new(charset => $self->charset, tree => $_, xml => $self->xml)
  } @results;

  # Collection
  return bless \@results, 'Mojo::DOM::_Collection';
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

sub _parse_css {
  my ($self, $css) = @_;

  # Tokenize
  my $pattern = [[]];
  while ($css =~ /$CSS_TOKEN_RE/g) {
    my $separator  = $1;
    my $element    = $2;
    my $pc         = $3;
    my $attributes = $6;
    my $combinator = $11;

    # Trash
    next
      unless $separator || $element || $pc || $attributes || $combinator;

    # New selector
    push @$pattern, [] if $separator;

    # Selector
    my $part = $pattern->[-1];
    push @$part, ['element'];
    my $selector = $part->[-1];

    # Element
    $element ||= '';
    my $tag = '*';
    $element =~ s/$CSS_ELEMENT_RE// and $tag = $self->_css_unescape($1);

    # Tag
    push @$selector, ['tag', $tag];

    # Class or ID
    while ($element =~ /$CSS_CLASS_ID_RE/g) {

      # Class
      push @$selector, ['attribute', 'class', $self->_css_regex('~', $1)]
        if defined $1;

      # ID
      push @$selector, ['attribute', 'id', $self->_css_regex('', $2)]
        if defined $2;
    }

    # Pseudo classes
    while ($pc =~ /$CSS_PSEUDO_CLASS_RE/g) {

      # "not"
      if ($1 eq 'not') {
        my $subpattern = $self->_parse_css($2)->[-1]->[-1];
        push @$selector, ['pseudoclass', 'not', $subpattern];
      }

      # Everything else
      else { push @$selector, ['pseudoclass', $1, $2] }
    }

    # Attributes
    while ($attributes =~ /$CSS_ATTR_RE/g) {
      my $key   = $self->_css_unescape($1);
      my $op    = $2 || '';
      my $value = $3;
      $value = $4 unless defined $3;

      push @$selector, ['attribute', $key, $self->_css_regex($op, $value)];
    }

    # Combinator
    push @$part, ['combinator', $combinator] if $combinator;
  }

  return $pattern;
}

sub _parse_xml {
  my ($self, $xml) = @_;

  # State
  my $tree    = ['root'];
  my $current = $tree;

  # Decode
  my $charset = $self->charset;
  decode $charset, $xml if $charset && !utf8::is_utf8 $xml;
  return $tree unless $xml;

  # Tokenize
  while ($xml =~ m/\G$XML_TOKEN_RE/gcs) {
    my $text    = $1;
    my $pi      = $2;
    my $comment = $3;
    my $cdata   = $4;
    my $doctype = $5;
    my $tag     = $6;

    # Text
    if (length $text) {

      # Unescape
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

        # End
        next if $key eq '/';

        # Unescape
        html_unescape $value if $value && (index $value, '&') >= 0;

        # Merge
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

sub _pi {
  my ($self, $pi, $current) = @_;

  # Try to detect XML
  $self->xml(1) if !defined $self->xml && $pi =~ /xml/i;

  push @$$current, ['pi', $pi];
}

sub _raw {
  my ($self, $raw, $current) = @_;
  push @$$current, ['raw', $raw];
}

sub _render {
  my ($self, $tree) = @_;

  my $e = $tree->[0];

  # Text (escaped)
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

  my $content = '';

  # Start tag
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

      # Escape
      xml_escape $value;

      # Key and value
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
  for my $i ($start .. $#$tree) {

    # Render next element
    $content .= $self->_render($tree->[$i]);
  }

  # End tag
  $content .= '</' . $tree->[1] . '>' if $e eq 'tag';

  return $content;
}

# "It's not important to talk about who got rich off of whom,
#  or who got exposed to tainted what..."
sub _start {
  my ($self, $start, $attrs, $current) = @_;

  warn "START $start\n" if DEBUG;

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

  # Add leading whitespace
  $text = " $text" if $ws;

  return $text;
}

package Mojo::DOM::_Collection;
use overload 'bool' => sub {1}, fallback => 1;
use overload '""' => sub { shift->to_xml }, fallback => 1;

sub each   { shift->_iterate(@_) }
sub to_xml { join "\n", map({"$_"} @{$_[0]}) }
sub until  { shift->_iterate(@_, 1) }
sub while  { shift->_iterate(@_, 0) }

sub _iterate {
  my ($self, $cb, $cond) = @_;
  return @$self unless $cb;

  # Iterate until condition is true
  my $i = 1;
  if (defined $cond) { !!$_->$cb($i++) == $cond && last for @$self }

  # Iterate over all elements
  else { $_->$cb($i++) for @$self }

  # Root
  return unless my $start = $self->[0];
  return $start->root;
}

1;
__END__

=head1 NAME

Mojo::DOM - Minimalistic XML/HTML5 DOM Parser With CSS3 Selectors

=head1 SYNOPSIS

  use Mojo::DOM;

  # Parse
  my $dom = Mojo::DOM->new('<div><p id="a">A</p><p id="b">B</p></div>');

  # Find
  my $b = $dom->at('#b');
  print $b->text;

  # Walk
  print $dom->div->p->[0]->text;
  print $dom->div->p->[1]->{id};

  # Iterate
  $dom->find('p[id]')->each(sub { print shift->{id} });

  # Loop
  for my $e ($dom->find('p[id]')->each) {
    print $e->text;
  }

  # Modify
  $dom->div->p->[1]->append('<p id="c">C</p>');

  # Render
  print $dom;

=head1 DESCRIPTION

L<Mojo::DOM> is a minimalistic and very relaxed XML/HTML5 DOM parser with
support for CSS3 selectors.
It will even try to interpret broken XML, so you should not use it for
validation.

=head1 SELECTORS

All CSS3 selectors that make sense for a standalone parser are supported.

=head2 C<*>

Any element.

  my $first = $dom->at('*');

=head2 C<E>

An element of type C<E>.

  my $title = $dom->at('title');

=head2 C<E[foo]>

An C<E> element with a C<foo> attribute.

  my $links = $dom->find('a[href]');

=head2 C<E[foo="bar"]>

An C<E> element whose C<foo> attribute value is exactly equal to C<bar>.

  my $fields = $dom->find('input[name="foo"]');

=head2 C<E[foo~="bar"]>

An C<E> element whose C<foo> attribute value is a list of
whitespace-separated values, one of which is exactly equal to C<bar>.

  my $fields = $dom->find('input[name~="foo"]');

=head2 C<E[foo^="bar"]>

An C<E> element whose C<foo> attribute value begins exactly with the string
C<bar>.

  my $fields = $dom->find('input[name^="f"]');

=head2 C<E[foo$="bar"]>

An C<E> element whose C<foo> attribute value ends exactly with the string
C<bar>.

  my $fields = $dom->find('input[name$="o"]');

=head2 C<E[foo*="bar"]>

An C<E> element whose C<foo> attribute value contains the substring C<bar>.

  my $fields = $dom->find('input[name*="fo"]');

=head2 C<E:root>

An C<E> element, root of the document.

  my $root = $dom->at(':root');

=head2 C<E:checked>

A user interface element C<E> which is checked (for instance a radio-button
or checkbox).

  my $input = $dom->at(':checked');

=head2 C<E:empty>

An C<E> element that has no children (including text nodes).

  my $empty = $dom->find(':empty');

=head2 C<E:nth-child(n)>

An C<E> element, the C<n-th> child of its parent.

  my $third = $dom->at('div:nth-child(3)');
  my $odd   = $dom->find('div:nth-child(odd)');
  my $even  = $dom->find('div:nth-child(even)');
  my $top3  = $dom->find('div:nth-child(-n+3)');

=head2 C<E:nth-last-child(n)>

An C<E> element, the C<n-th> child of its parent, counting from the last one.

  my $third    = $dom->at('div:nth-last-child(3)');
  my $odd      = $dom->find('div:nth-last-child(odd)');
  my $even     = $dom->find('div:nth-last-child(even)');
  my $bottom3  = $dom->find('div:nth-last-child(-n+3)');

=head2 C<E:nth-of-type(n)>

An C<E> element, the C<n-th> sibling of its type.

  my $third = $dom->at('div:nth-of-type(3)');
  my $odd   = $dom->find('div:nth-of-type(odd)');
  my $even  = $dom->find('div:nth-of-type(even)');
  my $top3  = $dom->find('div:nth-of-type(-n+3)');

=head2 C<E:nth-last-of-type(n)>

An C<E> element, the C<n-th> sibling of its type, counting from the last one.

  my $third    = $dom->at('div:nth-last-of-type(3)');
  my $odd      = $dom->find('div:nth-last-of-type(odd)');
  my $even     = $dom->find('div:nth-last-of-type(even)');
  my $bottom3  = $dom->find('div:nth-last-of-type(-n+3)');

=head2 C<E:first-child>

An C<E> element, first child of its parent.

  my $first = $dom->at('div p:first-child');

=head2 C<E:last-child>

An C<E> element, last child of its parent.

  my $last = $dom->at('div p:last-child');

=head2 C<E:first-of-type>

An C<E> element, first sibling of its type.

  my $first = $dom->at('div p:first-of-type');

=head2 C<E:last-of-type>

An C<E> element, last sibling of its type.

  my $last = $dom->at('div p:last-of-type');

=head2 C<E:only-child>

An C<E> element, only child of its parent.

  my $lonely = $dom->at('div p:only-child');

=head2 C<E:only-of-type>

An C<E> element, only sibling of its type.

  my $lonely = $dom->at('div p:only-of-type');

=head2 C<E.warning>

  my $warning = $dom->at('div.warning');

An C<E> element whose class is "warning".

=head2 C<E#myid>

  my $foo = $dom->at('div#foo');

An C<E> element with C<ID> equal to "myid".

=head2 C<E:not(s)>

An C<E> element that does not match simple selector C<s>.

  my $others = $dom->at('div p:not(:first-child)');

=head2 C<E F>

An C<F> element descendant of an C<E> element.

  my $headlines = $dom->find('div h1');

=head2 C<E E<gt> F>

An C<F> element child of an C<E> element.

  my $headlines = $dom->find('html > body > div > h1');

=head2 C<E + F>

An C<F> element immediately preceded by an C<E> element.

  my $second = $dom->find('h1 + h2');

=head2 C<E ~ F>

An C<F> element preceded by an C<E> element.

  my $second = $dom->find('h1 ~ h2');

=head2 C<E, F, G>

Elements of type C<E>, C<F> and C<G>.

  my $headlines = $dom->find('h1, h2, h3');

=head2 C<E[foo=bar][bar=baz]>

An C<E> element whose attributes match all following attribute selectors.

  my $links = $dom->find('a[foo^="b"][foo$="ar"]');

=head1 METHODS

L<Mojo::DOM> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $dom = Mojo::DOM->new;
  my $dom = Mojo::DOM->new(xml => 1);
  my $dom = Mojo::DOM->new('<foo bar="baz">test</foo>');
  my $dom = Mojo::DOM->new('<foo bar="baz">test</foo>', xml => 1);

Construct a new L<Mojo::DOM> object.

=head2 C<all_text>

  my $text = $dom->all_text;

Extract all text content from DOM structure.

=head2 C<append>

  $dom = $dom->append('<p>Hi!</p>');

Append to element.

  # "<div><h1>A</h1><h2>B</h2></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->append('<h2>B</h2>');

=head2 C<append_inner>

  $dom = $dom->append_inner('<p>Hi!</p>');

Append to element content.

  # "<div><h1>AB</h1></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->append_inner('B');

=head2 C<at>

  my $result = $dom->at('html title');

Find a single element with CSS3 selectors.

=head2 C<attrs>

  my $attrs = $dom->attrs;
  my $foo   = $dom->attrs('foo');
  $dom      = $dom->attrs({foo => 'bar'});
  $dom      = $dom->attrs(foo => 'bar');

Element attributes.

  # Direct hash access to attributes is also available
  print $dom->{foo};
  print $dom->div->{id};

=head2 C<charset>

  my $charset = $dom->charset;
  $dom        = $dom->charset('UTF-8');

Charset used for decoding and encoding XML.

=head2 C<children>

  my $collection = $dom->children;
  my $collection = $dom->children('div')

Return a collection containing the children of this element, similar to
C<find>.

  # Child elements are also automatically available as object methods
  print $dom->div->text;
  print $dom->div->[23]->text;
  $dom->div->each(sub { print $_->text });

=head2 C<find>

  my $collection = $dom->find('html title');

Find elements with CSS3 selectors and return a collection.

  print $dom->find('div')->[23]->text;

Collections are blessed arrays supporting these methods.

=over 2

=item C<each>

  my @elements = $dom->find('div')->each;
  $dom         = $dom->find('div')->each(sub { print shift->text });
  $dom         = $dom->find('div')->each(sub {
    my ($e, $count) = @_;
    print "$count: ", $e->text;
  });

Iterate over whole collection.

=item C<to_xml>

  my $xml = $dom->find('div')->to_xml;

Render collection to XML.
Note that this method is EXPERIMENTAL and might change without warning!

=item C<until>

  $dom = $dom->find('div')->until(sub { $_->text =~ /x/ && print $_->text });
  $dom = $dom->find('div')->until(sub {
    my ($e, $count) = @_;
    $e->text =~ /x/ && print "$count: ", $e->text;
  });

Iterate over collection until closure returns true.

=item C<while>

  $dom = $dom->find('div')->while(sub {
    print($_->text) && $_->text =~ /x/
  });
  $dom = $dom->find('div')->while(sub {
    my ($e, $count) = @_;
    print("$count: ", $e->text) && $e->text =~ /x/;
  });

Iterate over collection while closure returns true.

=back

=head2 C<inner_xml>

  my $xml = $dom->inner_xml;

Render content of this element to XML.

=head2 C<namespace>

  my $namespace = $dom->namespace;

Find element namespace.

=head2 C<parent>

  my $parent = $dom->parent;

Parent of element.

=head2 C<parse>

  $dom = $dom->parse('<foo bar="baz">test</foo>');

Parse XML document.

=head2 C<prepend>

  $dom = $dom->prepend('<p>Hi!</p>');

Prepend to element.

  # "<div><h1>A</h1><h2>B</h2></div>"
  $dom->parse('<div><h2>B</h2></div>')->at('h2')->prepend('<h1>A</h1>');

=head2 C<prepend_inner>

  $dom = $dom->prepend_inner('<p>Hi!</p>');

Prepend to element content.

  # "<div><h2>AB</h2></div>"
  $dom->parse('<div><h2>B</h2></div>')->at('h2')->prepend_inner('A');

=head2 C<replace>

  $dom = $dom->replace('<div>test</div>');

Replace elements.

  # "<div><h2>B</h2></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->replace('<h2>B</h2>');

=head2 C<replace_inner>

  $dom = $dom->replace_inner('test');

Replace element content.

  # "<div><h1>B</h1></div>"
  $dom->parse('<div><h1>A</h1></div>')->at('h1')->replace_inner('B');

=head2 C<root>

  my $root = $dom->root;

Find root element.

=head2 C<text>

  my $text = $dom->text;

Extract text content from element only, not including child elements.

=head2 C<to_xml>

  my $xml = $dom->to_xml;

Render DOM to XML.

=head2 C<tree>

  my $tree = $dom->tree;
  $dom     = $dom->tree(['root', ['text', 'lalala']]);

Document Object Model.

=head2 C<type>

  my $type = $dom->type;
  $dom     = $dom->type('html');

Element type.

=head2 C<xml>

  my $xml = $dom->xml;
  $dom    = $dom->xml(1);

Disable HTML5 semantics in parser and activate case sensitivity, defaults to
auto detection based on processing instructions.
Note that this method is EXPERIMENTAL and might change without warning!

=head1 DEBUGGING

You can set the C<MOJO_DOM_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_DOM_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
