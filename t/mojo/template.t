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
my $result;
$mt->interpret(\$result, 2);
is($result, "<html foo=\"bar\">\n3 test 4 lala \n4\%\n</html>\n");

# Arguments
$mt = Mojo::Template->new;
$result = '';
$mt->render(<<'EOF', \$result, 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %>
%= $message . ' ' . $hash->{foo}
</html>
EOF
is($result, "<html>\ntest bar</html>\n");

# Ugly multiline loop
$mt = Mojo::Template->new;
$result = '';
$mt->render(<<'EOF', \$result);
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
is($result, "<html>1234</html>\n");

# Clean multiline loop
$mt = Mojo::Template->new;
$result = '';
$mt->render(<<'EOF', \$result);
<html>
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is($result, "<html>\n1234</html>\n");

# Escaped line ending
$mt = Mojo::Template->new;
$result = '';
$mt->render(<<'EOF', \$result);
<html>\
%= '2' x 4
</html>\\\\
EOF
is($result, "<html>2222</html>\\\\\\\n");

# Multiline comment
$mt = Mojo::Template->new;
$result = '';
$mt->render(<<'EOF', \$result);
<html><%# this is
a
comment %>this not
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is($result, "<html>this not\n1234</html>\n");

# Oneliner
$mt = Mojo::Template->new;
$result = '';
$mt->render('<html><%= 3 * 3 %></html>\\', \$result);
is($result, '<html>9</html>');

# Different line start
$mt = Mojo::Template->new;
$mt->line_start('$');
$result = '';
$mt->render(<<'EOF', \$result);
<html>\
$= '2' x 4
</html>\\\\
EOF
is($result, "<html>2222</html>\\\\\\\n");

# Multiline expression
$mt = Mojo::Template->new;
$result = '';
$mt->render(<<'EOF', \$result);
<html><%= do { my $i = '2';
$i x 4; } %>\
</html>\
EOF
is($result, "<html>2222</html>");

# Different tags and line start
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
$mt->line_start('$-');
$result = '';
$mt->render(<<'EOF', \$result, 'test', {foo => 'bar'});
$- my $message = shift;
<html>[$- my $hash = $_[0]; -$]
$-= $message . ' ' . $hash->{foo}
</html>
EOF
is($result, "<html>\ntest bar</html>\n");

# Different expression and comment marks
$mt = Mojo::Template->new;
$mt->comment_mark('@@@');
$mt->expression_mark('---');
$result = '';
$mt->render(<<'EOF', \$result, 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %><%@@@ comment lalala %>
%--- $message . ' ' . $hash->{foo}
</html>
EOF
is($result, "<html>\ntest bar</html>\n");

# File
$mt = Mojo::Template->new;
my $file = File::Spec->catfile(
    File::Spec->splitdir($FindBin::Bin), qw/lib test.mt/
);
$result = '';
$mt->render_file($file, \$result, 3);
is($result, "23Hello World!\n");

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
$result = '';
$mt = Mojo::Template->new;
$mt->render_file($file2, \$result);
is($result, " foo bar\nbaz 23\ntest\n");