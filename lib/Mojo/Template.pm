# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Template;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Encode qw/decode encode/;
use IO::File;
use Mojo::ByteStream;
use Mojo::Template::Exception;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 4096;

__PACKAGE__->attr([qw/auto_escape compiled namespace/]);
__PACKAGE__->attr([qw/append code prepend/] => '');
__PACKAGE__->attr(comment_mark              => '#');
__PACKAGE__->attr(encoding                  => 'UTF-8');
__PACKAGE__->attr(escape_mark               => '=');
__PACKAGE__->attr(expression_mark           => '=');
__PACKAGE__->attr(line_start                => '%');
__PACKAGE__->attr(template                  => '');
__PACKAGE__->attr(tree => sub { [] });
__PACKAGE__->attr(tag_start => '<%');
__PACKAGE__->attr(tag_end   => '%>');

# Escape helper
my $ESCAPE = <<'EOF';
no strict 'refs'; no warnings 'redefine';
sub escape;
*escape = sub {
    my $v = shift;
    ref $v && ref $v eq 'Mojo::ByteStream'
      ? "$v"
      : Mojo::ByteStream->new($v)->xml_escape->to_string;
};
use strict; use warnings;
EOF
$ESCAPE =~ s/\n//g;

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

                $lines[-1] .= "\$_M .= \"" . $value . "\";";
            }

            # Code
            if ($type eq 'code') { $lines[-1] .= "$value" }

            # Expression
            if ($type eq 'expr' || $type eq 'escp') {

                # Escaped
                my $a = $self->auto_escape;
                if (($type eq 'escp' && !$a) || ($type eq 'expr' && $a)) {
                    $lines[-1] .= "\$_M .= escape +$value;";
                }

                # Raw
                else { $lines[-1] .= "\$_M .= $value;" }
            }
        }
    }

    # Wrap
    my $prepend   = $self->prepend;
    my $append    = $self->append;
    my $namespace = $self->namespace || ref $self;
    $lines[0] ||= '';
    $lines[0] = qq/package $namespace; sub { my \$_M = ''; $ESCAPE; $prepend;/
      . $lines[0];
    $lines[-1] .= qq/$append; return \$_M; };/;

    $self->code(join "\n", @lines);
    return $self;
}

sub compile {
    my $self = shift;

    # Shortcut
    my $code = $self->code;
    return unless $code;

    # Compile
    my $compiled = eval $code;

    # Exception
    return Mojo::Template::Exception->new($@, $self->template) if $@;

    $self->compiled($compiled);
    return;
}

