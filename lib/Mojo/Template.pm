package Mojo::Template;
use Mojo::Base -base;

use Carp 'croak';
use Encode qw/decode encode/;
use IO::File;
use Mojo::ByteStream;
use Mojo::Exception;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

# "If for any reason you're not completely satisfied, I hate you."
has [qw/auto_escape compiled/];
has [qw/append code prepend/] => '';
has capture_end     => 'end';
has capture_start   => 'begin';
has comment_mark    => '#';
has encoding        => 'UTF-8';
has escape_mark     => '=';
has expression_mark => '=';
has line_start      => '%';
has name            => 'template';
has namespace       => 'Mojo::Template::SandBox';
has tag_start       => '<%';
has tag_end         => '%>';
has template        => '';
has tree            => sub { [] };
has trim_mark       => '=';

# Helpers
my $HELPERS = <<'EOF';
use Mojo::ByteStream 'b';
use Mojo::Util;
no strict 'refs'; no warnings 'redefine';
sub capture;
*capture = sub { shift->(@_) };
sub escape;
*escape = sub {
  return "$_[0]" if ref $_[0] && ref $_[0] eq 'Mojo::ByteStream';
  my $v;
  {
    no warnings 'uninitialized';
    $v = "$_[0]";
  }
  Mojo::Util::xml_escape $v;
  $v;
};
use strict; use warnings;
EOF
$HELPERS =~ s/\n//g;

