#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 21;

use File::Spec;
use File::Temp;
use FindBin;

# When I held that gun in my hand, I felt a surge of power...
# like God must feel when he's holding a gun.
use_ok('Mojo::Template');

# All tags
my $mt = Mojo::Template->new;
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
my $output;
$mt->interpret(\$output, 2);
is($output, "<html foo=\"bar\">\n3 test 4 lala \n4\%\n</html>\n");

# Arguments
$mt = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output, 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %>
%= $message . ' ' . $hash->{foo}
</html>
EOF
is($output, "<html>\ntest bar</html>\n");

# Ugly multiline loop
$mt = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
is($output, "<html>1234</html>\n");

# Clean multiline loop
$mt = Mojo::Template->new;
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
$mt = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
<html>\
%= '2' x 4
</html>\\\\
EOF
is($output, "<html>2222</html>\\\\\\\n");

# Multiline comment
$mt = Mojo::Template->new;
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
$mt = Mojo::Template->new;
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
$mt = Mojo::Template->new;
$output = '';
$mt->render(<<'EOF', \$output);
<html><%= do { my $i = '2';
$i x 4; } %>\
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
my $file = File::Spec->catfile(
    File::Spec->splitdir($FindBin::Bin), qw/lib test.mt/
);
$output = '';
$mt->render_file($file, \$output, 3);
is($output, "23Hello World!\n");

# File to file
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
my $dir = File::Temp::tempdir();
$file = File::Spec->catfile($dir, 'test.mt');
is($mt->render_to_file(<<'EOF', $file), 1);
<% my $i = 23 %> foo bar
baz <%= $i %>
test
EOF
$mt = Mojo::Template->new;
my $file2 = File::Spec->catfile($dir, 'test2.mt');
is($mt->render_file_to_file($file, $file2), 1);
$output = '';
$mt = Mojo::Template->new;
$mt->render_file($file2, \$output);
is($output, " foo bar\nbaz 23\ntest\n");