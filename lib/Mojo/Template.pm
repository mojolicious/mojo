package Mojo::Template;
use Mojo::Base -base;

use Carp 'croak';
use IO::Handle;
use Mojo::ByteStream;
use Mojo::Exception;
use Mojo::Util qw/decode encode/;

# "If for any reason you're not completely satisfied, I hate you."
has [qw/auto_escape compiled/];
has [qw/append code prepend template/] => '';
has capture_end   => 'end';
has capture_start => 'begin';
has comment_mark  => '#';
has encoding      => 'UTF-8';
has [qw/escape_mark expression_mark trim_mark/] => '=';
has [qw/line_start replace_mark/] => '%';
has name      => 'template';
has namespace => 'Mojo::Template::SandBox';
has tag_start => '<%';
has tag_end   => '%>';
has tree      => sub { [] };

# Helpers
my $HELPERS = <<'EOF';
use Mojo::Util;
no warnings 'redefine';
sub _escape {
  return $_[0] if ref $_[0] eq 'Mojo::ByteStream';
  no warnings 'uninitialized';
  Mojo::Util::xml_escape "$_[0]";
}
use Mojo::Base -strict;
EOF
$HELPERS =~ s/\n//g;

sub build {
  my $self = shift;

  # Lines
  my (@lines, $cpst);
  my $multi = 0;
  for my $line (@{$self->tree}) {

    # New line
    push @lines, '';
    for (my $j = 0; $j < @{$line}; $j += 2) {
      my $type    = $line->[$j];
      my $value   = $line->[$j + 1] || '';
      my $newline = chomp $value;

      # Capture end
      if ($type eq 'cpen') {

        # End block
        $lines[-1] .= 'return Mojo::ByteStream->new($_M) }';

        # No following code
        my $next = $line->[$j + 3];
        $lines[-1] .= ';' if !defined $next || $next =~ /^\s*$/;
      }

      # Text
      if ($type eq 'text') {

        # Quote and fix line ending
        $value = quotemeta($value);
        $value .= '\n' if $newline;
        $lines[-1] .= "\$_M .= \"" . $value . "\";" if length $value;
      }

      # Code or multiline expression
      if ($type eq 'code' || $multi) { $lines[-1] .= "$value" }

      # Expression
      if ($type ~~ [qw/expr escp/]) {

        # Start
        unless ($multi) {

          # Escaped
          my $a = $self->auto_escape;
          if (($type eq 'escp' && !$a) || ($type eq 'expr' && $a)) {
            $lines[-1] .= "\$_M .= _escape";
            $lines[-1] .= " scalar $value" if length $value;
          }

          # Raw
          else { $lines[-1] .= "\$_M .= scalar $value" }
        }

        # Multiline
        $multi = ($line->[$j + 2] || '') eq 'text'
          && ($line->[$j + 3] || '') eq '' ? 0 : 1;

        # Append semicolon
        $lines[-1] .= ';' if !$multi && !$cpst;
      }

      # Capture start
      if ($cpst) {
        $lines[-1] .= $cpst;
        $cpst = undef;
      }
      $cpst = " sub { my \$_M = ''; " if $type eq 'cpst';
    }
  }

  # Closure
  my $first = $lines[0] ||= '';
  $lines[0] = 'package ' . $self->namespace . "; $HELPERS ";
  $lines[0]  .= "sub { my \$_M = ''; " . $self->prepend . "; do { $first";
  $lines[-1] .= $self->append . "; \$_M; } };";

  return $self->code(join "\n", @lines)->tree([]);
}

sub compile {
  my $self = shift;

  # Compile
  return unless my $code = $self->code;
  my $compiled = eval $code;

  # Use local stacktrace for compile exceptions
  return Mojo::Exception->new($@, [$self->template, $code], $self->name)
    ->trace->verbose(1)
    if $@;

  $self->compiled($compiled) and return;
}

sub interpret {
  my $self = shift;

  # Stacktrace
  local $SIG{__DIE__} = sub {
    CORE::die($_[0]) if ref $_[0];
    Mojo::Exception->throw(shift, [$self->template, $self->code], $self->name);
  };

  # Interpret
  return unless my $compiled = $self->compiled;
  my $output = eval { $compiled->(@_) };
  return $@
    ? Mojo::Exception->new($@, [$self->template], $self->name)->verbose(1)
    : $output;
}

