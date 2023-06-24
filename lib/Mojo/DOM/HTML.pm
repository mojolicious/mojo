package Mojo::DOM::HTML;
use Mojo::Base -base;

use Exporter     qw(import);
use Mojo::Util   qw(html_attr_unescape html_unescape xml_escape);
use Scalar::Util qw(weaken);

our @EXPORT_OK = ('tag_to_html');

has tree => sub { ['root'] };
has 'xml';

my $ATTR_RE = qr/
  ([^<>=\s\/0-9.\-][^<>=\s\/]*|\/)     # Key
  (?:
    \s*=\s*
    (?s:(["'])(.*?)\g{-2}|([^>\s]*))   # Value
  )?
  \s*
/x;
my $TOKEN_RE = qr/
  ([^<]+)?                                                                     # Text
  (?:
    <(?:
      !(?:
        DOCTYPE(
        \s+\w+                                                                 # Doctype
        (?:(?:\s+\w+)?(?:\s+(?:"[^"]*"|'[^']*'))+)?                            # External ID
        (?:\s+\[.+?\])?                                                        # Int Subset
        \s*)
      |
        --(?|()-*!?(?=>)|(.*?)--!?(?=>))                                       # Comment
      |
        \[CDATA\[(.*?)\]\]                                                     # CDATA
      )
    |
      \?(.*?)\?                                                                # Processing Instruction
    |
      \s*((?:\/\s*)?[^<>\s\/0-9.\-][^<>\s\/]*\s*(?:(?:$ATTR_RE){0,32766})*+)   # Tag
    )>
  |
    (<)                                                                        # Runaway "<"
  )??
/xis;

# HTML elements that only contain raw text
my %RAW = map { $_ => 1 } qw(script style);

# HTML elements that only contain raw text and entities
my %RCDATA = map { $_ => 1 } qw(title textarea);

# HTML elements with optional end tags
my %END = (body => 'head', optgroup => 'optgroup', option => 'option');

# HTML elements that break paragraphs
map { $END{$_} = 'p' } (
  qw(address article aside blockquote details dialog div dl fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6),
  qw(header hgroup hr main menu nav ol p pre section table ul)
);

# Container HTML elements that create their own scope
my %SCOPE = map { $_ => 1 } qw(math svg);

# HTML table elements with optional end tags
my %TABLE = map { $_ => 1 } qw(colgroup tbody td tfoot th thead tr);

# HTML elements with optional end tags and scoping rules
my %CLOSE = (li => [{li => 1}, {ul => 1, ol => 1}], tr => [{tr => 1}, {table => 1}]);
$CLOSE{$_} = [\%TABLE, {table => 1}] for qw(colgroup tbody tfoot thead);
$CLOSE{$_} = [{dd => 1, dt => 1}, {dl    => 1}] for qw(dd dt);
$CLOSE{$_} = [{rp => 1, rt => 1}, {ruby  => 1}] for qw(rp rt);
$CLOSE{$_} = [{th => 1, td => 1}, {table => 1}] for qw(td th);

# HTML parent elements that signal no more content when closed, but that are also phrasing content
my %NO_MORE_CONTENT = (ruby => [qw(rt rp)], select => [qw(option optgroup)]);

# HTML elements without end tags
my %EMPTY = map { $_ => 1 } qw(area base br col embed hr img input keygen link menuitem meta param source track wbr);

# HTML elements categorized as phrasing content (and obsolete inline elements)
my @PHRASING = (
  qw(a abbr area audio b bdi bdo br button canvas cite code data datalist del dfn em embed i iframe img input ins kbd),
  qw(keygen label link map mark math meta meter noscript object output picture progress q ruby s samp script select),
  qw(slot small span strong sub sup svg template textarea time u var video wbr)
);
my @OBSOLETE = qw(acronym applet basefont big font strike tt);
my %PHRASING = map { $_ => 1 } @OBSOLETE, @PHRASING;

# HTML elements that don't get their self-closing flag acknowledged
my %BLOCK = map { $_ => 1 } (
  qw(a address applet article aside b big blockquote body button caption center code col colgroup dd details dialog),
  qw(dir div dl dt em fieldset figcaption figure font footer form frameset h1 h2 h3 h4 h5 h6 head header hgroup html),
  qw(i iframe li listing main marquee menu nav nobr noembed noframes noscript object ol optgroup option p plaintext),
  qw(pre rp rt s script section select small strike strong style summary table tbody td template textarea tfoot th),
  qw(thead title tr tt u ul xmp)
);

sub parse {
  my ($self, $html) = (shift, "$_[0]");

  my $xml     = $self->xml;
  my $current = my $tree = ['root'];
  while ($html =~ /\G$TOKEN_RE/gcso) {
    my ($text, $doctype, $comment, $cdata, $pi, $tag, $runaway) = ($1, $2, $3, $4, $5, $6, $11);

    # Text (and runaway "<")
    $text .= '<'                                 if defined $runaway;
    _node($current, 'text', html_unescape $text) if defined $text;

    # Tag
    if (defined $tag) {

      # End
      if ($tag =~ /^\/\s*(\S+)/) {
        my $end = $xml ? $1 : lc $1;

        # No more content
        if (!$xml && (my $tags = $NO_MORE_CONTENT{$end})) { _end($_, $xml, \$current) for @$tags }

        _end($end, $xml, \$current);
      }

      # Start
      elsif ($tag =~ m!^([^\s/]+)([\s\S]*)!) {
        my ($start, $attr) = ($xml ? $1 : lc $1, $2);

        # Attributes
        my (%attrs, $closing);
        while ($attr =~ /$ATTR_RE/go) {
          my ($key, $value) = ($xml ? $1 : lc $1, $3 // $4);

          # Empty tag
          ++$closing and next if $key eq '/';

          $attrs{$key} = defined $value ? html_attr_unescape $value : $value;
        }

        # "image" is an alias for "img"
        $start = 'img' if !$xml && $start eq 'image';
        _start($start, \%attrs, $xml, \$current);

        # Element without end tag (self-closing)
        _end($start, $xml, \$current) if !$xml && $EMPTY{$start} || ($xml || !$BLOCK{$start}) && $closing;

        # Raw text elements
        next if $xml || !$RAW{$start} && !$RCDATA{$start};
        next unless $html =~ m!\G(.*?)</\Q$start\E(?:\s+|\s*>)!gcsi;
        _node($current, 'raw', $RCDATA{$start} ? html_unescape $1 : $1);
        _end($start, 0, \$current);
      }
    }

    # DOCTYPE
    elsif (defined $doctype) { _node($current, 'doctype', $doctype) }

    # Comment
    elsif (defined $comment) { _node($current, 'comment', $comment) }

    # CDATA
    elsif (defined $cdata) { _node($current, 'cdata', $cdata) }

    # Processing instruction (try to detect XML)
    elsif (defined $pi) {
      $self->xml($xml = 1) if !exists $self->{xml} && $pi =~ /xml/i;
      _node($current, 'pi', $pi);
    }
  }

  return $self->tree($tree);
}

sub render { _render($_[0]->tree, $_[0]->xml) }

sub tag { shift->tree(['root', _tag(@_)]) }

sub tag_to_html { _render(_tag(@_), undef) }

sub _end {
  my ($end, $xml, $current) = @_;

  # Search stack for start tag
  my $next = $$current;
  do {

    # Ignore useless end tag
    return if $next->[0] eq 'root';

    # Don’t traverse a container tag
    return if $SCOPE{$next->[1]} && $next->[1] ne $end;

    # Right tag
    return $$current = $next->[3] if $next->[1] eq $end;

    # Phrasing content can only cross phrasing content
    return if !$xml && $PHRASING{$end} && !$PHRASING{$next->[1]};

  } while $next = $next->[3];
}

sub _node {
  my ($current, $type, $content) = @_;
  push @$current, my $new = [$type, $content, $current];
  weaken $new->[2];
}

sub _render {
  my ($tree, $xml) = @_;

  # Tag
  my $type = $tree->[0];
  if ($type eq 'tag') {

    # Start tag
    my $tag    = $tree->[1];
    my $result = "<$tag";

    # Attributes
    for my $key (sort keys %{$tree->[2]}) {
      my $value = $tree->[2]{$key};
      $result .= $xml ? qq{ $key="$key"} : " $key" and next unless defined $value;
      $result .= qq{ $key="} . xml_escape($value) . '"';
    }

    # No children
    return $xml ? "$result />" : $EMPTY{$tag} ? "$result>" : "$result></$tag>" unless $tree->[4];

    # Children
    no warnings 'recursion';
    $result .= '>' . join '', map { _render($_, $xml) } @$tree[4 .. $#$tree];

    # End tag
    return "$result</$tag>";
  }

  # Text (escaped)
  return xml_escape $tree->[1] if $type eq 'text';

  # Raw text
  return $tree->[1] if $type eq 'raw';

  # Root
  return join '', map { _render($_, $xml) } @$tree[1 .. $#$tree] if $type eq 'root';

  # DOCTYPE
  return '<!DOCTYPE' . $tree->[1] . '>' if $type eq 'doctype';

  # Comment
  return '<!--' . $tree->[1] . '-->' if $type eq 'comment';

  # CDATA
  return '<![CDATA[' . $tree->[1] . ']]>' if $type eq 'cdata';

  # Processing instruction
  return '<?' . $tree->[1] . '?>' if $type eq 'pi';

  # Everything else
  return '';
}

sub _start {
  my ($start, $attrs, $xml, $current) = @_;

  # Autoclose optional HTML elements
  if (!$xml && $$current->[0] ne 'root') {
    if (my $end = $END{$start}) { _end($end, 0, $current) }

    elsif (my $close = $CLOSE{$start}) {
      my ($allowed, $scope) = @$close;

      # Close allowed parent elements in scope
      my $parent = $$current;
      while ($parent->[0] ne 'root' && !$scope->{$parent->[1]}) {
        _end($parent->[1], 0, $current) if $allowed->{$parent->[1]};
        $parent = $parent->[3];
      }
    }
  }

  # New tag
  push @$$current, my $new = ['tag', $start, $attrs, $$current];
  weaken $new->[3];
  $$current = $new;
}

sub _tag {
  my $tree = ['tag', shift, undef, undef];

  # Content
  push @$tree, ref $_[-1] eq 'CODE' ? ['raw', pop->()] : ['text', pop] if @_ % 2;

  # Attributes
  my $attrs = $tree->[2] = {@_};
  return $tree unless exists $attrs->{data} && ref $attrs->{data} eq 'HASH';
  my $data = delete $attrs->{data};
  @$attrs{map { y/_/-/; lc "data-$_" } keys %$data} = values %$data;
  return $tree;
}

1;

=encoding utf8

=head1 NAME

Mojo::DOM::HTML - HTML/XML engine

=head1 SYNOPSIS

  use Mojo::DOM::HTML;

  # Turn HTML into DOM tree
  my $html = Mojo::DOM::HTML->new;
  $html->parse('<div><p id="a">Test</p><p id="b">123</p></div>');
  my $tree = $html->tree;

=head1 DESCRIPTION

L<Mojo::DOM::HTML> is the HTML/XML engine used by L<Mojo::DOM>, based on the L<HTML Living
Standard|https://html.spec.whatwg.org> and the L<Extensible Markup Language (XML) 1.0|https://www.w3.org/TR/xml/>.

=head1 FUNCTIONS

L<Mojo::DOM::HTML> implements the following functions, which can be imported individually.

=head2 tag_to_html

  my $str = tag_to_html 'div', id => 'foo', 'safe content';

Generate HTML/XML tag and render it right away. This is a significantly faster alternative to L</"tag"> for template
systems that have to generate a lot of tags.

=head1 ATTRIBUTES

L<Mojo::DOM::HTML> implements the following attributes.

=head2 tree

  my $tree = $html->tree;
  $html    = $html->tree(['root']);

Document Object Model. Note that this structure should only be used very carefully since it is very dynamic.

=head2 xml

  my $bool = $html->xml;
  $html    = $html->xml($bool);

Disable HTML semantics in parser and activate case-sensitivity, defaults to auto-detection based on XML declarations.

=head1 METHODS

L<Mojo::DOM::HTML> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 parse

  $html = $html->parse('<foo bar="baz">I ♥ Mojolicious!</foo>');

Parse HTML/XML fragment.

=head2 render

  my $str = $html->render;

Render DOM to HTML/XML.

=head2 tag

  $html = $html->tag('div', id => 'foo', 'safe content');

Generate HTML/XML tag.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
