#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

package MyTemplateExporter;

use strict;
use warnings;

sub import {
    my $caller = caller;
    no strict 'refs';
    *{$caller . '::foo'} = sub {'works!'};
}

package MyTemplateException;

use strict;
use warnings;

sub exception { die 'ohoh' }

package main;

use strict;
use warnings;

use Test::More tests => 95;

use File::Spec;
use File::Temp;
use FindBin;

# When I held that gun in my hand, I felt a surge of power...
# like God must feel when he's holding a gun.
use_ok('Mojo::Template');

# Trim line
my $mt     = Mojo::Template->new;
my $output = $mt->render("    <%= 'test' =%> \n");
is($output, 'test', 'line trimmed');

# Trim line (with expression)
$mt     = Mojo::Template->new;
$output = $mt->render("<%= '123' %><%= 'test' =%>\n");
is($output, '123test', 'expression trimmed');

# Trim lines
$mt     = Mojo::Template->new;
$output = $mt->render(" foo    \n    <%= 'test' =%>\n foo\n");
is($output, " footestfoo\n", 'lines trimmed');

# Trim lines (at start of line)
$mt     = Mojo::Template->new;
$output = $mt->render("    \n<%= 'test' =%>\n    ");
is($output, 'test', 'lines at start trimmed');

# Trim lines (multiple lines)
$mt     = Mojo::Template->new;
$output = $mt->render(" bar\n foo\n    <%= 'test' =%>\n foo\n bar\n");
is($output, " bar\n footestfoo\n bar\n", 'multiple lines trimmed');

# Trim lines (multiple empty lines)
$mt     = Mojo::Template->new;
$output = $mt->render("    \n<%= 'test' =%>\n    ");
is($output, 'test', 'multiple empty lines trimmed');

# Trim expression tags
$mt     = Mojo::Template->new;
$output = $mt->render('    <%{= block =%><html><%} =%>    ');
is($output, '<html>', 'expression tags trimmed');

# Expression block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{ my $block =
<html>
%}
%= $block->()
EOF
is($output, "<html>\n", 'expression block');

# Escaped expression block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{ my $block =
<html>
%}
%== $block->()
EOF
is($output, "&lt;html&gt;\n", 'escaped expression block');

# Captured escaped expression block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{== my $result = block
<html>
%}
%= $result
EOF
is($output, "&lt;html&gt;\n<html>\n", 'captured escaped expression block');

# Capture lines
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{ my $result = escape block
<html>
%}
%= $result
EOF
is($output, "&lt;html&gt;\n", 'captured lines');

# Capture tags
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $result = escape block%><html><%}%><%= $result %>
EOF
is($output, "&lt;html&gt;\n", 'capture tags');

# Capture tags (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $result = escape block {%><html><%}%><%= $result %>
EOF
is($output, "&lt;html&gt;\n", 'capture tags');

# Capture tags with appended code
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $result = escape( block %><html><%} ); %><%= $result %>
EOF
is($output, "&lt;html&gt;\n", 'capture tags with appended code');

# Capture tags with appended code (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $result = escape( block {%><html><%} ); %><%= $result %>
EOF
is($output, "&lt;html&gt;\n", 'capture tags with appended code');

# Nested capture tags
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $result = block %><%{= escape block %><html><%}%><%}%><%= $result %>
EOF
is($output, "&lt;html&gt;\n", 'nested capture tags');

# Nested capture tags (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $result = block {%><%= escape block {%><html><%}%><%}%><%= $result %>
EOF
is($output, "&lt;html&gt;\n", 'nested capture tags');

# Advanced capturing
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{ my $block =
% my $name = shift;
Hello <%= $name %>.
%}
%= $block->('Baerbel')
%= $block->('Wolfgang')
EOF
is($output, <<EOF, 'advanced capturing');
Hello Baerbel.
Hello Wolfgang.
EOF

# Advanced capturing with tags
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $block = =%>
    <% my $name = shift; =%>
    Hello <%= $name %>.
<%}=%>
<%= $block->('Sebastian') %>
<%= $block->('Sara') %>
EOF
is($output, <<EOF, 'advanced capturing with tags');
Hello Sebastian.
Hello Sara.
EOF

# Advanced capturing with tags (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $block = ={%>
    <% my $name = shift; =%>
    Hello <%= $name %>.
<%}=%>
<%= $block->('Sebastian') %>
<%= $block->('Sara') %>
EOF
is($output, <<EOF, 'advanced capturing with tags');
Hello Sebastian.
Hello Sara.
EOF

# More advanced capturing with tags (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my
$block1 = ={%>
    <% my $name = shift; =%>
    Hello <%= $name %>.
<%}=%>
<% my
$block2 =
={%>
    <% my $name = shift; =%>
    Bye <%= $name %>.
<%}=%>
<%= $block1->('Sebastian') %>
<%= $block2->('Sara') %>
EOF
is($output, <<EOF, 'advanced capturing with tags');
Hello Sebastian.
Bye Sara.
EOF

