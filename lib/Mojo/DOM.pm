package Mojo::DOM;

use strict;
use warnings;

use base 'Mojo::Base';
use overload '""' => sub { shift->to_xml }, fallback => 1;

use Mojo::ByteStream 'b';
use Scalar::Util 'weaken';

# How are the kids supposed to get home?
# I dunno. Internet?
__PACKAGE__->attr(charset => 'UTF-8');
__PACKAGE__->attr(tree => sub { ['root'] });

# Regex
my $CSS_ESCAPE_RE = qr/\\[^0-9a-fA-F]|\\[0-9a-fA-F]{1,6}/;
my $CSS_ATTR_RE   = qr/
    \[
    ((?:$CSS_ESCAPE_RE|\w)+)   # Key
    (?:
    (\W)?                      # Operator
    =
    "((?:\\"|[^"])+)"          # Value
    )?
    \]
/x;
my $CSS_CLASS_RE        = qr/\.((?:\\\.|[^\.])+)/;
my $CSS_ELEMENT_RE      = qr/^((?:\\\.|\\\#|[^\.\#])+)/;
my $CSS_ID_RE           = qr/\#((?:\\\#|[^\#])+)/;
my $CSS_PSEUDO_CLASS_RE = qr/(?:\:(\w+)(?:\(([^\)]+)\))?)/;
my $CSS_TOKEN_RE        = qr/
    (\s*,\s*)?                                                   # Separator
    ((?:[^\[\\\:\s]|$CSS_ESCAPE_RE\s?)+)?                        # Element
    ((?:\:\w+(?:\([^\)]+\))?)*)?                                 # Pseudoclass
    ((?:\[(?:$CSS_ESCAPE_RE|\w)+(?:\W?="(?:\\"|[^"])+")?\])*)?   # Attributes
    (?:
    \s*
    ([\>\+\~])                                                   # Combinator
    )?
/x;
my $XML_ATTR_RE = qr/
    ([^=\s]+)                                   # Key
    (?:\s*=\s*(?:"([^"]*)"|'([^']*)'|(\S+)))?   # Value
/x;
my $XML_END_RE   = qr/^\s*\/\s*(.+)\s*/;
my $XML_START_RE = qr/(\S+)([\s\S]*)/;
my $XML_TOKEN_RE = qr/
    ([^<]*)                  # Text
    (?:
    <\?(.*?)\?>              # Processing Instruction
    |
    <\!--(.*?)-->            # Comment
    |
    <\!\[CDATA\[(.*?)\]\]>   # CDATA
    |
    <\!DOCTYPE([^>]*)>       # DOCTYPE
    |
    <(
    \s*
    [^>\s]+                  # Tag
    (?:
        \s*
        [^=\s>"']+           # Key
        (?:
            \s*
            =
            \s*
            (?:
            "[^"]*?"         # Quotation marks
            |
            '[^']*?'         # Apostrophes
            |
            [^>\s]+          # Unquoted
            )
        )?
        \s*
    )*
    )>
    )??
/xis;

sub all_text {
    my $self = shift;

    # Text
    my $text = '';

    # Tree
    my $tree = $self->tree;

    # Walk tree
    my $start = $tree->[0] eq 'root' ? 1 : 4;
    my @stack = @$tree[$start .. $#$tree];
    while (my $e = shift @stack) {

        # Type
        my $type = $e->[0];

        unshift @stack, @$e[4 .. $#$e] and next if $type eq 'tag';

        # Text or CDATA
        if ($type eq 'text' || $type eq 'cdata') {
            my $content = $e->[1];
            $text .= $content if $content =~ /\S+/;
        }
    }

    return $text;
}

sub at { shift->find(@_)->[0] }

sub attrs {
    my $self = shift;

    # Tree
    my $tree = $self->tree;

    # Root
    return if $tree->[0] eq 'root';

    return $tree->[2];
}

sub children {
    my $self = shift;

    # Children
    my @children;

    # Tree
    my $tree = $self->tree;

    # Walk tree
    my $start = $tree->[0] eq 'root' ? 1 : 4;
    for my $e (@$tree[$start .. $#$tree]) {

        # Tag
        next unless $e->[0] eq 'tag';

        # Add child
        push @children, $self->new(charset => $self->charset, tree => $e);
    }

    return \@children;
}

sub find {
    my ($self, $css) = @_;

    # Parse CSS selectors
    my $pattern = $self->_parse_css($css);

    # Filter tree
    return $self->_select($self->tree, $pattern);
}

sub name {
    my ($self, $name) = @_;

    # Tree
    my $tree = $self->tree;

    # Root
    return if $tree->[0] eq 'root';

    # Get
    return $tree->[1] unless $name;

    # Set
    $tree->[1] = $name;

    return $self;
}

sub namespace {
    my $self = shift;

    # Current
    my $current = $self->tree;
    return if $current->[0] eq 'root';

    # Prefix
    my $prefix = '';
    if ($current->[1] =~ /^(.*?)\:/) { $prefix = $1 }

    # Walk tree
    while ($current) {

        # Root
        return if $current->[0] eq 'root';

        # Attributes
        my $attrs = $current->[2];

        # Namespace for prefix
        if ($prefix) {
            for my $key (keys %$attrs) {
                return $attrs->{$key} if $key =~ /^xmlns\:$prefix$/;
            }
        }

        # Namespace attribute
        if (my $namespace = $attrs->{xmlns}) { return $namespace }

        # Parent
        $current = $current->[3];
    }
}

sub parent {
    my $self = shift;

    # Tree
    my $tree = $self->tree;

    # Root
    return if $tree->[0] eq 'root';

    # Parent
    return $self->new(charset => $self->charset, tree => $tree->[3]);
}

sub parse {
    my ($self, $xml) = @_;

    # Parse
    $self->tree($self->_parse_xml($xml));
}

sub replace {
    my ($self, $new) = @_;

    # Parse
    $new = ref $new ? $new->tree : $self->_parse_xml($new);

    # Tree
    my $tree = $self->tree;

    # Root
    return $self->replace_content(
        $self->new(charset => $self->charset, tree => $new))
      if $tree->[0] eq 'root';

    # Parent
    my $parent = $tree->[3];

    # Replacements
    my @new;
    for my $e (@$new[1 .. $#$new]) {
        $e->[3] = $parent if $e->[0] eq 'tag';
        push @new, $e;
    }

    # Find
    my $i = $parent->[0] eq 'root' ? 1 : 4;
    for my $e (@$parent[$i .. $#$parent]) {
        last if $e == $tree;
        $i++;
    }

    # Replace
    splice @$parent, $i, 1, @new;

    return $self;
}

sub replace_content {
    my ($self, $new) = @_;

    # Parse
    $new = ref $new ? $new->tree : $self->_parse_xml($new);

    # Tree
    my $tree = $self->tree;

    # Replacements
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

    return $self->new(charset => $self->charset, tree => $root);
}

sub text {
    my $self = shift;

    # Text
    my $text = '';

    # Walk stack
    for my $e (@{$self->tree}) {

        # Meta data
        next unless ref $e eq 'ARRAY';

        # Type
        my $type = $e->[0];

        # Text or CDATA
        if ($type eq 'text' || $type eq 'cdata') {
            my $content = $e->[1];
            $text .= $content if $content =~ /\S+/;
        }
    }

    return $text;
}

sub to_xml {
    my $self = shift;

    # Render
    my $result = $self->_render($self->tree);

    # Encode
    my $charset = $self->charset;
    $result = b($result)->encode($charset)->to_string if $charset;

    return $result;
}

# Woah! God is so in your face!
# Yeah, he's my favorite fictional character.
sub _cdata {
    my ($self, $cdata, $current) = @_;

    # Append
    push @$$current, ['cdata', $cdata];
}

sub _comment {
    my ($self, $comment, $current) = @_;

    # Append
    push @$$current, ['comment', $comment];
}

sub _compare {
    my ($self, $selector, $current) = @_;

    # Selectors
    for my $c (@$selector[1 .. $#$selector]) {
        my $type = $c->[0];

        # Tag
        if ($type eq 'tag') {
            my $name = $c->[1];

            # Wildcard
            next if $name eq '*';

            # Name (ignore namespace prefix)
            next if $current->[1] =~ /\:?$name$/;
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
            my $class = $c->[1];

            # ":root"
            if ($class eq 'root') {
                if (my $parent = $current->[3]) {
                    next if $parent->[0] eq 'root';
                }
            }
        }

        return;
    }

    return 1;
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

    # Append
    push @$$current, ['doctype', $doctype];
}

sub _end {
    my ($self, $end, $current) = @_;

    # Root
    return if $$current->[0] eq 'root';

    # Walk backwards
    while (1) {

        # Root
        last if $$current->[0] eq 'root';

        # Match
        return $$current = $$current->[3] if $end eq $$current->[1];

        # Children to move to parent
        my @buffer = splice @$$current, 4;

        # Parent
        $$current = $$current->[3];

        # Update parent reference
        for my $e (@buffer) {
            $e->[3] = $$current if $e->[0] eq 'tag';
            weaken $e->[3];
        }

        # Move children
        push @$$current, @buffer;
    }
}

sub _match {
    my ($self, $candidate, $pattern) = @_;

    # Parts
    my $first = 2;
    for my $part (@$pattern) {

        # Selectors
        my @selectors = reverse @$part;

        # Match
        my ($current, $marker, $snapback);
        my $parentonly = 0;
        for (my $i = 0; $i <= $#selectors; $i++) {
            my $selector = $selectors[$i];

            # Combinator
            $parentonly-- if $parentonly > 0;
            if ($selector->[0] eq 'combinator') {

                # Parent only ">"
                if ($selector->[1] eq '>') {
                    $parentonly += 2;
                    $marker   = $i - 1   unless defined $marker;
                    $snapback = $current unless $snapback;
                }

                # Move on
                next;
            }

            while (1) {
                $first-- if $first != 0;

                # Next parent
                return
                  unless $current = $current ? $current->[3] : $candidate;

                # Root
                return if $current->[0] ne 'tag';

                # Compare part to element
                last if $self->_compare($selector, $current);

                # First selector needs to match
                return if $first;

                # Parent only
                if ($parentonly) {
                    $i        = $marker - 1;
                    $current  = $snapback;
                    $snapback = undef;
                    $marker   = undef;
                    last;
                }
            }
        }
    }

    return 1;
}

sub _parse_css {
    my ($self, $css) = @_;

    # Tokenize
    my $pattern = [[]];
    while ($css =~ /$CSS_TOKEN_RE/g) {
        my $separator  = $1;
        my $element    = $2;
        my $pc         = $3;
        my $attributes = $4;
        my $combinator = $5;

        # Trash
        next
          unless $separator || $element || $pc || $attributes || $combinator;

        # New selector
        push @$pattern, [] if $separator;

        # Part
        my $part = $pattern->[-1];

        # Selector
        push @$part, ['element'];
        my $selector = $part->[-1];

        # Element
        $element ||= '';
        my $tag = '*';
        $element =~ s/$CSS_ELEMENT_RE// and $tag = $self->_css_unescape($1);

        # Tag
        push @$selector, ['tag', $tag];

        # Classes
        while ($element =~ /$CSS_CLASS_RE/g) {
            my $class = $self->_css_unescape($1);
            push @$selector,
              ['attribute', 'class', qr/(?:^|\W+)$class(?:\W+|$)/];
        }

        # ID
        if ($element =~ /$CSS_ID_RE/) {
            my $id = $self->_css_unescape($1);
            push @$selector, ['attribute', 'id', qr/^$id$/];
        }

        # Pseudo classes
        while ($pc =~ /$CSS_PSEUDO_CLASS_RE/g) {
            push @$selector, ['pseudoclass', $1, $2];
        }

        # Attributes
        while ($attributes =~ /$CSS_ATTR_RE/g) {
            my $key   = $self->_css_unescape($1);
            my $op    = $2 || '';
            my $value = $3;

            # Regex
            my $regex;

            # Value
            if ($value) {

                # Quote
                $value = quotemeta $self->_css_unescape($value);

                # "^=" (begins with)
                if ($op eq '^') { $regex = qr/^$value/ }

                # "$=" (ends with)
                elsif ($op eq '$') { $regex = qr/$value$/ }

                # Everything else
                else { $regex = qr/^$value$/ }
            }

            push @$selector, ['attribute', $key, $regex];
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
    $xml = b($xml)->decode($charset)->to_string if $charset;
    return $tree unless $xml;

    # Tokenize
    while ($xml =~ /$XML_TOKEN_RE/g) {
        my $text    = $1;
        my $pi      = $2;
        my $comment = $3;
        my $cdata   = $4;
        my $doctype = $5;
        my $tag     = $6;

        # Text
        if ($text) {

            # Unescape
            $text = b($text)->html_unescape->to_string if $text =~ /&/;

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
        if ($tag =~ /$XML_END_RE/) {
            if (my $end = lc $1) { $self->_end($end, \$current) }
        }

        # Start
        elsif ($tag =~ /$XML_START_RE/) {
            my $start = lc $1;
            my $attr  = $2;

            # Attributes
            my $attrs = {};
            while ($attr =~ /$XML_ATTR_RE/g) {
                my $key   = $1;
                my $value = $2;
                $value = $3 unless defined $value;
                $value = $4 unless defined $value;

                # End
                next if $key eq '/';

                # Unescape
                $value = b($value)->html_unescape->to_string
                  if $value && $value =~ /&/;

                # Merge
                $attrs->{$key} = $value;
            }

            # Start
            $self->_start($start, $attrs, \$current);
        }
    }

    return $tree;
}

sub _pi {
    my ($self, $pi, $current) = @_;

    # Append
    push @$$current, ['pi', $pi];
}

sub _render {
    my ($self, $tree) = @_;

    # Element
    my $e = $tree->[0];

    # Text (escaped)
    return b($tree->[1])->xml_escape->to_string if $e eq 'text';

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

    # Content
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
            push @attrs, $key and next unless $value;

            # Escape
            $value = b($value)->xml_escape->to_string;

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

sub _select {
    my ($self, $tree, $pattern) = @_;

    # Walk tree
    my @results;
    my @queue = ($tree);
    while (my $current = shift @queue) {

        # Type
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

            # Match
            push @results, $current if $self->_match($current, $pattern);
        }
    }

    # Upgrade results
    @results =
      map { $self->new(charset => $self->charset, tree => $_) } @results;

    # Collection
    return bless \@results, 'Mojo::DOM::_Collection';
}

# It's not important to talk about who got rich off of whom,
# or who got exposed to tainted what...
sub _start {
    my ($self, $start, $attrs, $current) = @_;

    # New
    my $new = ['tag', $start, $attrs, $$current];
    weaken $new->[3];

    # Append
    push @$$current, $new;
    $$current = $new;
}

sub _text {
    my ($self, $text, $current) = @_;

    # Append
    push @$$current, ['text', $text];
}

package Mojo::DOM::_Collection;

sub each {
    my ($self, $cb) = @_;

    # Shortcut
    return @$self unless $cb;

    # Iterate
    my $i = 1;
    $_->$cb($i++) for @$self;

    # Root
    return unless my $start = $self->[0];
    return $start->root;
}

1;
__END__

=head1 NAME

Mojo::DOM - Minimalistic XML DOM Parser With CSS3 Selectors

=head1 SYNOPSIS

    use Mojo::DOM;

    # Parse
    my $dom = Mojo::DOM->new;
    $dom->parse('<div><div id="a">A</div><div id="b">B</div></div>');

    # Find
    my $b = $dom->at('#b');
    print $b->text;

    # Iterate
    $dom->find('div[id]')->each(sub { print shift->text });

=head1 DESCRIPTION

L<Mojo::DOM> is a minimalistic and very relaxed XML DOM parser with support
for CSS3 selectors.
Note that this module is EXPERIMENTAL and might change without warning!

=head2 SELECTORS

These CSS3 selectors are currently implemented.

=over 4

=item C<*>

Any element.

=item C<E>

    my $title = $dom->at('title');

An element of type C<E>.

=item C<E[foo]>

    my $links = $dom->find('a[href]');

An C<E> element with a C<foo> attribute.

=item C<E[foo="bar"]>

    my $fields = $dom->find('input[name="foo"]');

An C<E> element whose C<foo> attribute value is exactly equal to C<bar>.

=item C<E[foo^="bar"]>

    my $fields = $dom->find('input[name^="f"]');

An C<E> element whose C<foo> attribute value begins exactly with the string
C<bar>.

=item C<E[foo$="bar"]>

    my $fields = $dom->find('input[name$="o"]');

An C<E> element whose C<foo> attribute value ends exactly with the string
C<bar>.

=item C<E:root>

    my $root = $dom->at(':root');

An C<E> element, root of the document.

=item C<E F>

    my $headlines = $dom->find('div h1');

An C<F> element descendant of an C<E> element.

=item C<E E<gt> F>

    my $headlines = $dom->find('html > body > div > h1');

An C<F> element child of an C<E> element.

=back

=head1 ATTRIBUTES

L<Mojo::DOM> implements the following attributes.

=head2 C<charset>

    my $charset = $dom->charset;
    $dom        = $dom->charset('UTF-8');

Charset used for decoding XML.

=head2 C<tree>

    my $array = $dom->tree;
    $dom      = $dom->tree(['root', ['text', 'lalala']]);

Document Object Model.

=head1 METHODS

L<Mojo::DOM> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<all_text>

    my $text = $dom->all_text;

Extract all text content from DOM structure.

=head2 C<at>

    my $result = $dom->at('html title');

Find a single element with CSS3 selectors.

=head2 C<attrs>

    my $attrs = $dom->attrs;

Element attributes.

=head2 C<children>

    my $children = $dom->children;

Children of element.

=head2 C<find>

    my $results = $dom->find('html title');

Find elements with CSS3 selectors.

    $dom->find('div')->each(sub { print shift->text });

=head2 C<name>

    my $name = $dom->name;
    $dom     = $dom->name('html');

Element name.

=head2 C<namespace>

    my $namespace = $dom->namespace;

Element namespace.

=head2 C<parent>

    my $parent = $dom->parent;

Parent of element.

=head2 C<parse>

    $dom = $dom->parse('<foo bar="baz">test</foo>');

Parse XML document.

=head2 C<replace>

    $dom = $dom->replace('<div>test</div>');

Replace elements.

=head2 C<replace_content>

    $dom = $dom->replace_content('test');

Replace element content.

=head2 C<root>

    my $root = $dom->root;

Find root element.

=head2 C<text>

    my $text = $dom->text;

Extract text content from element only, not including child elements.

=head2 C<to_xml>

    my $xml = $dom->to_xml;

Render DOM to XML.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
