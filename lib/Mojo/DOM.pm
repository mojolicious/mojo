package Mojo::DOM;
use Mojo::Base 'Mojo::HTML';

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

sub at { shift->find(@_)->[0] }

sub children { bless shift->SUPER::children(@_), 'Mojo::DOM::_Collection' }

# "How are the kids supposed to get home?
#  I dunno. Internet?"
sub find {
  my ($self, $css) = @_;
  $self->_match_tree($self->tree, $self->_parse_css($css));
}

# DEPRECATED in Smiling Face With Sunglasses!
sub inner_xml {
  warn <<EOF;
Mojo::DOM->inner_xml is DEPRECATED in favor of Mojo::DOM->content_xml!!!
EOF
  shift->content_xml(@_);
}

# DEPRECATED in Smiling Face With Sunglasses!
sub replace_inner {
  warn <<EOF;
Mojo::DOM->replace_inner is DEPRECATED in favor of
Mojo::DOM->replace_content!!!
EOF
  shift->content_xml(@_);
}

sub _css_equation {
  my ($self, $equation) = @_;

  # "even"
  my $num = [1, 1];
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

  # "~=" (word)
  my $regex;
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

sub _match_element {
  my ($self, $candidate, $selectors) = @_;

  # Match
  my @selectors  = reverse @$selectors;
  my $first      = 2;
  my $parentonly = 0;
  my $tree       = $self->tree;
  my ($current, $marker, $snapback, $siblings);
  for (my $i = 0; $i <= $#selectors; $i++) {
    my $selector = $selectors[$i];

    # Combinator
    $parentonly-- if $parentonly > 0;
    if ($selector->[0] eq 'combinator') {
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

        # Siblings
        my $parent = $current->[3];
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

        # Siblings
        my $parent = $current->[3];
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
        push(@results, $current) and last
          if $self->_match_element($current, $part);
      }
    }
  }

  # Upgrade results
  @results = map {
    $self->new(charset => $self->charset, tree => $_, xml => $self->xml)
  } @results;

  return bless \@results, 'Mojo::DOM::_Collection';
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

# "Hi, Super Nintendo Chalmers!"
package Mojo::DOM::_Collection;
use overload 'bool' => sub {1}, '""' => sub { shift->to_xml }, fallback => 1;

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

=head1 CASE SENSITIVITY

L<Mojo::DOM> defaults to HTML5 semantics, that means all tags and attributes
are lowercased and selectors need to be lowercase as well.

  my $dom = Mojo::DOM->new('<P ID="greeting">Hi!</P>');
  print $dom->at('p')->text;
  print $dom->p->{id};

If XML processing instructions are found, the parser will automatically
switch into XML mode and everything becomes case sensitive.

  my $dom = Mojo::DOM->new('<?xml version="1.0"?><P ID="greeting">Hi!</P>');
  print $dom->at('P')->text;
  print $dom->P->{ID};

XML detection can be also deactivated with the C<xml> method.

  # XML sematics
  $dom->xml(1);

  # HTML5 semantics
  $dom->xml(0);

=head1 METHODS

L<Mojo::DOM> inherits all methods from L<Mojo::HTML> and implements the
following new ones.

=head2 C<at>

  my $result = $dom->at('html title');

Find a single element with CSS3 selectors.

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

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
