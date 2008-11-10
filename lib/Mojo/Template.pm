# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Template;

use strict;
use warnings;

use base 'Mojo::Base';

use constant DEBUG => $ENV{MOJO_TEMPLATE_DEBUG} || 0;

use Carp 'croak';
use IO::File;

__PACKAGE__->attr('code'           , chained => 1, default => '');
__PACKAGE__->attr('comment_mark'   , chained => 1, default => '#');
__PACKAGE__->attr('compiled'       , chained => 1);
__PACKAGE__->attr('expression_mark', chained => 1, default => '=');
__PACKAGE__->attr('line_start'     , chained => 1, default => '%');
__PACKAGE__->attr('template'       , chained => 1, default => '');
__PACKAGE__->attr('tree'           , chained => 1, default => sub { [] });
__PACKAGE__->attr('tag_start'      , chained => 1, default => '<%');
__PACKAGE__->attr('tag_end'        , chained => 1, default => '%>');

sub build {
    my $self = shift;

    # Compile
    my @lines;
    for my $line (@{$self->tree}) {

        # New line
        push @lines, '';
        for (my $j = 0; $j < @{$line}; $j += 2) {
            my $type  = $line->[$j];
            my $value = $line->[$j + 1];

            # Need to fix line ending?
            my $newline = chomp $value;

            # Text
            if ($type eq 'text') {

                # Quote and fix line ending
                $value = quotemeta($value);
                $value .= '\n' if $newline;

                $lines[-1] .= "\$_MOJO .= \"" . $value . "\";";
            }

            # Code
            if ($type eq 'code') {
                $lines[-1] .= "$value;";
            }

            # Expression
            if ($type eq 'expr') {
                $lines[-1] .= "\$_MOJO .= $value;";
            }
        }
    }

    # Wrap
    $lines[0] ||= '';
    $lines[0]   = q/sub { my $_MOJO = '';/ . $lines[0];
    $lines[-1] .= q/return $_MOJO; };/;

    $self->code(join "\n", @lines);
    return $self;
}

sub compile {
    my $self = shift;

    # Shortcut
    my $code = $self->code;
    return undef unless $code;

    # Catch compilation warnings
    local $SIG{__WARN__} = sub {
        my $error = shift;
        warn $self->_error($error);
    };

    # Compile
    my $compiled = eval $code;
    die $self->_error($@) if $@;

    $self->compiled($compiled);
    return $self;
}

sub interpret {
    my $self = shift;

    # Shortcut
    my $compiled = $self->compiled;
    return undef unless $compiled;

    # Catch interpreter warnings
    local $SIG{__WARN__} = sub {
        my $error = shift;
        warn $self->_error($error);
    };

    # Interpret
    my $result = eval { $compiled->(@_) };
    return $self->_error($@) if $@;

    return $result;
}

# I am so smart! I am so smart! S-M-R-T! I mean S-M-A-R-T...
sub parse {
    my ($self, $tmpl) = @_;
    $self->template($tmpl);

    # Clean start
    delete $self->{tree};

    # Tags
    my $line_start = quotemeta $self->line_start;
    my $tag_start  = quotemeta $self->tag_start;
    my $tag_end    = quotemeta $self->tag_end;
    my $cmnt_mark  = quotemeta $self->comment_mark;
    my $expr_mark  = quotemeta $self->expression_mark;

    # Tokenize
    my $state = 'text';
    my $multiline_expression = 0;
    for my $line (split /\n/, $tmpl) {

        # Perl line without return value
        if ($line =~ /^$line_start\s+(.+)$/) {
            push @{$self->tree}, ['code', $1];
            $multiline_expression = 0;
            next;
        }

        # Perl line with return value
        if ($line =~ /^$line_start$expr_mark\s+(.+)$/) {
            push @{$self->tree}, ['expr', $1];
            $multiline_expression = 0;
            next;
        }

        # Comment line, dummy token needed for line count
        if ($line =~ /^$line_start$cmnt_mark\s+(.+)$/) {
            push @{$self->tree}, [];
            $multiline_expression = 0;
            next;
        }

        # Escaped line ending?
        if ($line =~ /(\\+)$/) {
            my $length = length $1;

            # Newline escaped
            if ($length == 1) {
                $line =~ s/\\$//;
            }

            # Backslash escaped
            if ($length >= 2) {
                $line =~ s/\\\\$/\\/;
                $line .= "\n";
            }
        }

        # Normal line ending
        else { $line .= "\n" }

        # Mixed line
        my @token;
        for my $token (split /
            (
                $tag_start$expr_mark   # Expression
            |
                $tag_start$cmnt_mark   # Comment
            |
                $tag_start             # Code
            |
                $tag_end               # End
            )
        /x, $line) {

            # Garbage
            next unless $token;

            # End
            if ($token =~ /^$tag_end$/) {
                $state = 'text';
                $multiline_expression = 0;
            }

            # Code
            elsif ($token =~ /^$tag_start$/) { $state = 'code' }

            # Comment
            elsif ($token =~ /^$tag_start$cmnt_mark$/) { $state = 'cmnt' }

            # Expression
            elsif ($token =~ /^$tag_start$expr_mark$/) {
                $state = 'expr';
            }

            # Value
            else {

                # Comments are ignored
                next if $state eq 'cmnt';

                # Multiline expressions are a bit complicated,
                # only the first line can be compiled as 'expr'
                $state = 'code' if $multiline_expression;
                $multiline_expression = 1 if $state eq 'expr';

                # Store value
                push @token, $state, $token;
            }
        }
        push @{$self->tree}, \@token;
    }

    return $self;
}