sub build {
  my $self = shift;

  # Compile
  my @lines;
  my $cpst;
  my $multi = 0;
  for my $line (@{$self->tree}) {

    # New line
    push @lines, '';
    for (my $j = 0; $j < @{$line}; $j += 2) {
      my $type  = $line->[$j];
      my $value = $line->[$j + 1];

      # Need to fix line ending
      $value ||= '';
      my $newline = chomp $value;

      # Capture end
      if ($type eq 'cpen') {

        # End block
        $lines[-1] .= 'return b($_M) }';

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
      if ($type eq 'expr' || $type eq 'escp') {

        # Start
        unless ($multi) {

          # Escaped
          my $a = $self->auto_escape;
          if (($type eq 'escp' && !$a) || ($type eq 'expr' && $a)) {
            $lines[-1] .= "\$_M .= escape";
            $lines[-1] .= " +$value" if length $value;
          }

          # Raw
          else { $lines[-1] .= "\$_M .= $value" }
        }

        # Multiline
        $multi = ($line->[$j + 2] || '') eq 'text'
          && ($line->[$j + 3] || '') eq '' ? 0 : 1;

        # Append semicolon
        $lines[-1] .= ';' if !$multi && !$cpst;
      }

      # Capture started
      if ($cpst) {
        $lines[-1] .= $cpst;
        $cpst = undef;
      }

      # Capture start
      if ($type eq 'cpst') {

        # Start block
        $cpst = " sub { my \$_M = ''; ";
      }
    }
  }

  # Wrap
  my $prepend   = $self->prepend;
  my $append    = $self->append;
  my $namespace = $self->namespace;
  $lines[0] ||= '';
  $lines[0] =
    "package $namespace; $HELPERS sub { my \$_M = ''; $prepend; do {"
    . $lines[0];
  $lines[-1] .= "$append; \$_M; } };";

  # Done
  $self->code(join "\n", @lines);
  $self->tree([]);

  return $self;
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

  $self->compiled($compiled);
  return;
}

sub interpret {
  my $self = shift;

  # Compile
  unless ($self->compiled) {
    my $e = $self->compile;
    return $e if ref $e;
  }
  my $compiled = $self->compiled;
  return unless $compiled;

  # Stacktrace
  local $SIG{__DIE__} = local $SIG{__DIE__} = sub {
    CORE::die($_[0]) if ref $_[0];
    Mojo::Exception->throw(shift, [$self->template, $self->code],
      $self->name);
  };

  # Interpret
  my $output = eval { $compiled->(@_) };
  $output =
    Mojo::Exception->new($@, [$self->template], $self->name)->verbose(1)
    if $@;

  return $output;
}

# "I am so smart! I am so smart! S-M-R-T! I mean S-M-A-R-T..."
sub parse {
  my ($self, $tmpl) = @_;
  $self->template($tmpl);

  # Clean start
  delete $self->{tree};

  # Tags
  my $line_start    = quotemeta $self->line_start;
  my $tag_start     = quotemeta $self->tag_start;
  my $tag_end       = quotemeta $self->tag_end;
  my $cmnt          = quotemeta $self->comment_mark;
  my $escp          = quotemeta $self->escape_mark;
  my $expr          = quotemeta $self->expression_mark;
  my $trim          = quotemeta $self->trim_mark;
  my $capture_start = quotemeta $self->capture_start;
  my $capture_end   = quotemeta $self->capture_end;

  # Mixed
  my $mixed_re = qr/
    (
    $tag_start$expr$escp\s*$capture_end   # Escaped expression (end)
    |
    $tag_start$expr$escp                  # Escaped expression
    |
    $tag_start$expr\s*$capture_end        # Expression (end)
    |
    $tag_start$expr                       # Expression
    |
    $tag_start$cmnt\s*$capture_end        # Comment (end)
    |
    $tag_start$cmnt                       # Comment
    |
    $tag_start\s*$capture_end             # Code (end)
    |
    $tag_start                            # Code
    |
    $capture_start\s*$trim$tag_end        # Trim end (start)
    |
    $trim$tag_end                         # Trim end
    |
    $capture_start\s*$tag_end             # End (start)
    |
    $tag_end                              # End
    )
  /x;

  # Capture end regex
  my $capture_end_re = qr/
    ^(
    $tag_start        # Start
    )
    (?:
    $expr             # Expression
    )?
    (?:
    $escp             # Escaped expression
    )?
    \s*$capture_end   # (end)
  /x;

  # Tag end regex
  my $end_re = qr/
    ^(
    $capture_start\s*$trim$tag_end   # Trim end (start)
    )|(
    $capture_start\s*$tag_end        # End (start)
    )|(
    $trim$tag_end                    # Trim end
    )|
    $tag_end                         # End
    $
  /x;

  # Perl line regex
  my $line_re = qr/
    ^
    (\s*)
    $line_start            # Line start
    ($expr)?               # Expression
    ($escp)?               # Escaped expression
    (\s*$capture_end)?     # End
    ([^\#\>]{1}.*?)?       # Code
    ($capture_start\s*)?   # Start
    $
  /x;

  # Tokenize
  my $state = 'text';
  my @capture_token;
  my $trimming = 0;
  for my $line (split /\n/, $tmpl) {

    # Perl line
    if ($line =~ /$line_re/) {
      my @token = ();

      # Capture end
      push @token, 'cpen', undef if $4;

      # Capture start
      push @token, 'cpst', undef if $6;

      # Expression
      if ($2) {
        unshift @token, 'text', $1;
        push @token, $3 ? 'escp' : 'expr', $5;

        # Hint at end
        push @token, 'text', '';

        # Line ending
        push @token, 'text', "\n";
      }

      # Code
      else { push @token, 'code', $5 }

      push @{$self->tree}, \@token;
      next;
    }

    # Comment line, dummy token needed for line count
    if ($line =~ /^\s*$line_start$cmnt(.+)?$/) {
      next;
    }

    # Escaped line ending
    if ($line =~ /(\\+)$/) {
      my $len = length $1;

      # Newline escaped
      if ($len == 1) { $line =~ s/\\$// }

      # Backslash escaped
      if ($len >= 2) {
        $line =~ s/\\\\$/\\/;
        $line .= "\n";
      }
    }

    # Normal line ending
    else { $line .= "\n" }

    # Mixed line
    my @token;
    for my $token (split /$mixed_re/, $line) {

      # Done trimming
      $trimming = 0 if $trimming && $state ne 'text';

      # Capture end
      @capture_token = ('cpen', undef)
        if $token =~ s/$capture_end_re/$1/;

      # End
      if ($state ne 'text' && $token =~ /$end_re/) {

        # Capture start
        splice @token, -2, 0, 'cpst', undef if $1 || $2;

        # Trim previous text
        if ($1 || $3) {
          $trimming = 1;

          # Trim current line
          unless ($self->_trim_line(\@token, 4)) {

            # Trim previous lines
            for my $l (reverse @{$self->tree}) {
              last if $self->_trim_line($l);
            }
          }
        }

        # Hint at end
        push @token, 'text', '';

        # Back to business as usual
        $state = 'text';
      }

      # Code
      elsif ($token =~ /^$tag_start$/) { $state = 'code' }

      # Expression
      elsif ($token =~ /^$tag_start$expr$/) {
        $state = 'expr';
      }

      # Expression that needs to be escaped
      elsif ($token =~ /^$tag_start$expr$escp$/) {
        $state = 'escp';
      }

      # Comment
      elsif ($token =~ /^$tag_start$cmnt$/) { $state = 'cmnt' }

      # Value
      else {

        # Trimming
        if ($trimming) {
          if ($token =~ s/^(\s+)//) {

            # Convert whitespace text to line noise
            push @token, 'code', $1;

            # Done with trimming
            $trimming = 0 if length $token;
          }
        }

        # Comments are ignored
        next if $state eq 'cmnt';

        # Store value
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
  my $tmpl = shift;

  # Parse
  $self->parse($tmpl);

  # Build
  $self->build;

  # Compile
  my $e = $self->compile;
  return $e if $e;

  # Interpret
  return $self->interpret(@_);
}

sub render_file {
  my $self = shift;
  my $path = shift;

  # Slurp file
  $self->name($path) unless defined $self->{name};
  croak "Can't open template '$path': $!"
    unless my $file = IO::File->new("< $path");
  my $tmpl = '';
  while ($file->sysread(my $buffer, CHUNK_SIZE, 0)) {
    $tmpl .= $buffer;
  }

  # Decode and render
  $tmpl = decode($self->encoding, $tmpl) if $self->encoding;
  return $self->render($tmpl, @_);
}

sub render_file_to_file {
  my $self  = shift;
  my $spath = shift;
  my $tpath = shift;

  # Render
  my $output = $self->render_file($spath, @_);
  return $output if ref $output;

  # Write to file
  return $self->_write_file($tpath, $output);
}

sub render_to_file {
  my $self = shift;
  my $tmpl = shift;
  my $path = shift;

  # Render
  my $output = $self->render($tmpl, @_);
  return $output if ref $output;

  # Write to file
  return $self->_write_file($path, $output);
}

sub _trim_line {
  my ($self, $line, $offset) = @_;

  # Walk line backwards
  $offset ||= 2;
  for (my $j = @$line - $offset; $j >= 0; $j -= 2) {

    # Skip capture
    next if $line->[$j] eq 'cpst' || $line->[$j] eq 'cpen';

    # Only trim text
    return 1 unless $line->[$j] eq 'text';

    # Trim
    my $value = $line->[$j + 1];
    if ($line->[$j + 1] =~ s/(\s+)$//) {

      # Value
      $value = $line->[$j + 1];

      # Convert whitespace text to line noise
      splice @$line, $j, 0, 'code', $1;
    }

    # Text left
    return 1 if length $value;
  }

  return;
}

sub _write_file {
  my ($self, $path, $output) = @_;

  # Encode and write to file
  croak "Can't open file '$path': $!"
    unless my $file = IO::File->new("> $path");
  $output = encode($self->encoding, $output) if $self->encoding;
  $file->syswrite($output) or croak "Can't write to file '$path': $!";

  return;
}

1;
__END__

=head1 NAME

Mojo::Template - Perlish Templates!

=head1 SYNOPSIS

  use Mojo::Template;
  my $mt = Mojo::Template->new;

  # Simple
  my $output = $mt->render(<<'EOF');
  <!doctype html><html>
    <head><title>Simple</title></head>
    <body>Time: <%= localtime(time) %></body>
  </html>
  EOF
  print $output;

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
  print $output;

=head1 DESCRIPTION

L<Mojo::Template> is a minimalistic and very Perl-ish template engine,
designed specifically for all those small tasks that come up during big
projects.
Like preprocessing a config file, generating text from heredocs and stuff
like that.

  <% Inline Perl %>
  <%= Perl expression, replaced with result %>
  <%== Perl expression, replaced with XML escaped result %>
  <%# Comment, useful for debugging %>
  % Perl line
  %= Perl expression line, replaced with result
  %== Perl expression line, replaced with XML escaped result
  %# Comment line, useful for debugging

Automatic escaping behavior can be reversed with the C<auto_escape>
attribute, this is the default in L<Mojolicious> C<.ep> templates for
example.

  <%= Perl expression, replaced with XML escaped result %>
  <%== Perl expression, replaced with result %>
  %= Perl expression line, replaced with XML escaped result
  %== Perl expression line, replaced with result

L<Mojo::ByteStream> objects are always excluded from automatic escaping.

  <%= b('<div>excluded!</div>') %>

Whitespace characters around tags can be trimmed with a special tag ending.

  <%= All whitespace characters around this expression will be trimmed =%>

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

L<Mojo::Template> templates work just like Perl subs (actually they get
compiled to a Perl sub internally).
That means you can access arguments simply via C<@_>.

  % my ($foo, $bar) = @_;
  % my $x = shift;
  test 123 <%= $foo %>

Note that you can't escape L<Mojo::Template> tags, instead we just replace
them if necessary.

  my $mt = Mojo::Template->new;
  $mt->line_start('@@');
  $mt->tag_start('[@@');
  $mt->tag_end('@@]');
  $mt->expression_mark('&');
  $mt->escape_mark('&');
  my $output = $mt->render(<<'EOF', 23);
  @@ my $i = shift;
  <% no code just text [@@&& $i @@]
  EOF

There is only one case that we can escape with a backslash, and that's a
newline at the end of a template line.

  This is <%= 23 * 3 %> a\
  single line

If for some strange reason you absolutely need a backslash in front of a
newline you can escape the backslash with another backslash.

  % use Data::Dumper;
  This will\\
  result <%=  Dumper {foo => 'bar'} %>\\
  in multiple lines

Templates get compiled to Perl code internally, this can make debugging a bit
tricky.
But L<Mojo::Template> will return L<Mojo::Exception> objects that stringify
to error messages with context.

  Bareword "xx" not allowed while "strict subs" in use at template line 4.
  2: </head>
  3: <body>
  4: % my $i = 2; xx
  5: %= $i * 2
  6: </body>

L<Mojo::Template> does not support caching by itself, but you can easily
build a wrapper around it.

  # Compile and store code somewhere
  my $mt = Mojo::Template->new;
  $mt->parse($template);
  $mt->build;
  my $code = $mt->code;

  # Load code and template (template for debug trace only)
  $mt->template($template);
  $mt->code($code);
  $mt->compile;
  my $output = $mt->interpret(@arguments);

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

Name of template currently being processed, defaults to C<template>.
Note that this method is attribute and might change without warning!

=head2 C<namespace>

  my $namespace = $mt->namespace;
  $mt           = $mt->namespace('main');

Namespace used to compile templates, defaults to C<Mojo::Template::SandBox>.

=head2 C<prepend>

  my $code = $mt->prepend;
  $mt      = $mt->prepend('my $self = shift;');

Prepend Perl code to compiled template.

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
  my $output = $mt->interpret(@arguments);

Interpret template.

=head2 C<parse>

  $mt = $mt->parse($template);

Parse template.

=head2 C<render>

  my $output = $mt->render($template);
  my $output = $mt->render($template, @arguments);

Render template.

=head2 C<render_file>

  my $output = $mt->render_file($template_file);
  my $output = $mt->render_file($template_file, @arguments);

Render template file.

=head2 C<render_file_to_file>

  my $exception = $mt->render_file_to_file($template_file, $output_file);
  my $exception = $mt->render_file_to_file(
    $template_file, $output_file, @arguments
  );

Render template file to a specific file.

=head2 C<render_to_file>

  my $exception = $mt->render_to_file($template, $output_file);
  my $exception = $mt->render_to_file(
    $template, $output_file, @arguments
  );

Render template to a specific file.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
