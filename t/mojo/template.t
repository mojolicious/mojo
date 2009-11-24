#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

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

use Test::More tests => 84;

use File::Spec;
use File::Temp;
use FindBin;

# When I held that gun in my hand, I felt a surge of power...
# like God must feel when he's holding a gun.
use_ok('Mojo::Template');

# Trim line
my $mt     = Mojo::Template->new;
my $output = $mt->render("    <%= 'test' =%> \n");
is($output, 'test');

# Trim line (with expression)
$mt     = Mojo::Template->new;
$output = $mt->render("<%= '123' %><%= 'test' =%>\n");
is($output, '123test');

# Trim lines
$mt     = Mojo::Template->new;
$output = $mt->render(" foo    \n    <%= 'test' =%>\n foo\n");
is($output, " footestfoo\n");

# Trim lines (at start of line)
$mt     = Mojo::Template->new;
$output = $mt->render("    \n<%= 'test' =%>\n    ");
is($output, 'test');

# Trim lines (multiple lines)
$mt     = Mojo::Template->new;
$output = $mt->render(" bar\n foo\n    <%= 'test' =%>\n foo\n bar\n");
is($output, " bar\n footestfoo\n bar\n");

# Trim lines (multiple empty lines)
$mt     = Mojo::Template->new;
$output = $mt->render("    \n<%= 'test' =%>\n    ");
is($output, 'test');

# Trim expression tags
$mt     = Mojo::Template->new;
$output = $mt->render('    <%{= =%><html><%} =%>    ');
is($output, '<html>');

# Expression block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{=
<html>
%}
EOF
is($output, "<html>\n");

# Escaped expression block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{==
<html>
%}
EOF
is($output, "&lt;html&gt;\n");

# Captured escaped expression block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{== my $result =
<html>
%}
%= $result
EOF
is($output, "&lt;html&gt;\n<html>\n");

# Capture lines
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%{ my $result = escape
<html>
%}
%= $result
EOF
is($output, "&lt;html&gt;\n");

# Capture tags
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $result = escape %><html><%}%><%= $result %>
EOF
is($output, "&lt;html&gt;\n");

# Capture tags with appended code
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $result = escape( %><html><%} ); %><%= $result %>
EOF
is($output, "&lt;html&gt;\n");

# Nested capture tags
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%{ my $result = %><%{= escape %><html><%}%><%}%><%= $result %>
EOF
is($output, "&lt;html&gt;\n");

# Strict
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% $foo = 1;
EOF
is(ref $output, 'Mojo::Template::Exception');
like($output->message, qr/^Global symbol "\$foo" requires/);

# Importing into a template
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
is($output, 'Mojo::Templateworks!');
$mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
is($output, 'Mojo::Templateworks!');