sub render {
    my $self = shift;
    my $tmpl  = shift;

    # Parse
    $self->parse($tmpl);

    # Build
    $self->build;

    # Compile
    $self->compile;

    # Interpret
    return $self->interpret(@_);
}

sub render_file {
    my $self = shift;
    my $path = shift;

    # Open file
    my $file = IO::File->new;
    $file->open("< $path") || croak "Can't open template '$path': $!";

    # Slurp file
    my $tmpl = '';
    while ($file->sysread(my $buffer, 4096, 0)) {
        $tmpl .= $buffer;
    }

    # Render
    return $self->render($tmpl, @_);
}

sub render_file_to_file {
    my $self = shift;
    my $spath = shift;
    my $tpath = shift;

    # Render
    my $result = $self->render_file($spath, @_);

    # Write to file
    return $self->_write_file($tpath, $result);
}

sub render_to_file {
    my $self = shift;
    my $tmpl = shift;
    my $path = shift;

    # Render
    my $result = $self->render($tmpl, @_);

    # Write to file
    return $self->_write_file($path, $result);
}

sub _context {
    my ($self, $text, $line) = @_;

    $line     -= 1;
    my $nline  = $line + 1;
    my $pline  = $line - 1;
    my $nnline = $line + 2;
    my $ppline = $line - 2;
    my @lines  = split /\n/, $text;

    # Context
    my $context = (($line + 1) . ': ' . $lines[$line] . "\n");

    # -1
    $context = (($pline + 1) . ': ' . $lines[$pline] . "\n" . $context)
      if $lines[$pline];

    # -2
    $context = (($ppline + 1) . ': ' . $lines[$ppline] . "\n" . $context)
      if $lines[$ppline];

    # +1
    $context = ($context . ($nline + 1) . ': ' . $lines[$nline] . "\n")
      if $lines[$nline];

    # +2
    $context = ($context . ($nnline + 1) . ': ' . $lines[$nnline] . "\n")
      if $lines[$nnline];

    return $context;
}

# Debug goodness
sub _error {
    my ($self, $error) = @_;

    # No trace in production mode
    return undef unless DEBUG;

    # Line
    if ($error =~ /at\s+\(eval\s+\d+\)\s+line\s+(\d+)/) {
        my $line  = $1;
        my $delim = '-' x 76;

        my $report = "\nTemplate error around line $line.\n";
        my $template = $self->_context($self->template, $line);
        $report .= "$delim\n$template$delim\n";

        # Advanced debugging
        if (DEBUG >= 2) {
            my $code = $self->_context($self->code, $line);
            $report .= "$code$delim\n";
        }

        $report .= "$error\n";
        return $report;
    }

    # No line found
    return "Template error: $error";
}

sub _write_file {
    my ($self, $path, $result) = @_;

    # Write to file
    my $file = IO::File->new;
    $file->open("> $path") or croak "Can't open file '$path': $!";
    $file->syswrite($result) or croak "Can't write to file '$path': $!";
    return 1;
}

1;
__END__

=head1 NAME