# "I am so smart! I am so smart! S-M-R-T! I mean S-M-A-R-T..."
sub parse {
  my ($self, $tmpl) = @_;

  # Clean start
  delete $self->template($tmpl)->{tree};

  # Token
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

  # Precompile
  my $token_re = qr/
    (
      \Q$tag$replace\E                       # Replace
    |
      \Q$tag$expr$escp\E\s*\Q$cpen\E(?!\w)   # Escaped expression (end)
    |
      \Q$tag$expr$escp\E                     # Escaped expression
    |
      \Q$tag$expr\E\s*\Q$cpen\E(?!\w)        # Expression (end)
    |
      \Q$tag$expr\E                          # Expression
    |
      \Q$tag$cmnt\E                          # Comment
    |
      \Q$tag\E\s*\Q$cpen\E(?!\w)             # Code (end)
    |
      \Q$tag\E                               # Code
    |
      (?<!\w)\Q$cpst\E\s*\Q$trim$end\E       # Trim end (start)
    |
      \Q$trim$end\E                          # Trim end
    |
      (?<!\w)\Q$cpst\E\s*\Q$end\E            # End (start)
    |
      \Q$end\E                               # End
    )
  /x;
  my $cpen_re = qr/^(\Q$tag\E)(?:\Q$expr\E)?(?:\Q$escp\E)?\s*\Q$cpen\E/;
  my $end_re  = qr/^(?:(\Q$cpst\E)\s*)?(\Q$trim\E)?\Q$end\E$/;

  # Split lines
  my $state = 'text';
  my @capture_token;
  my $trimming = 0;
  for my $line (split /\n/, $tmpl) {
    $trimming = 0 if $state eq 'text';

    # Perl line
    if ($state eq 'text' && $line !~ s/^(\s*)\Q$start$replace\E/$1$start/) {
      $line =~ s/^(\s*)\Q$start\E(\Q$expr\E)?//
        and $line = $2 ? "$1$tag$2$line $end" : "$tag$line $trim$end";
    }

    # Escaped line ending
    if ($line =~ /(\\+)$/) {
      my $len = length $1;

      # Newline
      if ($len == 1) { $line =~ s/\\$// }

      # Backslash
      elsif ($len > 1) { $line =~ s/\\\\$/\\\n/ }
    }

    # Normal line ending
    else { $line .= "\n" }

    # Tokenize
    my @token;
    for my $token (split $token_re, $line) {

      # Capture end
      @capture_token = ('cpen', undef) if $token =~ s/$cpen_re/$1/;

      # End
      if ($state ne 'text' && $token =~ $end_re) {
        $state = 'text';

        # Capture start
        splice @token, -2, 0, 'cpst', undef if $1;

        # Trim previous text
        if ($2) {
          $trimming = 1;
          $self->_trim(\@token);
        }

        # Hint at end
        push @token, 'text', '';
      }

      # Code
      elsif ($token =~ /^\Q$tag\E$/) { $state = 'code' }

      # Expression
      elsif ($token =~ /^\Q$tag$expr\E$/) { $state = 'expr' }

      # Expression that needs to be escaped
      elsif ($token =~ /^\Q$tag$expr$escp\E$/) { $state = 'escp' }

      # Comment
      elsif ($token =~ /^\Q$tag$cmnt\E$/) { $state = 'cmnt' }

      # Value
      else {

        # Replace
        $token = $tag if $token eq "$tag$replace";

        # Convert whitespace text to line noise
        if ($trimming && $token =~ s/^(\s+)//) {
          push @token, 'code', $1;
          $trimming = 0;
        }

        # Comments are ignored
        next if $state eq 'cmnt';
        push @token, @capture_token, $state, $token;
        @capture_token = ();
      }
    }
    push @{$self->tree}, \@token;
  }

  return $self;
}

sub render {
  my $self = shift;
  my $e    = $self->parse(shift)->build->compile;
  return $e ? $e : $self->interpret(@_);
}

sub render_file {
  my ($self, $path) = (shift, shift);

  # Slurp file
  $self->name($path) unless defined $self->{name};
  croak qq/Can't open template "$path": $!/ unless open my $file, '<', $path;
  my $tmpl = '';
  while ($file->sysread(my $buffer, 131072, 0)) { $tmpl .= $buffer }

  # Decode and render
  if (my $encoding = $self->encoding) {
    croak qq/Template "$path" has invalid encoding./
      unless defined($tmpl = decode $encoding, $tmpl);
  }
  return $self->render($tmpl, @_);
}

sub render_file_to_file {
  my ($self, $spath, $tpath) = (shift, shift, shift);
  my $output = $self->render_file($spath, @_);
  return ref $output ? $output : $self->_write_file($tpath, $output);
}

sub render_to_file {
  my ($self, $tmpl, $path) = (shift, shift, shift);
  my $output = $self->render($tmpl, @_);
  return ref $output ? $output : $self->_write_file($path, $output);
}

sub _trim {
  my ($self, $line) = @_;

  # Walk line backwards
  for (my $j = @$line - 4; $j >= 0; $j -= 2) {

    # Skip capture
    next if $line->[$j] eq 'cpst' || $line->[$j] eq 'cpen';

    # Only trim text
    return unless $line->[$j] eq 'text';

    # Convert whitespace text to line noise
    my $value = $line->[$j + 1];
    if ($line->[$j + 1] =~ s/(\s+)$//) {
      $value = $line->[$j + 1];
      splice @$line, $j, 0, 'code', $1;
    }

    # Text left
    return if length $value;
  }
}

sub _write_file {
  my ($self, $path, $output) = @_;

  # Encode and write to file
  croak qq/Can't open file "$path": $!/ unless open my $file, '>', $path;
  $output = encode $self->encoding, $output if $self->encoding;
  croak qq/Can't write to file "$path": $!/
    unless defined $file->syswrite($output);

  return;
}

1;

=head1 NAME

Mojo::Template - Perl-ish templates!

=head1 SYNOPSIS

  use Mojo::Template;
  my $mt = Mojo::Template->new;

  # Simple
  my $output = $mt->render(<<'EOF');
  <!DOCTYPE html>
  <html>
    <head><title>Simple</title></head>
    <body>Time: <%= localtime(time) %></body>
  </html>
  EOF
  say $output;

  # More complicated
  my $output = $mt->render(<<'EOF', 23, 'foo bar');
  %= 5 * 5
  % my ($number, $text) = @_;
  test 123
  foo <% my $i = $number + 2; %>
  % for (1 .. 23) {
  * some text <%= $i++ %>
  % }
  EOF
  say $output;

=head1 DESCRIPTION

L<Mojo::Template> is a minimalistic and very Perl-ish template engine,
designed specifically for all those small tasks that come up during big
projects. Like preprocessing a configuration file, generating text from
heredocs and stuff like that.

  <% Perl code %>
  <%= Perl expression, replaced with result %>
  <%== Perl expression, replaced with XML escaped result %>
  <%# Comment, useful for debugging %>
  <%% Replaced with "<%", useful for generating templates %>
  % Perl code line, treated as "<% line =%>"
  %= Perl expression line, treated as "<%= line %>"
  %== Perl expression line, treated as "<%== line %>"
  %# Comment line, treated as "<%# line =%>"
  %% Replaced with "%", useful for generating templates

=head2 Automatic escaping

Escaping behavior can be reversed with the C<auto_escape> attribute, this is
the default in L<Mojolicious> C<.ep> templates for example.

  <%= Perl expression, replaced with XML escaped result %>
  <%== Perl expression, replaced with result %>

L<Mojo::ByteStream> objects are always excluded from automatic escaping.

  <%= Mojo::ByteStream->new('<div>excluded!</div>') %>

=head2 Trimming

Whitespace characters around tags can be trimmed with a special tag ending.

  <%= All whitespace characters around this expression will be trimmed =%>

=head2 Blocks

You can capture whole template blocks for reuse later with the C<begin> and
C<end> keywords.

  <% my $block = begin %>
    <% my $name = shift; =%>
    Hello <%= $name %>.
  <% end %>
  <%= $block->('Baerbel') %>
  <%= $block->('Wolfgang') %>

=head2 Indentation

Perl lines can also be indented freely.

  % my $block = begin
    % my $name = shift;
    Hello <%= $name %>.
  % end
  %= $block->('Baerbel')
  %= $block->('Wolfgang')

=head2 Arguments

L<Mojo::Template> templates work just like Perl subs (actually they get
compiled to a Perl sub internally). That means you can access arguments simply
via C<@_>.

  % my ($foo, $bar) = @_;
  % my $x = shift;
  test 123 <%= $foo %>

=head2 More escaping

You can use escaped tags and lines to generate templates.

  %% my $number = <%= 20 + 3 %>;
  The number is <%%= $number %>

A newline can be escaped with a backslash.

  This is <%= 23 * 3 %> a\
  single line

And a backslash in front of a newline can be escaped with another backslash.

  % use Data::Dumper;
  This will\\
  result <%=  Dumper {foo => 'bar'} %>\\
  in multiple lines

=head2 Exceptions

Templates get compiled to Perl code internally, this can make debugging a bit
tricky. But L<Mojo::Template> will return L<Mojo::Exception> objects that
stringify to error messages with context.

  Bareword "xx" not allowed while "strict subs" in use at template line 4.
  2: </head>
  3: <body>
  4: % my $i = 2; xx
  5: %= $i * 2
  6: </body>

=head2 Caching

L<Mojo::Template> does not support caching by itself, but you can easily build
a wrapper around it.

  # Compile and store code somewhere
  my $mt = Mojo::Template->new;
  $mt->parse($template);
  $mt->build;
  my $code = $mt->code;

  # Load code and template (template for debug trace only)
  $mt->template($template);
  $mt->code($code);
  $mt->compile;
  my $output = $mt->interpret(@args);

=head1 ATTRIBUTES

L<Mojo::Template> implements the following attributes.

=head2 C<auto_escape>

  my $auto_escape = $mt->auto_escape;
  $mt             = $mt->auto_escape(1);

Activate automatic XML escaping.

=head2 C<append>

  my $code = $mt->append;
  $mt      = $mt->append('warn "Processed template"');

Append Perl code to compiled template.

=head2 C<capture_end>

  my $capture_end = $mt->capture_end;
  $mt             = $mt->capture_end('end');

Keyword indicating the end of a capture block, defaults to C<end>.

  <% my $block = begin %>
    Some data!
  <% end %>

=head2 C<capture_start>

  my $capture_start = $mt->capture_start;
  $mt               = $mt->capture_start('begin');

Keyword indicating the start of a capture block, defaults to C<begin>.

  <% my $block = begin %>
    Some data!
  <% end %>

=head2 C<code>

  my $code = $mt->code;
  $mt      = $mt->code($code);

Compiled template code.

=head2 C<comment_mark>

  my $comment_mark = $mt->comment_mark;
  $mt              = $mt->comment_mark('#');

Character indicating the start of a comment, defaults to C<#>.

  <%# This is a comment %>

=head2 C<encoding>

  my $encoding = $mt->encoding;
  $mt          = $mt->encoding('UTF-8');

Encoding used for template files.

=head2 C<escape_mark>

  my $escape_mark = $mt->escape_mark;
  $mt             = $mt->escape_mark('=');

Character indicating the start of an escaped expression, defaults to C<=>.

  <%== $foo %>

=head2 C<expression_mark>

  my $expression_mark = $mt->expression_mark;
  $mt                 = $mt->expression_mark('=');

Character indicating the start of an expression, defaults to C<=>.

  <%= $foo %>

=head2 C<line_start>

  my $line_start = $mt->line_start;
  $mt            = $mt->line_start('%');

Character indicating the start of a code line, defaults to C<%>.

  % $foo = 23;

=head2 C<name>

  my $name = $mt->name;
  $mt      = $mt->name('foo.mt');

Name of template currently being processed, defaults to C<template>. Note that
this method is attribute and might change without warning!

=head2 C<namespace>

  my $namespace = $mt->namespace;
  $mt           = $mt->namespace('main');

Namespace used to compile templates, defaults to C<Mojo::Template::SandBox>.

=head2 C<prepend>

  my $code = $mt->prepend;
  $mt      = $mt->prepend('my $self = shift;');

Prepend Perl code to compiled template.

=head2 C<replace_mark>

  my $replace_mark = $mt->replace_mark;
  $mt              = $mt->replace_mark('%');

Character used for escaping the start of a tag or line, defaults to C<%>.

  <%% my $foo = 23; %>

=head2 C<tag_start>

  my $tag_start = $mt->tag_start;
  $mt           = $mt->tag_start('<%');

Characters indicating the start of a tag, defaults to C<E<lt>%>.

  <% $foo = 23; %>

=head2 C<tag_end>

  my $tag_end = $mt->tag_end;
  $mt         = $mt->tag_end('%>');

Characters indicating the end of a tag, defaults to C<%E<gt>>.

  <%= $foo %>

=head2 C<template>

  my $template = $mt->template;
  $mt          = $mt->template($template);

Raw template.

=head2 C<tree>

  my $tree = $mt->tree;
  $mt      = $mt->tree($tree);

Parsed tree.

=head2 C<trim_mark>

  my $trim_mark = $mt->trim_mark;
  $mt           = $mt->trim_mark('-');

Character activating automatic whitespace trimming, defaults to C<=>.

  <%= $foo =%>

=head1 METHODS

L<Mojo::Template> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $mt = Mojo::Template->new;

Construct a new L<Mojo::Template> object.

=head2 C<build>

  $mt = $mt->build;

Build template.

=head2 C<compile>

  my $exception = $mt->compile;

Compile template.

=head2 C<interpret>

  my $output = $mt->interpret;
  my $output = $mt->interpret(@args);

Interpret template.

=head2 C<parse>

  $mt = $mt->parse($template);

Parse template.

=head2 C<render>

  my $output = $mt->render($template);
  my $output = $mt->render($template, @args);

Render template.

=head2 C<render_file>

  my $output = $mt->render_file($template_file);
  my $output = $mt->render_file($template_file, @args);

Render template file.

=head2 C<render_file_to_file>

  my $exception = $mt->render_file_to_file($template_file, $output_file);
  my $exception
    = $mt->render_file_to_file($template_file, $output_file, @args);

Render template file to a specific file.

=head2 C<render_to_file>

  my $exception = $mt->render_to_file($template, $output_file);
  my $exception = $mt->render_to_file($template, $output_file, @args);

Render template to a specific file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