# Compile time exception
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% {
%= 1 + 1
test
EOF
is(ref $output, 'Mojo::Template::Exception');
like($output->message, qr/^Missing right curly or square bracket/);
is($output->lines_before->[0]->[0], 3);
is($output->lines_before->[0]->[1], '% {');
is($output->lines_before->[1]->[0], 4);
is($output->lines_before->[1]->[1], '%= 1 + 1');
is($output->line->[0],              5);
is($output->line->[1],              'test');
$output->message("oops!\n");
$output->stack([['Foo', 'foo', 23], ['Bar', 'bar', 24]]);
my $backup = $ENV{MOJO_EXCEPTION_VERBOSE} || '';
$ENV{MOJO_EXCEPTION_VERBOSE} = 0;
is("$output", <<'EOF');
Error around line 5.
3: % {
4: %= 1 + 1
5: test
oops!
EOF
$ENV{MOJO_EXCEPTION_VERBOSE} = 1;
is("$output", <<'EOF');
Error around line 5.
3: % {
4: %= 1 + 1
5: test
foo: 23
bar: 24
oops!
EOF
$ENV{MOJO_EXCEPTION_VERBOSE} = $backup;

# Exception in module
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
%= MyTemplateException->exception
%= 1 + 1
test
EOF
is(ref $output, 'Mojo::Template::Exception');
like($output->message, qr/ohoh/);
is($output->lines_before->[0]->[0], 1);
is($output->lines_before->[0]->[1], 'test');
is($output->lines_before->[1]->[0], 2);
is($output->lines_before->[1]->[1], '123');
is($output->line->[0],              3);
is($output->line->[1],              '%= MyTemplateException->exception');
is($output->lines_after->[0]->[0],  4);
is($output->lines_after->[0]->[1],  '%= 1 + 1');
is($output->lines_after->[1]->[0],  5);
is($output->lines_after->[1]->[1],  'test');
$output->message("oops!\n");
$output->stack([]);
is("$output", <<'EOF');
Error around line 3.
1: test
2: 123
3: %= MyTemplateException->exception
4: %= 1 + 1
5: test
oops!
EOF

# Excpetion in template
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% die 'oops!';
%= 1 + 1
test
EOF
is(ref $output, 'Mojo::Template::Exception');
like($output->message, qr/oops\!/);
is($output->lines_before->[0]->[0], 1);
is($output->lines_before->[0]->[1], 'test');
is($output->lines_before->[1]->[0], 2);
is($output->lines_before->[1]->[1], '123');
is($output->line->[0],              3);
is($output->line->[1],              "% die 'oops!';");
is($output->lines_after->[0]->[0],  4);
is($output->lines_after->[0]->[1],  '%= 1 + 1');
is($output->lines_after->[1]->[0],  5);
is($output->lines_after->[1]->[1],  'test');
$output->message("oops!\n");
$output->stack([]);
is("$output", <<'EOF');
Error around line 3.
1: test
2: 123
3: % die 'oops!';
4: %= 1 + 1
5: test
oops!
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
is($output, "foo\nbar\n");

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
like($mt->code, qr/^package /);
like($mt->code, qr/lala/);
unlike($mt->code, qr/ comment lalala /);
ok(!defined($mt->compiled));
$mt->compile;
is(ref($mt->compiled), 'CODE');
$output = $mt->interpret(2);
is($output, "<html foo=\"bar\">\n3 test 4 lala \n4\</html>\n");

# Arguments
$mt = Mojo::Template->new;
$output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %>
%= $message . ' ' . $hash->{foo}
</html>
EOF
is($output, "<html>\ntest bar</html>\n");

# Ugly multiline loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
is($output, "<html>1234</html>\n");

# Clean multiline loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html>
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is($output, "<html>\n1234</html>\n");

# Escaped line ending
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html>\
%= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n");

# XML escape
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%== '<html>' %>
%== '&lt;'
</html>
EOF
is($output, "<html>&lt;html&gt;\n&amp;lt;</html>\n");

# XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF');
<html><%= '<html>' %>
%= '&lt;'
%== '&lt;'
</html>
EOF
is($output, "<html>&lt;html&gt;\n&amp;lt;&lt;</html>\n");

# Complicated XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF', {foo => 23});
% use Data::Dumper;
%= Data::Dumper->new([shift])->Maxdepth(2)->Indent(1)->Terse(1)->Dump
EOF
is($output, <<'EOF');
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
is($output, "<html>&lt;html&gt;&lt;html&gt;&lt;html&gt;</html>\n");

# Prepending code
$mt = Mojo::Template->new;
$mt->prepend('my $foo = shift; my $bar = "something\nelse"');
$output = $mt->render(<<'EOF', 23);
<%= $foo %>
%= $bar
EOF
is($output, "23\nsomething\nelse");
$mt = Mojo::Template->new;
$mt->prepend(
    q/{no warnings 'redefine'; no strict 'refs'; *foo = sub { 23 }}/);
$output = $mt->render('<%= foo() %>');
is($output, "23\n");
$output = $mt->render('%= foo()');
is($output, 23);

# Appending code
$mt = Mojo::Template->new;
$mt->append('$_M = "FOO!"');
$output = $mt->render('23');
is($output, "FOO!");

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
is($output, "<html>this not\n1234</html>\n");

# Oneliner
$mt     = Mojo::Template->new;
$output = $mt->render('<html><%= 3 * 3 %></html>\\');
is($output, '<html>9</html>');

# Different line start
$mt = Mojo::Template->new;
$mt->line_start('$');
$output = $mt->render(<<'EOF');
<html>\
$= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n");

# Multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%= do { my $i = '2';
$i x 4; }; %>\
</html>\
EOF
is($output, "<html>2222</html>");

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
is($output, "<html>\ntest bar</html>\n");

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
is($output, "<html>\ntest bar</html>\n");

# File
$mt = Mojo::Template->new;
my $file =
  File::Spec->catfile(File::Spec->splitdir($FindBin::Bin), qw/lib test.mt/);
$output = $mt->render_file($file, 3);
like($output, qr/23Hello World!/);

# File to file with utf8 data
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
my $dir = File::Temp::tempdir();
$file = File::Spec->catfile($dir, 'test.mt');
is($mt->render_to_file(<<"EOF", $file), undef);
<% my \$i = 23; %> foo bar
\x{df}\x{0100}bar\x{263a} <%= \$i %>
test
EOF
$mt = Mojo::Template->new;
my $file2 = File::Spec->catfile($dir, 'test2.mt');
is($mt->render_file_to_file($file, $file2), undef);
$mt     = Mojo::Template->new;
$output = $mt->render_file($file2);
is($output, " foo bar\n\x{df}\x{0100}bar\x{263a} 23\ntest\n");
