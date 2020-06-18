package Mojo::DOM::CSS;
use Mojo::Base -base;

use Mojo::Util qw(dumper trim);

use constant DEBUG => $ENV{MOJO_DOM_CSS_DEBUG} || 0;

has 'tree';

my $ESCAPE_RE = qr/\\[^0-9a-fA-F]|\\[0-9a-fA-F]{1,6}/;
my $ATTR_RE   = qr/
  \[
  ((?:$ESCAPE_RE|[\w\-])+)                              # Key
  (?:
    (\W)?=                                              # Operator
    (?:"((?:\\"|[^"])*)"|'((?:\\'|[^'])*)'|([^\]]+?))   # Value
    (?:\s+(?:(i|I)|s|S))?                               # Case-sensitivity
  )?
  \]
/x;

sub matches {
  my $tree = shift->tree;
  return $tree->[0] ne 'tag' ? undef : _match(_compile(@_), $tree, $tree, _root($tree));
}

sub select     { _select(0, shift->tree, _compile(@_)) }
sub select_one { _select(1, shift->tree, _compile(@_)) }

sub _absolutize { [map { _is_scoped($_) ? $_ : [[['pc', 'scope']], ' ', @$_] } @{shift()}] }

sub _ancestor {
  my ($selectors, $current, $tree, $scope, $one, $pos) = @_;

  while ($current ne $scope && $current->[0] ne 'root' && ($current = $current->[3])) {
    return 1     if _combinator($selectors, $current, $tree, $scope, $pos);
    return undef if $current eq $scope;
    last         if $one;
  }

  return undef;
}

sub _attr {
  my ($name_re, $value_re, $current) = @_;

  my $attrs = $current->[2];
  for my $name (keys %$attrs) {
    my $value = $attrs->{$name};
    next if $name !~ $name_re || (!defined $value && defined $value_re);
    return 1 if !(defined $value && defined $value_re) || $value =~ $value_re;
  }

  return undef;
}

sub _combinator {
  my ($selectors, $current, $tree, $scope, $pos) = @_;

  # Selector
  return undef unless my $c = $selectors->[$pos];
  if (ref $c) {
    return undef unless _selector($c, $current, $tree, $scope);
    return 1 unless $c = $selectors->[++$pos];
  }

  # ">" (parent only)
  return _ancestor($selectors, $current, $tree, $scope, 1, ++$pos) if $c eq '>';

  # "~" (preceding siblings)
  return _sibling($selectors, $current, $tree, $scope, 0, ++$pos) if $c eq '~';

  # "+" (immediately preceding siblings)
  return _sibling($selectors, $current, $tree, $scope, 1, ++$pos) if $c eq '+';

  # " " (ancestor)
  return _ancestor($selectors, $current, $tree, $scope, 0, ++$pos);
}

sub _compile {
  my ($css, %ns) = (trim('' . shift), @_);

  my $group = [[]];
  while (my $selectors = $group->[-1]) {
    push @$selectors, [] unless @$selectors && ref $selectors->[-1];
    my $last = $selectors->[-1];

    # Separator
    if ($css =~ /\G\s*,\s*/gc) { push @$group, [] }

    # Combinator
    elsif ($css =~ /\G\s*([ >+~])\s*/gc) {
      push @$last, ['pc', 'scope'] unless @$last;
      push @$selectors, $1;
    }

    # Class or ID
    elsif ($css =~ /\G([.#])((?:$ESCAPE_RE\s|\\.|[^,.#:[ >~+])+)/gco) {
      my ($name, $op) = $1 eq '.' ? ('class', '~') : ('id', '');
      push @$last, ['attr', _name($name), _value($op, $2)];
    }

    # Attributes
    elsif ($css =~ /\G$ATTR_RE/gco) { push @$last, ['attr', _name($1), _value($2 // '', $3 // $4 // $5, $6)] }

    # Pseudo-class
    elsif ($css =~ /\G:([\w\-]+)(?:\(((?:\([^)]+\)|[^)])+)\))?/gcs) {
      my ($name, $args) = (lc $1, $2);

      # ":is" and ":not" (contains more selectors)
      $args = _compile($args, %ns) if $name eq 'has' || $name eq 'is' || $name eq 'not';

      # ":nth-*" (with An+B notation)
      $args = _equation($args) if $name =~ /^nth-/;

      # ":first-*" (rewrite to ":nth-*")
      ($name, $args) = ("nth-$1", [0, 1]) if $name =~ /^first-(.+)$/;

      # ":last-*" (rewrite to ":nth-*")
      ($name, $args) = ("nth-$name", [-1, 1]) if $name =~ /^last-/;

      push @$last, ['pc', $name, $args];
    }

    # Tag
    elsif ($css =~ /\G((?:$ESCAPE_RE\s|\\.|[^,.#:[ >~+])+)/gco) {
      my $alias = (my $name = $1) =~ s/^([^|]*)\|// && $1 ne '*' ? $1                                  : undef;
      my $ns    = length $alias                                  ? $ns{$alias} // return [['invalid']] : $alias;
      push @$last, ['tag', $name eq '*' ? undef : _name($name), _unescape($ns)];
    }

    else {last}
  }

  warn qq{-- CSS Selector ($css)\n@{[dumper $group]}} if DEBUG;
  return $group;
}

sub _empty { $_[0][0] eq 'comment' || $_[0][0] eq 'pi' }

sub _equation {
  return [0, 0] unless my $equation = shift;

  # "even"
  return [2, 2] if $equation =~ /^\s*even\s*$/i;

  # "odd"
  return [2, 1] if $equation =~ /^\s*odd\s*$/i;

  # "4", "+4" or "-4"
  return [0, $1] if $equation =~ /^\s*((?:\+|-)?\d+)\s*$/;

  # "n", "4n", "+4n", "-4n", "n+1", "4n-1", "+4n-1" (and other variations)
  return [0, 0] unless $equation =~ /^\s*((?:\+|-)?(?:\d+)?)?n\s*((?:\+|-)\s*\d+)?\s*$/i;
  return [$1 eq '-' ? -1 : !length $1 ? 1 : $1, join('', split(' ', $2 // 0))];
}

sub _is_scoped {
  my $selector = shift;

  for my $pc (grep { $_->[0] eq 'pc' } map { ref $_ ? @$_ : () } @$selector) {

    # Selector with ":scope"
    return 1 if $pc->[1] eq 'scope';

    # Argument of functional pseudo-class with ":scope"
    return 1 if ($pc->[1] eq 'has' || $pc->[1] eq 'is' || $pc->[1] eq 'not') && grep { _is_scoped($_) } @{$pc->[2]};
  }

  return undef;
}

sub _match {
  my ($group, $current, $tree, $scope) = @_;
  _combinator([reverse @$_], $current, $tree, $scope, 0) and return 1 for @$group;
  return undef;
}

sub _name {qr/(?:^|:)\Q@{[_unescape(shift)]}\E$/}

sub _namespace {
  my ($ns, $current) = @_;

  my $attr = $current->[1] =~ /^([^:]+):/ ? "xmlns:$1" : 'xmlns';
  while ($current) {
    last                               if $current->[0] eq 'root';
    return $current->[2]{$attr} eq $ns if exists $current->[2]{$attr};

    $current = $current->[3];
  }

  # Failing to match yields true if searching for no namespace, false otherwise
  return !length $ns;
}

sub _pc {
  my ($class, $args, $current, $tree, $scope) = @_;

  # ":scope"
  return $current eq $scope if $class eq 'scope';

  # ":checked"
  return exists $current->[2]{checked} || exists $current->[2]{selected} if $class eq 'checked';

  # ":not"
  return !_match($args, $current, $current, $scope) if $class eq 'not';

  # ":is"
  return !!_match($args, $current, $current, $scope) if $class eq 'is';

  # ":has"
  return !!_select(1, $current, $args) if $class eq 'has';

  # ":empty"
  return !grep { !_empty($_) } @$current[4 .. $#$current] if $class eq 'empty';

  # ":root"
  return $current->[3] && $current->[3][0] eq 'root' if $class eq 'root';

  # ":any-link", ":link" and ":visited"
  if ($class eq 'any-link' || $class eq 'link' || $class eq 'visited') {
    return undef unless $current->[0] eq 'tag' && exists $current->[2]{href};
    return !!grep { $current->[1] eq $_ } qw(a area link);
  }

  # ":only-child" or ":only-of-type"
  if ($class eq 'only-child' || $class eq 'only-of-type') {
    my $type = $class eq 'only-of-type' ? $current->[1] : undef;
    $_ ne $current and return undef for @{_siblings($current, $type)};
    return 1;
  }

  # ":nth-child", ":nth-last-child", ":nth-of-type" or ":nth-last-of-type"
  if (ref $args) {
    my $type     = $class eq 'nth-of-type' || $class eq 'nth-last-of-type' ? $current->[1] : undef;
    my @siblings = @{_siblings($current, $type)};
    @siblings = reverse @siblings if $class eq 'nth-last-child' || $class eq 'nth-last-of-type';

    for my $i (0 .. $#siblings) {
      next if (my $result = $args->[0] * $i + $args->[1]) < 1;
      return undef unless my $sibling = $siblings[$result - 1];
      return 1 if $sibling eq $current;
    }
  }

  # Everything else
  return undef;
}

sub _root {
  my $tree = shift;
  $tree = $tree->[3] while $tree->[0] ne 'root';
  return $tree;
}

sub _select {
  my ($one, $scope, $group) = @_;

  # Scoped selectors require the whole tree to be searched
  my $tree = $scope;
  ($group, $tree) = (_absolutize($group), _root($scope)) if grep { _is_scoped($_) } @$group;

  my @results;
  my @queue = @$tree[($tree->[0] eq 'root' ? 1 : 4) .. $#$tree];
  while (my $current = shift @queue) {
    next unless $current->[0] eq 'tag';

    unshift @queue, @$current[4 .. $#$current];
    next unless _match($group, $current, $tree, $scope);
    $one ? return $current : push @results, $current;
  }

  return $one ? undef : \@results;
}

sub _selector {
  my ($selector, $current, $tree, $scope) = @_;

  # The root might be the scope
  my $is_tag = $current->[0] eq 'tag';
  for my $s (@$selector) {
    my $type = $s->[0];

    # Tag
    if ($is_tag && $type eq 'tag') {
      return undef if defined $s->[1] && $current->[1] !~ $s->[1];
      return undef if defined $s->[2] && !_namespace($s->[2], $current);
    }

    # Attribute
    elsif ($is_tag && $type eq 'attr') { return undef unless _attr(@$s[1, 2], $current) }

    # Pseudo-class
    elsif ($type eq 'pc') { return undef unless _pc(@$s[1, 2], $current, $tree, $scope) }

    # No match
    else { return undef }
  }

  return 1;
}

sub _sibling {
  my ($selectors, $current, $tree, $scope, $immediate, $pos) = @_;

  my $found;
  for my $sibling (@{_siblings($current)}) {
    return $found if $sibling eq $current;

    # "+" (immediately preceding sibling)
    if ($immediate) { $found = _combinator($selectors, $sibling, $tree, $scope, $pos) }

    # "~" (preceding sibling)
    else { return 1 if _combinator($selectors, $sibling, $tree, $scope, $pos) }
  }

  return undef;
}

sub _siblings {
  my ($current, $type) = @_;

  my $parent   = $current->[3];
  my @siblings = grep { $_->[0] eq 'tag' } @$parent[($parent->[0] eq 'root' ? 1 : 4) .. $#$parent];
  @siblings = grep { $type eq $_->[1] } @siblings if defined $type;

  return \@siblings;
}

sub _unescape {
  return undef unless defined(my $value = shift);

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

  # "|=" (hyphen-separated)
  return qr/^$value(?:-|$)/ if $op eq '|';

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

L<Mojo::DOM::CSS> is the CSS selector engine used by L<Mojo::DOM>, based on the L<HTML Living
Standard|https://html.spec.whatwg.org> and L<Selectors Level 3|http://www.w3.org/TR/css3-selectors/>.

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

An C<E> element whose C<foo> attribute value is exactly equal to any (ASCII-range) case-permutation of C<bar>. Note
that this selector is B<EXPERIMENTAL> and might change without warning!

  my $case_insensitive = $css->select('input[type="hidden" i]');
  my $case_insensitive = $css->select('input[type=hidden i]');
  my $case_insensitive = $css->select('input[class~="foo" i]');

This selector is part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a work in progress.

=head2 E[foo="bar" s]

An C<E> element whose C<foo> attribute value is exactly and case-sensitively equal to C<bar>. Note that this selector
is B<EXPERIMENTAL> and might change without warning!

  my $case_sensitive = $css->select('input[type="hidden" s]');

This selector is part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a work in progress.

=head2 E[foo~="bar"]

An C<E> element whose C<foo> attribute value is a list of whitespace-separated values, one of which is exactly equal to
C<bar>.

  my $foo = $css->select('input[class~="foo"]');
  my $foo = $css->select('input[class~=foo]');

=head2 E[foo^="bar"]

An C<E> element whose C<foo> attribute value begins exactly with the string C<bar>.

  my $begins_with = $css->select('input[name^="f"]');
  my $begins_with = $css->select('input[name^=f]');

=head2 E[foo$="bar"]

An C<E> element whose C<foo> attribute value ends exactly with the string C<bar>.

  my $ends_with = $css->select('input[name$="o"]');
  my $ends_with = $css->select('input[name$=o]');

=head2 E[foo*="bar"]

An C<E> element whose C<foo> attribute value contains the substring C<bar>.

  my $contains = $css->select('input[name*="fo"]');
  my $contains = $css->select('input[name*=fo]');

=head2 E[foo|="en"]

An C<E> element whose C<foo> attribute has a hyphen-separated list of values beginning (from the left) with C<en>.

  my $english = $css->select('link[hreflang|=en]');

=head2 E:root

An C<E> element, root of the document.

  my $root = $css->select(':root');

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

=head2 E:empty

An C<E> element that has no children (including text nodes).

  my $empty = $css->select(':empty');

=head2 E:any-link

Alias for L</"E:link">. Note that this selector is B<EXPERIMENTAL> and might change without warning! This selector is
part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a work in progress.

=head2 E:link

An C<E> element being the source anchor of a hyperlink of which the target is not yet visited (C<:link>) or already
visited (C<:visited>). Note that L<Mojo::DOM::CSS> is not stateful, therefore C<:any-link>, C<:link> and C<:visited>
yield exactly the same results.

  my $links = $css->select(':any-link');
  my $links = $css->select(':link');
  my $links = $css->select(':visited');

=head2 E:visited

Alias for L</"E:link">.

=head2 E:scope

An C<E> element being a designated reference element. Note that this selector is B<EXPERIMENTAL> and might change
without warning!

  my $scoped = $css->select('a:not(:scope > a)');
  my $scoped = $css->select('div :scope p');
  my $scoped = $css->select('~ p');

This selector is part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a work in progress.

=head2 E:checked

A user interface element C<E> which is checked (for instance a radio-button or checkbox).

  my $input = $css->select(':checked');

=head2 E.warning

An C<E> element whose class is "warning".

  my $warning = $css->select('div.warning');

=head2 E#myid

An C<E> element with C<ID> equal to "myid".

  my $foo = $css->select('div#foo');

=head2 E:not(s1, s2)

An C<E> element that does not match either compound selector C<s1> or compound selector C<s2>. Note that support for
compound selectors is B<EXPERIMENTAL> and might change without warning!

  my $others = $css->select('div p:not(:first-child, :last-child)');

Support for compound selectors was added as part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is
still a work in progress.

=head2 E:is(s1, s2)

An C<E> element that matches compound selector C<s1> and/or compound selector C<s2>. Note that this selector is
B<EXPERIMENTAL> and might change without warning!

  my $headers = $css->select(':is(section, article, aside, nav) h1');

This selector is part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a work in progress.

=head2 E:has(rs1, rs2)

An C<E> element, if either of the relative selectors C<rs1> or C<rs2>, when evaluated with C<E> as the :scope elements,
match an element. Note that this selector is B<EXPERIMENTAL> and might change without warning!

  my $link = $css->select('a:has(> img)');

This selector is part of L<Selectors Level 4|http://dev.w3.org/csswg/selectors-4>, which is still a work in progress.
Also be aware that this feature is currently marked C<at-risk>, so there is a high chance that it will get removed
completely.

=head2 A|E

An C<E> element that belongs to the namespace alias C<A> from L<CSS Namespaces Module Level
3|https://www.w3.org/TR/css-namespaces-3/>. Key/value pairs passed to selector methods are used to declare namespace
aliases.

  my $elem = $css->select('lq|elem', lq => 'http://example.com/q-markup');

Using an empty alias searches for an element that belongs to no namespace.

  my $div = $c->select('|div');

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

Document Object Model. Note that this structure should only be used very carefully since it is very dynamic.

=head1 METHODS

L<Mojo::DOM::CSS> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 matches

  my $bool = $css->matches('head > title');
  my $bool = $css->matches('svg|line', svg => 'http://www.w3.org/2000/svg');

Check if first node in L</"tree"> matches the CSS selector. Trailing key/value pairs can be used to declare xml
namespace aliases.

=head2 select

  my $results = $css->select('head > title');
  my $results = $css->select('svg|line', svg => 'http://www.w3.org/2000/svg');

Run CSS selector against L</"tree">. Trailing key/value pairs can be used to declare xml namespace aliases.

=head2 select_one

  my $result = $css->select_one('head > title');
  my $result =
    $css->select_one('svg|line', svg => 'http://www.w3.org/2000/svg');

Run CSS selector against L</"tree"> and stop as soon as the first node matched. Trailing key/value pairs can be used to
declare xml namespace aliases.

=head1 DEBUGGING

You can set the C<MOJO_DOM_CSS_DEBUG> environment variable to get some advanced diagnostics information printed to
C<STDERR>.

  MOJO_DOM_CSS_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
