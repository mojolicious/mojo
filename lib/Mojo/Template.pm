package Mojo::Template;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::ByteStream;
use Mojo::Exception;
use Mojo::Util qw(decode encode monkey_patch slurp);

use constant DEBUG => $ENV{MOJO_TEMPLATE_DEBUG} || 0;

has [qw(auto_escape compiled)];
has [qw(append code prepend template)] => '';
has capture_end   => 'end';
has capture_start => 'begin';
has comment_mark  => '#';
has encoding      => 'UTF-8';
has escape        => sub { \&Mojo::Util::xml_escape };
has [qw(escape_mark expression_mark trim_mark)] => '=';
has [qw(line_start replace_mark)] => '%';
has name      => 'template';
has namespace => 'Mojo::Template::SandBox';
has tag_start => '<%';
has tag_end   => '%>';
has tree      => sub { [] };

sub build {
  my $self = shift;

  my (@lines, $cpst, $multi);
  my $escape = $self->auto_escape;
  for my $line (@{$self->tree}) {
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
        $value = quotemeta $value;
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
          if (($type eq 'escp' && !$escape) || ($type eq 'expr' && $escape)) {
            $lines[-1] .= "\$_M .= _escape";
            $lines[-1] .= " scalar $value" if length $value;
          }

          # Raw
          else { $lines[-1] .= "\$_M .= scalar $value" }
        }

        # Multiline
        $multi = !(($line->[$j + 2] // '') eq 'text'
          && ($line->[$j + 3] // '') eq '');

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

  return $self->code($self->_wrap(\@lines))->tree([]);
}

sub compile {
  my $self = shift;

  # Compile with line directive
  return undef unless my $code = $self->code;
  my $name = $self->name;
  $name =~ s/"//g;
  my $compiled = eval qq{#line 1 "$name"\n$code};
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
  my $output = eval { $compiled->(@_) };
  return $output unless $@;

  # Exception with template context
  return Mojo::Exception->new($@, [$self->template])->verbose(1);
}

sub parse {
  my ($self, $template) = @_;

  # Clean start
  my $tree = $self->template($template)->tree([])->tree;

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
  my ($trimming, @capture_token);
  for my $line (split /\n/, $template) {
    $trimming = 0 if $state eq 'text';

    # Turn Perl line into mixed line
    if ($state eq 'text' && $line !~ s/^(\s*)\Q$start$replace\E/$1$start/) {
      if ($line =~ s/^(\s*)\Q$start\E(?:(\Q$cmnt\E)|(\Q$expr\E))?//) {

        # Comment
        if ($2) { $line = "$tag$2 $trim$end" }

        # Expression or code
        else { $line = $3 ? "$1$tag$3$line $end" : "$tag$line $trim$end" }
      }
    }

    # Escaped line ending
    $line .= "\n" unless $line =~ s/\\\\$/\\\n/ || $line =~ s/\\$//;

    # Mixed line
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

      # Text
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
    push @$tree, \@token;
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
  croak qq{Template "$path" has invalid encoding.}
    if $encoding && !defined($template = decode $encoding, $template);

  return $self->render($template, @_);
}

sub _trim {
  my ($self, $line) = @_;

  # Walk line backwards
  for (my $j = @$line - 4; $j >= 0; $j -= 2) {

    # Skip captures
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

sub _wrap {
  my ($self, $lines) = @_;

  # Escape function
  my $escape = $self->escape;
  monkey_patch $self->namespace, _escape => sub {
    no warnings 'uninitialized';
    ref $_[0] eq 'Mojo::ByteStream' ? $_[0] : $escape->("$_[0]");
  };

  # Wrap lines
  my $first = $lines->[0] ||= '';
  $lines->[0] = "package @{[$self->namespace]}; use Mojo::Base -strict;";
  $lines->[0]  .= "sub { my \$_M = ''; @{[$self->prepend]}; do { $first";
  $lines->[-1] .= "@{[$self->append]}; \$_M } };";

  my $code = join "\n", @$lines;
  warn "-- Code for @{[$self->name]}\n@{[encode 'UTF-8', $code]}\n\n" if DEBUG;
  return $code;
}

1;

=head1 NAME

Mojo::Template - Perl-ish templates!

=head1 SYNOPSIS

  use Mojo::Template;
  my $mt = Mojo::Template->new;

  # Simple
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
  my $output = $mt->render(<<'EOF', 23, 'foo bar');
  % my ($num, $text) = @_;
  %= 5 * 5
  <!DOCTYPE html>
  <html>
    <head><title>More advanced</title></head>
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

Escaping behavior can be reversed with the C<auto_escape> attribute, this is
the default in L<Mojolicious> C<.ep> templates for example.

  <%= Perl expression, replaced with XML escaped result %>
  <%== Perl expression, replaced with result %>

L<Mojo::ByteStream> objects are always excluded from automatic escaping.

  % use Mojo::ByteStream 'b';
  <%= b('<div>excluded!</div>') %>

Newline characters can be escaped with a backslash.

  This is <%= 1 + 1 %> a\
  single line

And a backslash in front of a newline character can be escaped with another
backslash.

  This will <%= 1 + 1 %> result\\
  in multiple\\
  lines

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

  my $escape = $mt->auto_escape;
  $mt        = $mt->auto_escape(1);

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
  $mt    = $mt->escape(sub { reverse $_[0] });

A callback used to escape the results of escaped expressions, defaults to
L<Mojo::Util/"xml_escape">.

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
  $mt      = $mt->tree([['text', 'foo']]);

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

Build Perl code from tree.

=head2 compile

  my $exception = $mt->compile;

Compile Perl code for template.

=head2 interpret

  my $output = $mt->interpret;
  my $output = $mt->interpret(@args);

Interpret compiled template code.

  # Reuse template
  say $mt->render('Hello <%= $_[0] %>!', 'Bender');
  say $mt->interpret('Fry');
  say $mt->interpret('Leela');

=head2 parse

  $mt = $mt->parse($template);

Parse template into tree.

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

You can set the MOJO_TEMPLATE_DEBUG environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_TEMPLATE_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