Mojo::Template - Perlish Templates!

=head1 SYNOPSIS

    use Mojo::Template;
    my $mt = Mojo::Template->new;

    # Simple
    print $mt->render(<<'EOF');
    <html>
      <head></head>
      <body>
        Time: <%= localtime(time) %>
      </body>
    </html>
    EOF

    # More complicated
    print $mt->render(<<'EOF', 23, 'foo bar');
    %= 5 * 5
    % my ($number, $text) = @_;
    test 123
    foo <% my $i = $number + 2 %>
    % for (1 .. 23) {
    * some text <%= $i++ %>
    % }
    EOF

=head1 DESCRIPTION

L<Mojo::Template> is a minimalistic and very Perl-ish template engine,
designed specifically for all those small tasks that come up during big
projects.
Like preprocessing a config file, generating text from heredocs and stuff
like that.
For bigger tasks you might want to use L<HTML::Mason> or L<Template>.

    <% Inline Perl %>
    <%= Perl expression, replaced with result %>
    <%# Comment, useful for debugging %>
    % Perl line
    %= Perl expression line, replaced with result
    %# Comment line, useful for debugging

L<Mojo::Template> templates work just like Perl subs (actually they get
compiled to a Perl sub internally).
That means you can access arguments simply via C<@_>.

    % my ($foo, $bar) = @_;
    % my $x = shift;
    test 123 <%= $foo %>

Note that you can't escape L<Mojo::Template> tags, instead we just replace
them if neccessary.

    my $mt = Mojo::Template->new;
    $mt->line_start('@@');
    $mt->tag_start('[@@');
    $mt->tag_end('@@]');
    $mt->expression_mark('&');
    $mt->render(<<'EOF', 23);
    @@ my $i = shift;
    <% no code just text [@@& $i @@]
    EOF

There is only one case that we can escape with a backslash, and thats a
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
But by setting the MOJO_TEMPLATE_DEBUG environment variable to C<1>, you can
tell L<Mojo::Template> to trace all errors that might occur and present them
in a very convenient way with context.

    Template error around line 4.
    -----------------------------------------------------------------
    2: </head>
    3: <body>
    4: % my $i = 2; xx
    5: %= $i * 2
    6: </body>
    -----------------------------------------------------------------
    Bareword "xx" not allowed while "strict subs" in use at (eval 13)
    line 4.

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
    my $result = $mt->interpret(@arguments);

=head1 ATTRIBUTES

=head2 C<code>

    my $code = $mt->code;
    $mt      = $mt->code($code);

=head2 C<comment_mark>

    my $comment_mark = $mt->comment_mark;
    $mt              = $mt->comment_mark('#');

=head2 C<expression_mark>

    my $expression_mark = $mt->expression_mark;
    $mt                 = $mt->expression_mark('=');

=head2 C<line_start>

    my $line_start = $mt->line_start;
    $mt            = $mt->line_start('%');

=head2 C<template>

    my $template = $mt->template;
    $mt          = $mt->template($template);

=head2 C<tree>

    my $tree = $mt->tree;
    $mt      = $mt->tree($tree);

=head2 C<tag_start>

    my $tag_start = $mt->tag_start;
    $mt           = $mt->tag_start('<%');

=head2 C<tag_end>

    my $tag_end = $mt->tag_end;
    $mt         = $mt->tag_end('%>');

=head1 METHODS

L<Mojo::Template> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $mt = Mojo::Template->new;

=head2 C<build>

    $mt = $mt->build;

=head2 C<compile>

    $mt = $mt->compile;

=head2 C<interpret>

    my $result = $mt->interpret;
    my $result = $mt->interpret(@arguments);

=head2 C<parse>

    $mt = $mt->parse($template);

=head2 C<render>

    my $result = $mt->render($template);
    my $result = $mt->render($template, @arguments);

=head2 C<render_file>

    my $result = $mt->render_file($template_file);
    my $result = $mt->render_file($template_file, @arguments);

=head2 C<render_file_to_file>

    my $result = $mt->render_file_to_file($template_file, $result_file);
    my $result = $mt->render_file_to_file(
        $template_file, $result_file, @arguments
    );

=head2 C<render_to_file>

    my $result = $mt->render_to_file($template, $result_file);
    my $result = $mt->render_to_file(
        $template, $result_file, @arguments
    );

=cut