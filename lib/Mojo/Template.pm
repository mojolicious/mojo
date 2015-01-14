package Mojo::Template;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::ByteStream;
use Mojo::Exception;
use Mojo::Util qw(decode encode monkey_patch slurp);

use constant DEBUG => $ENV{MOJO_TEMPLATE_DEBUG} || 0;

has [qw(append code prepend template)] => '';
has [qw(auto_escape compiled)];
has capture_end   => 'end';
has capture_start => 'begin';
has comment_mark  => '#';
has encoding      => 'UTF-8';
has escape        => sub { \&Mojo::Util::xss_escape };
has [qw(escape_mark expression_mark trim_mark)] => '=';
has [qw(line_start replace_mark)] => '%';
has name      => 'template';
has namespace => 'Mojo::Template::SandBox';
has tag_start => '<%';
has tag_end   => '%>';
has tree      => sub { [] };

sub build {
  my $self = shift;

  my $tree   = $self->tree;
  my $escape = $self->auto_escape;

  my @blocks = ('');
  my ($i, $capture, $multi);
  while (++$i <= @$tree && (my $next = $tree->[$i])) {
    my ($op, $value) = @{$tree->[$i - 1]};
    push @blocks, '' and next if $op eq 'line';
    my $newline = chomp($value //= '');

    # Text (quote and fix line ending)
    if ($op eq 'text') {
      $value = join "\n", map { quotemeta $_ } split("\n", $value, -1);
      $value .= '\n' if $newline;
      $blocks[-1] .= "\$_M .= \"" . $value . "\";" if length $value;
    }

    # Code or multiline expression
    elsif ($op eq 'code' || $multi) { $blocks[-1] .= $value }

    # Capture end
    elsif ($op eq 'cpen') {
      $blocks[-1] .= 'return Mojo::ByteStream->new($_M) }';

      # No following code
      $blocks[-1] .= ';' if ($next->[1] // '') =~ /^\s*$/;
    }

    # Expression
    if ($op eq 'expr' || $op eq 'escp') {

      # Escaped
      if (!$multi && ($op eq 'escp' && !$escape || $op eq 'expr' && $escape)) {
        $blocks[-1] .= "\$_M .= _escape scalar $value";
      }

      # Raw
      elsif (!$multi) { $blocks[-1] .= "\$_M .= scalar $value" }

      # Multiline
      $multi = !$next || $next->[0] ne 'text';

      # Append semicolon
      $blocks[-1] .= ';' unless $multi || $capture;
    }

    # Capture start
    if ($op eq 'cpst') { $capture = 1 }
    elsif ($capture) {
      $blocks[-1] .= " sub { my \$_M = ''; ";
      $capture = 0;
    }
  }

  return $self->code(join "\n", @blocks)->tree([]);
}

sub compile {
  my $self = shift;

  # Compile with line directive
  return undef unless my $code = $self->code;
  my $compiled = eval $self->_wrap($code);
  $self->compiled($compiled) and return undef unless $@;

  # Use local stacktrace for compile exceptions
  return Mojo::Exception->new($@, [$self->template, $code])->trace->verbose(1);
}

sub interpret {
  my $self = shift;

  # Stacktrace
  local $SIG{__DIE__} = sub {
    CORE::die($_[0]) if ref $_[0];
    Mojo::Exception->throw(shift, [$self->template, $self->code]);
  };

  return undef unless my $compiled = $self->compiled;
  my $output;
  return $output if eval { $output = $compiled->(@_); 1 };

  # Exception with template context
  return Mojo::Exception->new($@, [$self->template])->verbose(1);
}

sub parse {
  my ($self, $template) = @_;

  # Clean start
  $self->template($template)->tree(\my @tree);

  my $tag     = $self->tag_start;
  my $replace = $self->replace_mark;
  my $expr    = $self->expression_mark;
  my $escp    = $self->escape_mark;
  my $cpen    = $self->capture_end;
  my $cmnt    = $self->comment_mark;
  my $cpst    = $self->capture_start;
  my $trim    = $self->trim_mark;
  my $end     = $self->tag_end;
  my $start   = $self->line_start;

  my $line_re
    = qr/^(\s*)\Q$start\E(?:(\Q$replace\E)|(\Q$cmnt\E)|(\Q$expr\E))?(.*)$/;
  my $token_re = qr/
    (
      \Q$tag\E(?:\Q$replace\E|\Q$cmnt\E)                   # Replace
    |
      \Q$tag$expr\E(?:\Q$escp\E)?(?:\s*\Q$cpen\E(?!\w))?   # Expression
    |
      \Q$tag\E(?:\s*\Q$cpen\E(?!\w))?                      # Code
    |
      (?:(?<!\w)\Q$cpst\E\s*)?(?:\Q$trim\E)?\Q$end\E       # End
    )
  /x;
  my $cpen_re = qr/^\Q$tag\E(?:\Q$expr\E)?(?:\Q$escp\E)?\s*\Q$cpen\E(.*)$/;
  my $end_re  = qr/^(?:(\Q$cpst\E)\s*)?(\Q$trim\E)?\Q$end\E$/;

  # Split lines
  my $op = 'text';
  my ($trimming, $capture);
  for my $line (split "\n", $template) {

    # Turn Perl line into mixed line
    if ($op eq 'text' && $line =~ $line_re) {

      # Escaped start
      if ($2) { $line = "$1$start$5" }

      # Comment
      elsif ($3) { $line = "$tag$3 $trim$end" }

      # Expression or code
      else { $line = $4 ? "$1$tag$4$5 $end" : "$tag$5 $trim$end" }
    }

    # Escaped line ending
    $line .= "\n" if $line !~ s/\\\\$/\\\n/ && $line !~ s/\\$//;

    # Mixed line
    for my $token (split $token_re, $line) {

      # Capture end
      ($token, $capture) = ("$tag$1", 1) if $token =~ $cpen_re;

      # End
      if ($op ne 'text' && $token =~ $end_re) {
        $op = 'text';

        # Capture start
        splice @tree, -1, 0, ['cpst'] if $1;

        # Trim left side
        _trim(\@tree) if ($trimming = $2) && @tree > 1;

        # Hint at end
        push @tree, ['text', ''];
      }

      # Code
      elsif ($token eq $tag) { $op = 'code' }

      # Expression
      elsif ($token eq "$tag$expr") { $op = 'expr' }

      # Expression that needs to be escaped
      elsif ($token eq "$tag$expr$escp") { $op = 'escp' }

      # Comment
      elsif ($token eq "$tag$cmnt") { $op = 'cmnt' }

      # Text (comments are just ignored)
      elsif ($op ne 'cmnt') {

        # Replace
        $token = $tag if $token eq "$tag$replace";

        # Trim right side (convert whitespace to line noise)
        if ($trimming && $token =~ s/^(\s+)//) {
          push @tree, ['code', $1];
          $trimming = 0;
        }

        # Token (with optional capture end)
        push @tree, $capture ? ['cpen'] : (), [$op, $token];
        $capture = 0;
      }
    }

    # Optimize successive text lines separated by a newline
    push @tree, ['line'] and next
      if $tree[-4] && $tree[-4][0] ne 'line'
      || (!$tree[-3] || $tree[-3][0] ne 'text' || $tree[-3][1] !~ /\n$/)
      || ($tree[-2][0] ne 'line' || $tree[-1][0] ne 'text');
    $tree[-3][1] .= pop(@tree)->[1];
  }

  return $self;
}

sub render {
  my $self = shift;
  return $self->parse(shift)->build->compile || $self->interpret(@_);
}

sub render_file {
  my ($self, $path) = (shift, shift);

  $self->name($path) unless defined $self->{name};
  my $template = slurp $path;
  my $encoding = $self->encoding;
  croak qq{Template "$path" has invalid encoding}
    if $encoding && !defined($template = decode $encoding, $template);

  return $self->render($template, @_);
}

sub _line {
  my $name = shift->name;
  $name =~ y/"//d;
  return qq{#line @{[shift]} "$name"};
}

sub _trim {
  my $tree = shift;

  # Skip captures
  my $i = $tree->[-2][0] eq 'cpst' || $tree->[-2][0] eq 'cpen' ? -3 : -2;

  # Only trim text
  return unless $tree->[$i][0] eq 'text';

  # Convert whitespace text to line noise
  splice @$tree, $i, 0, ['code', $1] if $tree->[$i][1] =~ s/(\s+)$//;
}

sub _wrap {
  my ($self, $code) = @_;

  # Escape function
  monkey_patch $self->namespace, '_escape', $self->escape;

  # Wrap lines
  my $num = () = $code =~ /\n/g;
  my $head = $self->_line(1);
  $head .= "\npackage @{[$self->namespace]}; use Mojo::Base -strict;";
  $code = "$head sub { my \$_M = ''; @{[$self->prepend]}; { $code\n";
  $code .= $self->_line($num + 1) . "\n@{[$self->append]}; } \$_M };";

  warn "-- Code for @{[$self->name]}\n@{[encode 'UTF-8', $code]}\n\n" if DEBUG;
  return $code;
}

1;

=encoding utf8

=head1 NAME

Mojo::Template - Perl-ish templates!

=head1 SYNOPSIS

  use Mojo::Template;

  # Simple
  my $mt = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
  % use Time::Piece;
  <!DOCTYPE html>
  <html>
    <head><title>Simple</title></head>
    % my $now = localtime;
    <body>Time: <%= $now->hms %></body>
  </html>
  EOF
  say $output;

  # More advanced
  my $output = $mt->render(<<'EOF', 23, 'More advanced');
  % my ($num, $title) = @_;
  %= 5 * 5
  <!DOCTYPE html>
  <html>
    <head><title><%= $title %></title></head>
    <body>
      test 123
      foo <% my $i = $num + 2; %>
      % for (1 .. 23) {
      * some text <%= $i++ %>
      % }
    </body>
  </html>
  EOF
  say $output;

=head1 DESCRIPTION

L<Mojo::Template> is a minimalistic and very Perl-ish template engine,
designed specifically for all those small tasks that come up during big
projects. Like preprocessing a configuration file, generating text from
heredocs and stuff like that.

See L<Mojolicious::Guides::Rendering> for information on how to generate
content with the L<Mojolicious> renderer.

=head1 SYNTAX

For all templates L<strict>, L<warnings>, L<utf8> and Perl 5.10 features are
automatically enabled.

  <% Perl code %>
  <%= Perl expression, replaced with result %>
  <%== Perl expression, replaced with XML escaped result %>
  <%# Comment, useful for debugging %>
  <%% Replaced with "<%", useful for generating templates %>
  % Perl code line, treated as "<% line =%>"
  %= Perl expression line, treated as "<%= line %>"
  %== Perl expression line, treated as "<%== line %>"
  %# Comment line, useful for debugging
  %% Replaced with "%", useful for generating templates

Escaping behavior can be reversed with the L</"auto_escape"> attribute, this
is the default in L<Mojolicious> C<.ep> templates for example.

  <%= Perl expression, replaced with XML escaped result %>
  <%== Perl expression, replaced with result %>

L<Mojo::ByteStream> objects are always excluded from automatic escaping.

  % use Mojo::ByteStream 'b';
  <%= b('<div>excluded!</div>') %>

Whitespace characters around tags can be trimmed by adding an additional equal
sign to the end of a tag.

  <%= All whitespace characters around this expression will be trimmed =%>

Newline characters can be escaped with a backslash.

  This is <%= 1 + 1 %> a\
  single line

And a backslash in front of a newline character can be escaped with another
backslash.

  This will <%= 1 + 1 %> result\\
  in multiple\\
  lines

You can capture whole template blocks for reuse later with the C<begin> and
C<end> keywords.

  <% my $block = begin %>
    <% my $name = shift; =%>
    Hello <%= $name %>.
  <% end %>
  <%= $block->('Baerbel') %>
  <%= $block->('Wolfgang') %>

Perl lines can also be indented freely.

  % my $block = begin
    % my $name = shift;
    Hello <%= $name %>.
  % end
  %= $block->('Baerbel')
  %= $block->('Wolfgang')

L<Mojo::Template> templates get compiled to a Perl subroutine, that means you
can access arguments simply via C<@_>.

  % my ($foo, $bar) = @_;
  % my $x = shift;
  test 123 <%= $foo %>

The compilation of templates to Perl code can make debugging a bit tricky, but
L<Mojo::Template> will return L<Mojo::Exception> objects that stringify to
error messages with context.

  Bareword "xx" not allowed while "strict subs" in use at template line 4.
  2: </head>
  3: <body>
  4: % my $i = 2; xx
  5: %= $i * 2
  6: </body>

=head1 ATTRIBUTES

L<Mojo::Template> implements the following attributes.

=head2 auto_escape

  my $bool = $mt->auto_escape;
  $mt      = $mt->auto_escape($bool);

Activate automatic escaping.

=head2 append

  my $code = $mt->append;
  $mt      = $mt->append('warn "Processed template"');

Append Perl code to compiled template. Note that this code should not contain
newline characters, or line numbers in error messages might end up being
wrong.

=head2 capture_end

  my $end = $mt->capture_end;
  $mt     = $mt->capture_end('end');

Keyword indicating the end of a capture block, defaults to C<end>.

  <% my $block = begin %>
    Some data!
  <% end %>

=head2 capture_start

  my $start = $mt->capture_start;
  $mt       = $mt->capture_start('begin');

Keyword indicating the start of a capture block, defaults to C<begin>.

  <% my $block = begin %>
    Some data!
  <% end %>

=head2 code

  my $code = $mt->code;
  $mt      = $mt->code($code);

Perl code for template.

=head2 comment_mark

  my $mark = $mt->comment_mark;
  $mt      = $mt->comment_mark('#');

Character indicating the start of a comment, defaults to C<#>.

  <%# This is a comment %>

=head2 compiled

  my $compiled = $mt->compiled;
  $mt          = $mt->compiled($compiled);

Compiled template code.

=head2 encoding

  my $encoding = $mt->encoding;
  $mt          = $mt->encoding('UTF-8');

Encoding used for template files.

=head2 escape

  my $cb = $mt->escape;
  $mt    = $mt->escape(sub {...});

A callback used to escape the results of escaped expressions, defaults to
L<Mojo::Util/"xss_escape">.

  $mt->escape(sub {
    my $str = shift;
    return reverse $str;
  });

=head2 escape_mark

  my $mark = $mt->escape_mark;
  $mt      = $mt->escape_mark('=');

Character indicating the start of an escaped expression, defaults to C<=>.

  <%== $foo %>

=head2 expression_mark

  my $mark = $mt->expression_mark;
  $mt      = $mt->expression_mark('=');

Character indicating the start of an expression, defaults to C<=>.

  <%= $foo %>

=head2 line_start

  my $start = $mt->line_start;
  $mt       = $mt->line_start('%');

Character indicating the start of a code line, defaults to C<%>.

  % $foo = 23;

=head2 name

  my $name = $mt->name;
  $mt      = $mt->name('foo.mt');

Name of template currently being processed, defaults to C<template>. Note that
this value should not contain quotes or newline characters, or error messages
might end up being wrong.

=head2 namespace

  my $namespace = $mt->namespace;
  $mt           = $mt->namespace('main');

Namespace used to compile templates, defaults to C<Mojo::Template::SandBox>.
Note that namespaces should only be shared very carefully between templates,
since functions and global variables will not be cleared automatically.

=head2 prepend

  my $code = $mt->prepend;
  $mt      = $mt->prepend('my $self = shift;');

Prepend Perl code to compiled template. Note that this code should not contain
newline characters, or line numbers in error messages might end up being
wrong.

=head2 replace_mark

  my $mark = $mt->replace_mark;
  $mt      = $mt->replace_mark('%');

Character used for escaping the start of a tag or line, defaults to C<%>.

  <%% my $foo = 23; %>

=head2 tag_start

  my $start = $mt->tag_start;
  $mt       = $mt->tag_start('<%');

Characters indicating the start of a tag, defaults to C<E<lt>%>.

  <% $foo = 23; %>

=head2 tag_end

  my $end = $mt->tag_end;
  $mt     = $mt->tag_end('%>');

Characters indicating the end of a tag, defaults to C<%E<gt>>.

  <%= $foo %>

=head2 template

  my $template = $mt->template;
  $mt          = $mt->template($template);

Raw unparsed template.

=head2 tree

  my $tree = $mt->tree;
  $mt      = $mt->tree([['text', 'foo'], ['line']]);

Template in parsed form. Note that this structure should only be used very
carefully since it is very dynamic.

=head2 trim_mark

  my $mark = $mt->trim_mark;
  $mt      = $mt->trim_mark('-');

Character activating automatic whitespace trimming, defaults to C<=>.

  <%= $foo =%>

=head1 METHODS

L<Mojo::Template> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 build

  $mt = $mt->build;

Build Perl L</"code"> from L</"tree">.

=head2 compile

  my $exception = $mt->compile;

Compile Perl L</"code"> for template.

=head2 interpret

  my $output = $mt->interpret;
  my $output = $mt->interpret(@args);

Interpret L</"compiled"> template code.

  # Reuse template
  say $mt->render('Hello <%= $_[0] %>!', 'Bender');
  say $mt->interpret('Fry');
  say $mt->interpret('Leela');

=head2 parse

  $mt = $mt->parse($template);

Parse template into L</"tree">.

=head2 render

  my $output = $mt->render($template);
  my $output = $mt->render($template, @args);

Render template.

  say $mt->render('Hello <%= $_[0] %>!', 'Bender');

=head2 render_file

  my $output = $mt->render_file('/tmp/foo.mt');
  my $output = $mt->render_file('/tmp/foo.mt', @args);

Render template file.

=head1 DEBUGGING

You can set the C<MOJO_TEMPLATE_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_TEMPLATE_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
