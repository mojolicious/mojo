package Mojo::DOM::HTML;
use Mojo::Base -base;

use Mojo::Util qw/decode encode html_unescape xml_escape/;
use Scalar::Util 'weaken';

# Regex
my $HTML_ATTR_RE = qr/
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
my $HTML_END_RE   = qr/^\s*\/\s*(.+)\s*/;
my $HTML_START_RE = qr/([^\s\/]+)([\s\S]*)/;
my $HTML_TOKEN_RE = qr/
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
      (?:$HTML_ATTR_RE)*                            # Attributes
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

has [qw/charset xml/];
has tree => sub { ['root'] };

sub parse {
  my ($self, $html) = @_;

  # Decode
  my $charset = $self->charset;
  decode $charset, $html if $charset && !utf8::is_utf8 $html;

  # Tokenize
  my $tree    = ['root'];
  my $current = $tree;
  while ($html =~ m/\G$HTML_TOKEN_RE/gcs) {
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

    # End
    next unless $tag;
    my $cs = $self->xml;
    if ($tag =~ /$HTML_END_RE/) {
      if (my $end = $cs ? $1 : lc($1)) { $self->_end($end, \$current) }
    }

    # Start
    elsif ($tag =~ /$HTML_START_RE/) {
      my $start = $cs ? $1 : lc($1);
      my $attr = $2;

      # Attributes
      my $attrs = {};
      while ($attr =~ /$HTML_ATTR_RE/g) {
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
        if ($html =~ /\G(.*?)<\s*\/\s*$start\s*>/gcsi) {
          $self->_raw($1, \$current);
          $self->_end($start, \$current);
        }
      }
    }
  }
  $self->tree($tree);

  return $self;
}

sub render {
  my $self    = shift;
  my $content = $self->_render($self->tree);
  my $charset = $self->charset;
  encode $charset, $content if $charset;
  return $content;
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

1;
__END__

=head1 NAME

Mojo::DOM::HTML - HTML5/XML Engine

=head1 SYNOPSIS

  use Mojo::DOM::HTML;

=head1 DESCRIPTION

L<Mojo::DOM::HTML> is the HTML5/XML engine used by L<Mojo::DOM>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::DOM::HTML> implements the following attributes.

=head2 C<charset>

  my $charset = $html->charset;
  $html       = $html->charset('UTF-8');

Charset used for decoding and encoding HTML5/XML.

=head2 C<tree>

  my $tree = $html->tree;
  $html    = $html->tree(['root', ['text', 'lalala']]);

Document Object Model.

=head2 C<xml>

  my $xml = $html->xml;
  $html   = $html->xml(1);

Disable HTML5 semantics in parser and activate case sensitivity, defaults to
auto detection based on processing instructions.

=head1 METHODS

L<Mojo::DOM::HTML> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<parse>

  $html = $html->parse('<foo bar="baz">test</foo>');

Parse HTML5/XML document.

=head2 C<render>

  my $xml = $html->render;

Render DOM to XML.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
