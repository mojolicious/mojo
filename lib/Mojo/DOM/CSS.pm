package Mojo::DOM::CSS;
use Mojo::Base -base;

has 'tree';

my $ESCAPE_RE = qr/\\[^0-9a-fA-F]|\\[0-9a-fA-F]{1,6}/;
my $ATTR_RE   = qr/
  \[
  ((?:$ESCAPE_RE|[\w\-])+)           # Key
  (?:
    (\W)?=                           # Operator
    (?:"((?:\\"|[^"])*)"|([^\]]+?))  # Value
    (?:\s+(i))?                      # Case-sensitivity
  )?
  \]
/x;
my $PSEUDO_CLASS_RE = qr/(?::([\w\-]+)(?:\(((?:\([^)]+\)|[^)])+)\))?)/;
my $TOKEN_RE        = qr/
  (\s*,\s*)?                            # Separator
  ((?:[^[\\:\s,>+~]|$ESCAPE_RE\s?)+)?   # Element
  ($PSEUDO_CLASS_RE*)?                  # Pseudoclass
  ((?:$ATTR_RE)*)?                      # Attributes
  (?:\s*([>+~]))?                       # Combinator
/x;

sub match {
  my $tree = shift->tree;
  return $tree->[0] ne 'tag' ? undef : _match(_compile(shift), $tree, $tree);
}

sub select     { _select(0, shift->tree, _compile(@_)) }
sub select_one { _select(1, shift->tree, _compile(@_)) }

sub _ancestor {
  my ($selectors, $current, $tree, $pos) = @_;
  while ($current = $current->[3]) {
    return undef if $current->[0] eq 'root' || $current eq $tree;
    return 1 if _combinator($selectors, $current, $tree, $pos);
  }
  return undef;
}

sub _attr {
  my ($name_re, $value_re, $current) = @_;

  my $attrs = $current->[2];
  for my $name (keys %$attrs) {
    next unless $name =~ $name_re;
    return 1 unless defined $attrs->{$name} && defined $value_re;
    return 1 if $attrs->{$name} =~ $value_re;
  }

  return undef;
}

sub _combinator {
  my ($selectors, $current, $tree, $pos) = @_;

  # Selector
  return undef unless my $c = $selectors->[$pos];
  if (ref $c) {
    return undef unless _selector($c, $current);
    return 1 unless $c = $selectors->[++$pos];
  }

  # ">" (parent only)
  return _parent($selectors, $current, $tree, ++$pos) if $c eq '>';

  # "~" (preceding siblings)
  return _sibling($selectors, $current, $tree, 0, ++$pos) if $c eq '~';

  # "+" (immediately preceding siblings)
  return _sibling($selectors, $current, $tree, 1, ++$pos) if $c eq '+';

  # " " (ancestor)
  return _ancestor($selectors, $current, $tree, ++$pos);
}

sub _compile {
  my $css = "$_[0]";

  my $pattern = [[]];
  while ($css =~ /$TOKEN_RE/go) {
    my ($separator, $element, $pc, $attrs, $combinator)
      = ($1, $2 // '', $3, $6, $12);

    next unless $separator || $element || $pc || $attrs || $combinator;

    # New selector
    push @$pattern, [] if $separator;
    my $part = $pattern->[-1];

    # Empty combinator
    push @$part, ' ' if $part->[-1] && ref $part->[-1];

    # Tag
    push @$part, my $selector = [];
    push @$selector, ['tag', _name($1)]
      if $element =~ s/^((?:\\\.|\\\#|[^.#])+)// && $1 ne '*';

    # Class or ID
    while ($element =~ /(?:([.#])((?:\\[.\#]|[^\#.])+))/g) {
      my ($name, $op) = $1 eq '.' ? ('class', '~') : ('id', '');
      push @$selector, ['attr', _name($name), _value($op, $2)];
    }

    # Pseudo classes (":not" contains more selectors)
    push @$selector, ['pc', lc $1, $1 eq 'not' ? _compile($2) : _equation($2)]
      while $pc =~ /$PSEUDO_CLASS_RE/go;

    # Attributes
    push @$selector, ['attr', _name($1), _value($2 // '', $3 // $4, $5)]
      while $attrs =~ /$ATTR_RE/go;

    # Combinator
    push @$part, $combinator if $combinator;
  }

  return $pattern;
}

sub _empty { $_[0][0] eq 'comment' || $_[0][0] eq 'pi' }

sub _equation {
  return [] unless my $equation = shift;

  # "even"
  return [2, 2] if $equation =~ /^\s*even\s*$/i;

  # "odd"
  return [2, 1] if $equation =~ /^\s*odd\s*$/i;

  # Equation
  my $num = [1, 1];
  return $num if $equation !~ /(?:(-?(?:\d+)?)?(n))?\s*\+?\s*(-?\s*\d+)?\s*$/i;
  $num->[0] = defined($1) && length($1) ? $1 : $2 ? 1 : 0;
  $num->[0] = -1 if $num->[0] eq '-';
  $num->[1] = $3 // 0;
  $num->[1] =~ s/\s+//g;
  return $num;
}

sub _match {
  my ($pattern, $current, $tree) = @_;
  _combinator([reverse @$_], $current, $tree, 0) and return 1 for @$pattern;
  return undef;
}

sub _name {qr/(?:^|:)\Q@{[_unescape(shift)]}\E$/}

sub _parent {
  my ($selectors, $current, $tree, $pos) = @_;
  return undef unless my $parent = $current->[3];
  return undef if $parent->[0] eq 'root' || $parent eq $tree;
  return _combinator($selectors, $parent, $tree, $pos);
}

sub _pc {
  my ($class, $args, $current) = @_;

  # ":empty"
  return !grep { !_empty($_) } @$current[4 .. $#$current] if $class eq 'empty';

  # ":root"
  return $current->[3] && $current->[3][0] eq 'root' if $class eq 'root';

  # ":not"
  return !_match($args, $current, $current) if $class eq 'not';

  # ":checked"
  return exists $current->[2]{checked} || exists $current->[2]{selected}
    if $class eq 'checked';

  # ":first-*" or ":last-*" (rewrite with equation)
  ($class, $args) = $1 ? ("nth-$class", [0, 1]) : ("nth-last-$class", [-1, 1])
    if $class =~ s/^(?:(first)|last)-//;

  # ":nth-*"
  if ($class =~ /^nth-/) {
    my $type = $class =~ /of-type$/ ? $current->[1] : undef;
    my @siblings = @{_siblings($current, $type)};

    # ":nth-last-*"
    @siblings = reverse @siblings if $class =~ /^nth-last/;

    for my $i (0 .. $#siblings) {
      next if (my $result = $args->[0] * $i + $args->[1]) < 1;
      last unless my $sibling = $siblings[$result - 1];
      return 1 if $sibling eq $current;
    }
  }

  # ":only-*"
  elsif ($class =~ /^only-(?:child|(of-type))$/) {
    $_ ne $current and return undef
      for @{_siblings($current, $1 ? $current->[1] : undef)};
    return 1;
  }

  return undef;
}

sub _select {
  my ($one, $tree, $pattern) = @_;

  my @results;
  my @queue = @$tree[($tree->[0] eq 'root' ? 1 : 4) .. $#$tree];
  while (my $current = shift @queue) {
    next unless $current->[0] eq 'tag';

    unshift @queue, @$current[4 .. $#$current];
    next unless _match($pattern, $current, $tree);
    $one ? return $current : push @results, $current;
  }

  return $one ? undef : \@results;
}

sub _selector {
  my ($selector, $current) = @_;

  for my $s (@$selector) {
    my $type = $s->[0];

    # Tag
    if ($type eq 'tag') { return undef unless $current->[1] =~ $s->[1] }

    # Attribute
    elsif ($type eq 'attr') { return undef unless _attr(@$s[1, 2], $current) }

    # Pseudo class
    elsif ($type eq 'pc') { return undef unless _pc(@$s[1, 2], $current) }
  }

  return 1;
}

sub _sibling {
  my ($selectors, $current, $tree, $immediate, $pos) = @_;

  my $found;
  for my $sibling (@{_siblings($current)}) {
    return $found if $sibling eq $current;

    # "+" (immediately preceding sibling)
    if ($immediate) { $found = _combinator($selectors, $sibling, $tree, $pos) }

    # "~" (preceding sibling)
    else { return 1 if _combinator($selectors, $sibling, $tree, $pos) }
  }

  return undef;
}

sub _siblings {
  my ($current, $type) = @_;

  my $parent = $current->[3];
  my @siblings = grep { $_->[0] eq 'tag' }
    @$parent[($parent->[0] eq 'root' ? 1 : 4) .. $#$parent];
  @siblings = grep { $type eq $_->[1] } @siblings if defined $type;

  return \@siblings;
}

sub _unescape {
  my $value = shift;

  # Remove escaped newlines
  $value =~ s/\\\n//g;

  # Unescape Unicode characters
  $value =~ s/\\([0-9a-fA-F]{1,6})\s?/pack 'U', hex $1/ge;

  # Remove backslash
  $value =~ s/\\//g;

  return $value;
}

sub _value {
  my ($op, $value, $insensitive) = @_;
  return undef unless defined $value;
  $value = ($insensitive ? '(?i)' : '') . quotemeta _unescape($value);

  # "~=" (word)
  return qr/(?:^|\s+)$value(?:\s+|$)/ if $op eq '~';

  # "*=" (contains)
  return qr/$value/ if $op eq '*';

  # "^=" (begins with)
  return qr/^$value/ if $op eq '^';

  # "$=" (ends with)
  return qr/$value$/ if $op eq '$';

  # Everything else
  return qr/^$value$/;
}

1;

=encoding utf8

=head1 NAME

Mojo::DOM::CSS - CSS selector engine

=head1 SYNOPSIS

  use Mojo::DOM::CSS;

  # Select elements from DOM tree
  my $css = Mojo::DOM::CSS->new(tree => $tree);
  my $elements = $css->select('h1, h2, h3');

=head1 DESCRIPTION

L<Mojo::DOM::CSS> is the CSS selector engine used by L<Mojo::DOM> and based on
L<Selectors Level 3|http://www.w3.org/TR/css3-selectors/>.

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

  my $case_sensitive = $css->select('input[type="hidden"]');
  my $case_sensitive = $css->select('input[type=hidden]');

=head2 E[foo="bar" i]

An C<E> element whose C<foo> attribute value is exactly equal to any
(ASCII-range) case-permutation of C<bar>. Note that this selector is
EXPERIMENTAL and might change without warning!

  my $case_insensitive = $css->select('input[type="hidden" i]');
  my $case_insensitive = $css->select('input[type=hidden i]');
  my $case_insensitive = $css->select('input[class~="foo" i]');

This selector is part of
L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a
work in progress.

=head2 E[foo~="bar"]

An C<E> element whose C<foo> attribute value is a list of
whitespace-separated values, one of which is exactly equal to C<bar>.

  my $foo = $css->select('input[class~="foo"]');
  my $foo = $css->select('input[class~=foo]');

=head2 E[foo^="bar"]

An C<E> element whose C<foo> attribute value begins exactly with the string
C<bar>.

  my $begins_with = $css->select('input[name^="f"]');
  my $begins_with = $css->select('input[name^=f]');

=head2 E[foo$="bar"]

An C<E> element whose C<foo> attribute value ends exactly with the string
C<bar>.

  my $ends_with = $css->select('input[name$="o"]');
  my $ends_with = $css->select('input[name$=o]');

=head2 E[foo*="bar"]

An C<E> element whose C<foo> attribute value contains the substring C<bar>.

  my $contains = $css->select('input[name*="fo"]');
  my $contains = $css->select('input[name*=fo]');

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

An C<E> element whose class is "warning".

  my $warning = $css->select('div.warning');

=head2 E#myid

An C<E> element with C<ID> equal to "myid".

  my $foo = $css->select('div#foo');

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

  my $links = $css->select('a[foo^=b][foo$=ar]');

=head1 ATTRIBUTES

L<Mojo::DOM::CSS> implements the following attributes.

=head2 tree

  my $tree = $css->tree;
  $css     = $css->tree(['root']);

Document Object Model. Note that this structure should only be used very
carefully since it is very dynamic.

=head1 METHODS

L<Mojo::DOM::CSS> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 match

  my $bool = $css->match('head > title');

Match CSS selector against first node in L</"tree">.

=head2 select

  my $results = $css->select('head > title');

Run CSS selector against L</"tree">.

=head2 select_one

  my $result = $css->select_one('head > title');

Run CSS selector against L</"tree"> and stop as soon as the first node
matched.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