# Block loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $i = 2;
<%{= block %>
    <%= $i++ %>
<%} for 1 .. 3; %>
EOF
is($output, <<EOF, 'block loop');

    2

    3

    4

EOF

# Strict
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% $foo = 1;
EOF
is(ref $output, 'Mojo::Exception', 'right exception');
like($output->message, qr/^Global symbol "\$foo" requires/, 'right message');

# Importing into a template
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
is($output, 'Mojo::Templateworks!', 'right result');
$output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
is($output, 'Mojo::Templateworks!', 'right result');

# Compile time exception
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% {
%= 1 + 1
test
EOF
is(ref $output, 'Mojo::Exception', 'right exception');
like(
    $output->message,
    qr/^Missing right curly or square bracket/,
    'right message'
);
like($output->message, qr/syntax error at template line 5.$/,
    'right message');
is($output->lines_before->[0]->[0], 3,          'right number');
is($output->lines_before->[0]->[1], '% {',      'right line');
is($output->lines_before->[1]->[0], 4,          'right number');
is($output->lines_before->[1]->[1], '%= 1 + 1', 'right line');
is($output->line->[0],              5,          'right number');
is($output->line->[1],              'test',     'right line');
like("$output", qr/^Missing right curly or square bracket/, 'right result');

# Exception in module
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
%= MyTemplateException->exception
%= 1 + 1
test
EOF
is(ref $output, 'Mojo::Exception', 'right exception');
like($output->message, qr/ohoh/, 'right message');
is($output->lines_before->[0]->[0], 19,              'right number');
is($output->lines_before->[0]->[1], 'use warnings;', 'right line');
is($output->lines_before->[1]->[0], 20,              'right number');
is($output->lines_before->[1]->[1], '',              'right line');
is($output->line->[0],              21,              'right number');
is($output->line->[1], "sub exception { die 'ohoh' }", 'right line');
is($output->lines_after->[0]->[0], 22,              'right number');
is($output->lines_after->[0]->[1], '',              'right line');
is($output->lines_after->[1]->[0], 23,              'right number');
is($output->lines_after->[1]->[1], 'package main;', 'right line');
like("$output", qr/ohoh/, 'right result');

# Exception in template
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% die 'oops!';
%= 1 + 1
test
EOF
is(ref $output, 'Mojo::Exception', 'right exception');
like($output->message, qr/oops\!/, 'right message');
is($output->lines_before->[0]->[0], 1,                'right number');
is($output->lines_before->[0]->[1], 'test',           'right line');
is($output->lines_before->[1]->[0], 2,                'right number');
is($output->lines_before->[1]->[1], '123',            'right line');
is($output->line->[0],              3,                'right number');
is($output->line->[1],              "% die 'oops!';", 'right line');
is($output->lines_after->[0]->[0],  4,                'right number');
is($output->lines_after->[0]->[1],  '%= 1 + 1',       'right line');
is($output->lines_after->[1]->[0],  5,                'right number');
is($output->lines_after->[1]->[1],  'test',           'right line');
like("$output", qr/oops\! at template line 3, near "%= 1 \+ 1"./,
    'right result');

# Exception in nested template
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
$mt->line_start('$-');
$output = $mt->render(<<'EOF');
test
$- my $mt = Mojo::Template->new;
[$- my $output = $mt->render(<<'EOT');
%= bar
EOT
$-= $output
-$]
EOF
is($output, <<'EOF', 'exception in nested template');
test
Bareword "bar" not allowed while "strict subs" in use at template line 1.
1: %= bar

EOF

# Control structures
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% if (23 > 22) {
foo
% }
% else {
bar
% }
% if (23 > 22) {
bar
% }
% else {
foo
% }
EOF
is($output, "foo\nbar\n", 'control structure');

# All tags
$mt = Mojo::Template->new;
$mt->parse(<<'EOF');
<html foo="bar">
<%= $_[0] + 1 %> test <%= 2 + 2 %> lala <%# comment lalala %>
%# This is a comment!
% my $i = 2;
%= $i * 2
</html>
EOF
$mt->build;
like($mt->code, qr/^package /, 'right code');
like($mt->code, qr/lala/,      'right code');
unlike($mt->code, qr/ comment lalala /, 'right code');
ok(!defined($mt->compiled), 'nothing compiled');
$mt->compile;
is(ref($mt->compiled), 'CODE', 'code compiled');
$output = $mt->interpret(2);
is($output, "<html foo=\"bar\">\n3 test 4 lala \n4\</html>\n", 'all tags');

# Arguments
$mt = Mojo::Template->new;
$output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %>
%= $message . ' ' . $hash->{foo}
</html>
EOF
is($output, "<html>\ntest bar</html>\n", 'arguments');

# Ugly multiline loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
is($output, "<html>1234</html>\n", 'ugly multiline loop');

# Clean multiline loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html>
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is($output, "<html>\n1234</html>\n", 'clean multiline loop');

# Escaped line ending
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html>\
%= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n", 'escaped line ending');

# XML escape
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%== '<html>' %>
%== '&lt;'
</html>
EOF
is($output, "<html>&lt;html&gt;\n&amp;lt;</html>\n", 'XML escape');

# XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF');
<html><%= '<html>' %>
%= '&lt;'
%== '&lt;'
</html>
EOF
is($output, "<html>&lt;html&gt;\n&amp;lt;&lt;</html>\n", 'XML auto escape');

# Complicated XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF', {foo => 23});
% use Data::Dumper;
%= Data::Dumper->new([shift])->Maxdepth(2)->Indent(1)->Terse(1)->Dump
EOF
is($output, <<'EOF', 'complicated XML auto escape');
{
  &apos;foo&apos; =&gt; 23
}
EOF

# Complicated XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF');
<html><%= '<html>' for 1 .. 3 %></html>
EOF
is( $output,
    "<html>&lt;html&gt;&lt;html&gt;&lt;html&gt;</html>\n",
    'complicated XML auto escape'
);

# Prepending code
$mt = Mojo::Template->new;
$mt->prepend('my $foo = shift; my $bar = "something\nelse"');
$output = $mt->render(<<'EOF', 23);
<%= $foo %>
%= $bar
% my $bar = 23;
%= $bar
EOF
is($output, "23\nsomething\nelse23", 'prepending code');
$mt = Mojo::Template->new;
$mt->prepend(
    q/{no warnings 'redefine'; no strict 'refs'; *foo = sub { 23 }}/);
$output = $mt->render('<%= foo() %>');
is($output, "23\n", 'right result');
$output = $mt->render('%= foo()');
is($output, 23, 'right result');

# Appending code
$mt = Mojo::Template->new;
$mt->append('$_M = "FOO!"');
$output = $mt->render('23');
is($output, "FOO!", 'appending code');

# Multiline comment
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%# this is
a
comment %>this not
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is($output, "<html>this not\n1234</html>\n", 'multiline comment');

# Oneliner
$mt     = Mojo::Template->new;
$output = $mt->render('<html><%= 3 * 3 %></html>\\');
is($output, '<html>9</html>', 'oneliner');

# Different line start
$mt = Mojo::Template->new;
$mt->line_start('$');
$output = $mt->render(<<'EOF');
<html>\
$= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n", 'different line start');

# Multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%= do { my $i = '2';
$i x 4; }; %>\
</html>\
EOF
is($output, '<html>2222</html>', 'multiline expression');