sub interpret {
    my $self = shift;

    # Compile
    unless ($self->compiled) {
        my $e = $self->compile;

        # Exception
        return $e if ref $e;
    }
    my $compiled = $self->compiled;

    # Shortcut
    return unless $compiled;

    # Catch warnings
    local $SIG{__WARN__} =
      sub { warn Mojo::Template::Exception->new(shift, $self->template) };

    # Catch errors
    local $SIG{__DIE__} =
      sub { die Mojo::Template::Exception->new(shift, $self->template) };

    # Interpret
    my $output = eval { $compiled->(@_) };
    $output = $@ if $@;

    return $output;
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
    my $escp_mark  = quotemeta $self->escape_mark;
    my $expr_mark  = quotemeta $self->expression_mark;

    my $mixed_re = qr/
        (
        $tag_start$expr_mark$escp_mark   # Escaped expression
        |
        $tag_start$expr_mark             # Expression
        |
        $tag_start$cmnt_mark             # Comment
        |
        $tag_start                       # Code
        |
        $tag_end                         # End
        )
    /x;

    # Tokenize
    my $state                = 'text';
    my $multiline_expression = 0;
    for my $line (split /\n/, $tmpl) {

        # Perl line without return value
        if ($line =~ /^$line_start\s+(.+)$/) {
            push @{$self->tree}, ['code', $1];
            $multiline_expression = 0;
            next;
        }

        # Perl line with return value that needs to be escaped
        if ($line =~ /^$line_start$expr_mark$escp_mark\s+(.+)$/) {
            push @{$self->tree}, ['escp', $1];
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
        for my $token (split /$mixed_re/, $line) {

            # Garbage
            next unless $token;

            # End
            if ($token =~ /^$tag_end$/) {
                $state                = 'text';
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

            # Expression that needs to be escaped
            elsif ($token =~ /^$tag_start$expr_mark$escp_mark$/) {
                $state = 'escp';
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

    # Open file
    my $file = IO::File->new;
    $file->open("< $path") or croak "Can't open template '$path': $!";

    # Slurp file
    my $tmpl = '';
    while ($file->sysread(my $buffer, CHUNK_SIZE, 0)) {
        $tmpl .= $buffer;
    }

    # Encoding
    $tmpl = decode($self->encoding, $tmpl) if $self->encoding;

    # Render
    return $self->render($tmpl, @_);
}

sub render_file_to_file {
    my $self  = shift;
    my $spath = shift;
    my $tpath = shift;

    # Render
    my $output = $self->render_file($spath, @_);

    # Exception
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

    # Exception
    return $output if ref $output;

    # Write to file
    return $self->_write_file($path, $output);
}

sub _write_file {
    my ($self, $path, $output) = @_;

    # Open file
    my $file = IO::File->new;
    $file->open("> $path") or croak "Can't open file '$path': $!";

    # Encoding
    $output = encode($self->encoding, $output) if $self->encoding;

    # Write to file
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
But L<Mojo::Template> will return L<Mojo::Template::Exception> objects that
stringify to error messages with context.

    Error around line 4.
    2: </head>
    3: <body>
    4: % my $i = 2; xx
    5: %= $i * 2
    6: </body>
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
    my $output = $mt->interpret(@arguments);

=head1 ATTRIBUTES

L<Mojo::Template> implements the following attributes.

=head2 C<auto_escape>

    my $auto_escape = $mt->auto_escape;
    $mt             = $mt->auto_escape(1);

=head2 C<append>

    my $code = $mt->append;
    $mt      = $mt->append('warn "Processed template"');

=head2 C<code>

    my $code = $mt->code;
    $mt      = $mt->code($code);

=head2 C<comment_mark>

    my $comment_mark = $mt->comment_mark;
    $mt              = $mt->comment_mark('#');

=head2 C<encoding>

    my $encoding = $mt->encoding;
    $mt          = $mt->encoding('UTF-8');

=head2 C<escape_mark>

    my $escape_mark = $mt->escape_mark;
    $mt             = $mt->escape_mark('=');

=head2 C<expression_mark>

    my $expression_mark = $mt->expression_mark;
    $mt                 = $mt->expression_mark('=');

=head2 C<line_start>

    my $line_start = $mt->line_start;
    $mt            = $mt->line_start('%');

=head2 C<namespace>

    my $namespace = $mt->namespace;
    $mt           = $mt->namespace('main');

=head2 C<prepend>

    my $code = $mt->prepend;
    $mt      = $mt->prepend('my $self = shift;');

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

    my $exception = $mt->compile;

=head2 C<interpret>

    my $output = $mt->interpret;
    my $output = $mt->interpret(@arguments);

=head2 C<parse>

    $mt = $mt->parse($template);

=head2 C<render>

    my $output = $mt->render($template);
    my $output = $mt->render($template, @arguments);

=head2 C<render_file>

    my $output = $mt->render_file($template_file);
    my $output = $mt->render_file($template_file, @arguments);

=head2 C<render_file_to_file>

    my $exception = $mt->render_file_to_file($template_file, $output_file);
    my $exception = $mt->render_file_to_file(
        $template_file, $output_file, @arguments
    );

=head2 C<render_to_file>

    my $exception = $mt->render_to_file($template, $output_file);
    my $exception = $mt->render_to_file(
        $template, $output_file, @arguments
    );

=cut
