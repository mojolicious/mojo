package Mojo::DOM::CSS;
use Mojo::Base -base;

has 'tree';

my $ESCAPE_RE = qr/\\[^[:xdigit:]]|\\[[:xdigit:]]{1,6}/;
my $ATTR_RE   = qr/
  \[
  ((?:$ESCAPE_RE|[\w\-])+)        # Key
  (?:
    (\W)?                         # Operator
    =
    (?:"((?:\\"|[^"])+)"|(\S+))   # Value
  )?
  \]
/x;
my $CLASS_ID_RE = qr/
  (?:
    (?:\.((?:\\\.|[^\#.])+))   # Class
  |
    (?:\#((?:\\\#|[^.\#])+))   # ID
  )
/x;
my $PSEUDO_CLASS_RE = qr/(?::([\w\-]+)(?:\(((?:\([^)]+\)|[^)])+)\))?)/;
my $TOKEN_RE        = qr/
  (\s*,\s*)?                         # Separator
  ((?:[^[\\:\s,]|$ESCAPE_RE\s?)+)?   # Element
  ($PSEUDO_CLASS_RE*)?               # Pseudoclass
  ((?:$ATTR_RE)*)?                   # Attributes
  (?:
    \s*
    ([>+~])                          # Combinator
  )?
/x;

sub select {
  my $self = shift;

  my @results;
  my $pattern = $self->_compile(shift);
  my $tree    = $self->tree;
  my @queue   = ($tree);
  while (my $current = shift @queue) {
    my $type = $current->[0];

    # Root
    if ($type eq 'root') { unshift @queue, @$current[1 .. $#$current] }

    # Tag
    elsif ($type eq 'tag') {
      unshift @queue, @$current[4 .. $#$current];

      # Try all selectors with element
      for my $part (@$pattern) {
        push @results, $current and last
          if $self->_combinator([reverse @$part], $current, $tree);
      }
    }
  }

  return \@results;
}

sub _ancestor {
  my ($self, $selectors, $current, $tree) = @_;
  while ($current = $current->[3]) {
    return undef if $current->[0] eq 'root' || $current eq $tree;
    return 1 if $self->_combinator($selectors, $current, $tree);
  }
  return undef;
}

sub _attr {
  my ($self, $key, $regex, $current) = @_;

  # Ignore namespace prefix
  my $attrs = $current->[2];
  for my $name (keys %$attrs) {
    next unless $name =~ /(?:^|:)$key$/;
    return 1 unless defined $attrs->{$name} && defined $regex;
    return 1 if $attrs->{$name} =~ $regex;
  }

  return undef;
}

sub _combinator {
  my ($self, $selectors, $current, $tree) = @_;

  # Selector
  my @s = @$selectors;
  return undef unless my $combinator = shift @s;
  if ($combinator->[0] ne 'combinator') {
    return undef unless $self->_selector($combinator, $current);
    return 1 unless $combinator = shift @s;
  }

  # " " (ancestor)
  my $c = $combinator->[1];
  if ($c eq ' ') { return undef unless $self->_ancestor(\@s, $current, $tree) }

  # ">" (parent only)
  elsif ($c eq '>') {
    return undef unless $self->_parent(\@s, $current, $tree);
  }

  # "~" (preceding siblings)
  elsif ($c eq '~') {
    return undef unless $self->_sibling(\@s, $current, $tree, 0);
  }

  # "+" (immediately preceding siblings)
  elsif ($c eq '+') {
    return undef unless $self->_sibling(\@s, $current, $tree, 1);
  }

  return 1;
}

sub _compile {
  my ($self, $css) = @_;

  my $pattern = [[]];
  while ($css =~ /$TOKEN_RE/g) {
    my ($separator, $element, $pc, $attrs, $combinator)
      = ($1, $2 // '', $3, $6, $11);

    # Trash
    next unless $separator || $element || $pc || $attrs || $combinator;

    # New selector
    push @$pattern, [] if $separator;
    my $part = $pattern->[-1];

    # Empty combinator
    push @$part, [combinator => ' ']
      if $part->[-1] && $part->[-1][0] ne 'combinator';

    # Selector
    push @$part, ['element'];
    my $selector = $part->[-1];

    # Element
    my $tag = '*';
    $element =~ s/^((?:\\\.|\\\#|[^.#])+)// and $tag = $self->_unescape($1);

    # Tag
    push @$selector, ['tag', $tag];

    # Class or ID
    while ($element =~ /$CLASS_ID_RE/g) {

      # Class
      push @$selector, ['attr', 'class', $self->_regex('~', $1)] if defined $1;

      # ID
      push @$selector, ['attr', 'id', $self->_regex('', $2)] if defined $2;
    }

    # Pseudo classes
    while ($pc =~ /$PSEUDO_CLASS_RE/g) {

      # "not"
      if ($1 eq 'not') {
        my $subpattern = $self->_compile($2)->[-1][-1];
        push @$selector, ['pc', 'not', $subpattern];
      }

      # Everything else
      else { push @$selector, ['pc', $1, $2] }
    }

    # Attributes
    while ($attrs =~ /$ATTR_RE/g) {
      my ($key, $op, $value) = ($self->_unescape($1), $2 // '', $3 // $4);
      push @$selector, ['attr', $key, $self->_regex($op, $value)];
    }

    # Combinator
    push @$part, [combinator => $combinator] if $combinator;
  }

  return $pattern;
}

sub _equation {
  my ($self, $equation) = @_;

  # "even"
  my $num = [1, 1];
  if ($equation =~ /^even$/i) { $num = [2, 2] }

  # "odd"
  elsif ($equation =~ /^odd$/i) { $num = [2, 1] }

  # Equation
  elsif ($equation =~ /(?:(-?(?:\d+)?)?(n))?\s*\+?\s*(-?\s*\d+)?\s*$/i) {
    $num->[0] = defined($1) && length($1) ? $1 : $2 ? 1 : 0;
    $num->[0] = -1 if $num->[0] eq '-';
    $num->[1] = $3 // 0;
    $num->[1] =~ s/\s+//g;
  }

  return $num;
}

sub _parent {
  my ($self, $selectors, $current, $tree) = @_;
  return undef unless my $parent = $current->[3];
  return undef if $parent->[0] eq 'root';
  return $self->_combinator($selectors, $parent, $tree) ? 1 : undef;
}

sub _pc {
  my ($self, $class, $args, $current) = @_;

  # ":first-*"
  if ($class =~ /^first-(?:(child)|of-type)$/) {
    $class = defined $1 ? 'nth-child' : 'nth-of-type';
    $args = 1;
  }

  # ":last-*"
  elsif ($class =~ /^last-(?:(child)|of-type)$/) {
    $class = defined $1 ? 'nth-last-child' : 'nth-last-of-type';
    $args = '-n+1';
  }

  # ":checked"
  if ($class eq 'checked') {
    my $attrs = $current->[2];
    return 1 if exists $attrs->{checked} || exists $attrs->{selected};
  }

  # ":empty"
  elsif ($class eq 'empty') { return 1 unless defined $current->[4] }

  # ":root"
  elsif ($class eq 'root') {
    if (my $parent = $current->[3]) { return 1 if $parent->[0] eq 'root' }
  }

  # ":not"
  elsif ($class eq 'not') { return 1 if !$self->_selector($args, $current) }

  # ":nth-*"
  elsif ($class =~ /^nth-/) {

    # Numbers
    $args = $self->_equation($args) unless ref $args;

    # Siblings
    my $parent = $current->[3];
    my $start = $parent->[0] eq 'root' ? 1 : 4;
    my @siblings;
    my $type = $class =~ /of-type$/ ? $current->[1] : undef;
    for my $i ($start .. $#$parent) {
      my $sibling = $parent->[$i];
      next unless $sibling->[0] eq 'tag';
      next if defined $type && $type ne $sibling->[1];
      push @siblings, $sibling;
    }

    # Reverse
    @siblings = reverse @siblings if $class =~ /^nth-last/;

    # Find
    for my $i (0 .. $#siblings) {
      my $result = $args->[0] * $i + $args->[1];
      next if $result < 1;
      last unless my $sibling = $siblings[$result - 1];
      return 1 if $sibling eq $current;
    }
  }

  # ":only-*"
  elsif ($class =~ /^only-(?:child|(of-type))$/) {
    my $type = $1 ? $current->[1] : undef;

    # Siblings
    my $parent = $current->[3];
    my $start = $parent->[0] eq 'root' ? 1 : 4;
    for my $i ($start .. $#$parent) {
      my $sibling = $parent->[$i];
      next if $sibling->[0] ne 'tag' || $sibling eq $current;
      return undef unless defined $type && $sibling->[1] ne $type;
    }

    # No siblings
    return 1;
  }

  return undef;
}

sub _regex {
  my ($self, $op, $value) = @_;
  return undef unless defined $value;
  $value = quotemeta $self->_unescape($value);

  # "~=" (word)
  return qr/(?:^|.*\s+)$value(?:\s+.*|$)/ if $op eq '~';

  # "*=" (contains)
  return qr/$value/ if $op eq '*';

  # "^=" (begins with)
  return qr/^$value/ if $op eq '^';

  # "$=" (ends with)
  return qr/$value$/ if $op eq '$';

  # Everything else
  return qr/^$value$/;
}

sub _selector {
  my ($self, $selector, $current) = @_;

  for my $s (@$selector[1 .. $#$selector]) {
    my $type = $s->[0];

    # Tag (ignore namespace prefix)
    if ($type eq 'tag') {
      my $tag = $s->[1];
      return undef unless $tag eq '*' || $current->[1] =~ /(?:^|:)$tag$/;
    }

    # Attribute
    elsif ($type eq 'attr') {
      return undef unless $self->_attr(@$s[1, 2], $current);
    }

    # Pseudo class
    elsif ($type eq 'pc') {
      return undef unless $self->_pc(lc $s->[1], $s->[2], $current);
    }
  }

  return 1;
}

sub _sibling {
  my ($self, $selectors, $current, $tree, $immediate) = @_;

  my $parent = $current->[3];
  my $found;
  my $start = $parent->[0] eq 'root' ? 1 : 4;
  for my $e (@$parent[$start .. $#$parent]) {
    return $found if $e eq $current;
    next unless $e->[0] eq 'tag';

    # "+" (immediately preceding sibling)
    if ($immediate) { $found = $self->_combinator($selectors, $e, $tree) }

    # "~" (preceding sibling)
    else { return 1 if $self->_combinator($selectors, $e, $tree) }
  }

  return undef;
}

sub _unescape {
  my ($self, $value) = @_;

  # Remove escaped newlines
  $value =~ s/\\\n//g;

  # Unescape Unicode characters
  $value =~ s/\\([[:xdigit:]]{1,6})\s?/pack('U', hex $1)/ge;

  # Remove backslash
  $value =~ s/\\//g;

  return $value;
}

1;

=head1 NAME

Mojo::DOM::CSS - CSS selector engine

=head1 SYNOPSIS

  use Mojo::DOM::CSS;

  # Select elements from DOM tree
  my $css = Mojo::DOM::CSS->new(tree => $tree);
  my $elements = $css->select('h1, h2, h3');

=head1 DESCRIPTION

L<Mojo::DOM::CSS> is the CSS selector engine used by L<Mojo::DOM>.

=head1 SELECTORS

All CSS selectors that make sense for a standalone parser are supported.

=head2 *

Any element.

  my $all = $css->select('*');

=head2 E

An element of type C<E>.

  my $title = $css->select('title');

=head2 E[foo]

An C<E> element with a C<foo> attribute.

  my $links = $css->select('a[href]');

=head2 E[foo="bar"]

An C<E> element whose C<foo> attribute value is exactly equal to C<bar>.

  my $fields = $css->select('input[name="foo"]');

=head2 E[foo~="bar"]

An C<E> element whose C<foo> attribute value is a list of
whitespace-separated values, one of which is exactly equal to C<bar>.

  my $fields = $css->select('input[name~="foo"]');

=head2 E[foo^="bar"]

An C<E> element whose C<foo> attribute value begins exactly with the string
C<bar>.

  my $fields = $css->select('input[name^="f"]');

=head2 E[foo$="bar"]

An C<E> element whose C<foo> attribute value ends exactly with the string
C<bar>.

  my $fields = $css->select('input[name$="o"]');

=head2 E[foo*="bar"]

An C<E> element whose C<foo> attribute value contains the substring C<bar>.

  my $fields = $css->select('input[name*="fo"]');

=head2 E:root

An C<E> element, root of the document.

  my $root = $css->select(':root');

=head2 E:checked

A user interface element C<E> which is checked (for instance a radio-button or
checkbox).

  my $input = $css->select(':checked');

=head2 E:empty

An C<E> element that has no children (including text nodes).

  my $empty = $css->select(':empty');

=head2 E:nth-child(n)

An C<E> element, the C<n-th> child of its parent.

  my $third = $css->select('div:nth-child(3)');
  my $odd   = $css->select('div:nth-child(odd)');
  my $even  = $css->select('div:nth-child(even)');
  my $top3  = $css->select('div:nth-child(-n+3)');

=head2 E:nth-last-child(n)

An C<E> element, the C<n-th> child of its parent, counting from the last one.

  my $third    = $css->select('div:nth-last-child(3)');
  my $odd      = $css->select('div:nth-last-child(odd)');
  my $even     = $css->select('div:nth-last-child(even)');
  my $bottom3  = $css->select('div:nth-last-child(-n+3)');

=head2 E:nth-of-type(n)

An C<E> element, the C<n-th> sibling of its type.

  my $third = $css->select('div:nth-of-type(3)');
  my $odd   = $css->select('div:nth-of-type(odd)');
  my $even  = $css->select('div:nth-of-type(even)');
  my $top3  = $css->select('div:nth-of-type(-n+3)');

=head2 E:nth-last-of-type(n)

An C<E> element, the C<n-th> sibling of its type, counting from the last one.

  my $third    = $css->select('div:nth-last-of-type(3)');
  my $odd      = $css->select('div:nth-last-of-type(odd)');
  my $even     = $css->select('div:nth-last-of-type(even)');
  my $bottom3  = $css->select('div:nth-last-of-type(-n+3)');

=head2 E:first-child

An C<E> element, first child of its parent.

  my $first = $css->select('div p:first-child');

=head2 E:last-child

An C<E> element, last child of its parent.

  my $last = $css->select('div p:last-child');

=head2 E:first-of-type

An C<E> element, first sibling of its type.

  my $first = $css->select('div p:first-of-type');

=head2 E:last-of-type

An C<E> element, last sibling of its type.

  my $last = $css->select('div p:last-of-type');

=head2 E:only-child

An C<E> element, only child of its parent.

  my $lonely = $css->select('div p:only-child');

=head2 E:only-of-type

An C<E> element, only sibling of its type.

  my $lonely = $css->select('div p:only-of-type');

=head2 E.warning

  my $warning = $css->select('div.warning');

An C<E> element whose class is "warning".

=head2 E#myid

  my $foo = $css->select('div#foo');

An C<E> element with C<ID> equal to "myid".

=head2 E:not(s)

An C<E> element that does not match simple selector C<s>.

  my $others = $css->select('div p:not(:first-child)');

=head2 E F

An C<F> element descendant of an C<E> element.

  my $headlines = $css->select('div h1');

=head2 E E<gt> F

An C<F> element child of an C<E> element.

  my $headlines = $css->select('html > body > div > h1');

=head2 E + F

An C<F> element immediately preceded by an C<E> element.

  my $second = $css->select('h1 + h2');

=head2 E ~ F

An C<F> element preceded by an C<E> element.

  my $second = $css->select('h1 ~ h2');

=head2 E, F, G

Elements of type C<E>, C<F> and C<G>.

  my $headlines = $css->select('h1, h2, h3');

=head2 E[foo=bar][bar=baz]

An C<E> element whose attributes match all following attribute selectors.

  my $links = $css->select('a[foo^="b"][foo$="ar"]');

=head1 ATTRIBUTES

L<Mojo::DOM::CSS> implements the following attributes.

=head2 tree

  my $tree = $css->tree;
  $css     = $css->tree(['root', ['text', 'foo']]);

Document Object Model. Note that this structure should only be used very
carefully since it is very dynamic.

=head1 METHODS

L<Mojo::DOM::CSS> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 select

  my $results = $css->select('head > title');

Run CSS selector against C<tree>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