# Different multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%= do { my $i = '2';
  $i x 4; };
%>\
EOF
is($output, '2222', 'multiline expression');

# Scoped scalar
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $foo = 'bar';
<%= $foo %>
EOF
is($output, "bar\n", 'scoped scalar');

# Different tags and line start
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
$mt->line_start('$-');
$output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
$- my $message = shift;
<html>[$- my $hash = $_[0]; -$]
$-= $message . ' ' . $hash->{foo}
</html>
EOF
is($output, "<html>\ntest bar</html>\n", 'different tags and line start');

# Different expression and comment marks
$mt = Mojo::Template->new;
$mt->comment_mark('@@@');
$mt->expression_mark('---');
$output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %><%@@@ comment lalala %>
%--- $message . ' ' . $hash->{foo}
</html>
EOF
is( $output,
    "<html>\ntest bar</html>\n",
    'different expression and comment mark'
);

# File
$mt = Mojo::Template->new;
my $file =
  File::Spec->catfile(File::Spec->splitdir($FindBin::Bin), qw/lib test.mt/);
$output = $mt->render_file($file, 3);
like($output, qr/23Hello World!/, 'file');

# File to file with utf8 data
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
my $dir = File::Temp::tempdir(CLEANUP => 1);
$file = File::Spec->catfile($dir, 'test.mt');
is($mt->render_to_file(<<"EOF", $file), undef, 'file rendered');
<% my \$i = 23; %> foo bar
\x{df}\x{0100}bar\x{263a} <%= \$i %>
test
EOF
$mt = Mojo::Template->new;
my $file2 = File::Spec->catfile($dir, 'test2.mt');
is($mt->render_file_to_file($file, $file2), undef, 'file rendered to file');
$mt     = Mojo::Template->new;
$output = $mt->render_file($file2);
is($output, " foo bar\n\x{df}\x{0100}bar\x{263a} 23\ntest\n", 'right result');
