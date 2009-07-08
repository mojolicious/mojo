#!perl

# Copyright (C) 2008-2009, Sebastian Riedel.

package MyTemplateException;

use strict;
use warnings;

sub exception { die 'ohoh' }

package main;

use strict;
use warnings;

use Test::More tests => 57;

use File::Spec;
use File::Temp;
use FindBin;

# When I held that gun in my hand, I felt a surge of power...
# like God must feel when he's holding a gun.
use_ok('Mojo::Template');

# Compile time exception
my $mt     = Mojo::Template->new;
my $output = '';
eval {
    $mt->render(<<'EOF', \$output) };
test
123
% {
%= 1 + 1
test
EOF
$output = $@;
is(ref $output, 'Mojo::Template::Exception');
like($output->message, qr/^Missing right curly or square bracket/);
is($output->lines_before->[0]->[0], 3);
is($output->lines_before->[0]->[1], '% {');
is($output->lines_before->[1]->[0], 4);
is($output->lines_before->[1]->[1], '%= 1 + 1');
is($output->line->[0],              5);
is($output->line->[1],              'test');
$output->message("oops!\n");
is("$output", <<'EOF');
Error around line 5.
----------------------------------------------------------------------------
3: % {
4: %= 1 + 1
5: test
----------------------------------------------------------------------------
oops!
EOF

# Exception in module
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
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
is("$output", <<'EOF');
Error around line 3.
----------------------------------------------------------------------------
1: test
2: 123
3: %= MyTemplateException->exception
4: %= 1 + 1
5: test
----------------------------------------------------------------------------
oops!
EOF

# Excpetion in template
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
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
is("$output", <<'EOF');
Error around line 3.
----------------------------------------------------------------------------
1: test
2: 123
3: % die 'oops!';
4: %= 1 + 1
5: test
----------------------------------------------------------------------------
oops!
EOF

# Control structures
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
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
%
</html>
EOF
$mt->build;
like($mt->code, qr/^sub /);
like($mt->code, qr/lala/);
unlike($mt->code, qr/ comment lalala /);
ok(!defined($mt->compiled));
$mt->compile;
is(ref($mt->compiled), 'CODE');
$output = '';
$mt->interpret(\$output, 2);
is($output, "<html foo=\"bar\">\n3 test 4 lala \n4\%\n</html>\n");

# Arguments
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output, 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %>
%= $message . ' ' . $hash->{foo}
</html>
EOF
is($output, "<html>\ntest bar</html>\n");

# Ugly multiline loop
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
is($output, "<html>1234</html>\n");

# Clean multiline loop
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
<html>
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is($output, "<html>\n1234</html>\n");

# Escaped line ending
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
<html>\
%= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n");

# Multiline comment
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
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
$output = '';
$mt->render('<html><%= 3 * 3 %></html>\\', \$output);
is($output, '<html>9</html>');

# Different line start
$mt = Mojo::Template->new;
$mt->line_start('$');
$output = '';
$mt->render(<<'EOF', \$output);
<html>\
$= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n");

# Multiline expression
$mt     = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
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
$output = '';
$mt->render(<<'EOF', \$output, 'test', {foo => 'bar'});
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
$output = '';
$mt->render(<<'EOF', \$output, 'test', {foo => 'bar'});
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
$output = '';
$mt->render_file($file, \$output, 3);
like($output, qr/23Hello World!/);

# File to file with utf8 data
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
my $dir = File::Temp::tempdir();
$file = File::Spec->catfile($dir, 'test.mt');
is($mt->render_to_file(<<"EOF", $file), 1);
<% my \$i = 23; %> foo bar
\x{df}\x{0100}bar\x{263a} <%= \$i %>
test
EOF
$mt = Mojo::Template->new;
my $file2 = File::Spec->catfile($dir, 'test2.mt');
is($mt->render_file_to_file($file, $file2), 1);
$output = '';
$mt     = Mojo::Template->new;
$mt->render_file($file2, \$output);
is($output, " foo bar\n\x{df}\x{0100}bar\x{263a} 23\ntest\n");
