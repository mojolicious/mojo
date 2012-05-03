package MyTemplateExporter;
use Mojo::Base -strict;

sub import {
  my $caller = caller;
  no strict 'refs';
  *{$caller . '::foo'} = sub {'works!'};
}

package MyTemplateException;
use Mojo::Base -strict;

sub exception { die 'ohoh' }

package main;
use Mojo::Base -strict;

use utf8;

use Test::More tests => 202;

# "When I held that gun in my hand, I felt a surge of power...
#  like God must feel when he's holding a gun."
use File::Spec::Functions qw/catfile splitdir/;
use File::Temp;
use FindBin;
use Mojo::Template;

# Capture helper
my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';

# Consistent scalar context
my $mt = Mojo::Template->new;
$mt->prepend('my @foo = (3, 4);');
my $output = $mt->render('<%= @foo %>:<%== @foo %>');
is $output, "2:2\n", 'same context';

# Trim tag
$mt     = Mojo::Template->new;
$output = $mt->render(" ♥    <%= 'test♥' =%> \n");
is $output, ' ♥test♥', 'tag trimmed';

# Trim expression
$mt     = Mojo::Template->new;
$output = $mt->render("<%= '123' %><%= 'test' =%>\n");
is $output, '123test', 'expression trimmed';

# Trim expression (multiple lines)
$mt     = Mojo::Template->new;
$output = $mt->render(" foo    \n    <%= 'test' =%>\n foo\n");
is $output, " foo    \ntest foo\n", 'expression trimmed';

# Trim expression (at start of line)
$mt     = Mojo::Template->new;
$output = $mt->render("    \n<%= 'test' =%>\n    ");
is $output, "    \ntest    \n", 'expression trimmed';

# Trim expression (multiple lines)
$mt     = Mojo::Template->new;
$output = $mt->render(" bar\n foo\n    <%= 'test' =%>\n foo\n bar\n");
is $output, " bar\n foo\ntest foo\n bar\n", 'expression trimmed';

# Trim expression (multiple empty lines)
$mt     = Mojo::Template->new;
$output = $mt->render("    \n<%= 'test' =%>\n    ");
is $output, "    \ntest    \n", 'expression trimmed';

# Trim expression tags
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render('    <%= capture begin =%><html><% end =%>    ');
is $output, '<html>', 'expression tags trimmed';

# Trim expression tags (relaxed expression end)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render('    <%= capture begin =%><html><%= end =%>    ');
is $output, '<html>', 'expression tags trimmed';

# Trim expression tags (relaxed escaped expression end)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render('    <%= capture begin =%><html><%== end =%>    ');
is $output, '<html>', 'expression tags trimmed';

# Trim expression tags (trim reset)
$mt     = Mojo::Template->new;
$output = $mt->render('    <%= "one" =%><%= "two" %>  three');
is $output, "onetwo  three\n", 'expression tags trimmed';

# Replace tag
$mt     = Mojo::Template->new;
$output = $mt->render('<%% 1 + 1 %>');
is $output, "<% 1 + 1 %>\n", 'tag has been replaced';

# Replace expression tag
$mt     = Mojo::Template->new;
$output = $mt->render('<%%= 1 + 1 %>');
is $output, "<%= 1 + 1 %>\n", 'expression tag has been replaced';

# Replace expression tag (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(' lalala <%%= 1 + 1 %> 1234 ');
is $output, " lalala <%= 1 + 1 %> 1234 \n", 'expression tag has been replaced';

# Replace expression tag (another alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<EOF);
lalala <%%= 1 +
 1 %> 12
34
EOF
is $output, "lalala <%= 1 +\n 1 %> 12\n34\n",
  'expression tag has been replaced';

# Replace comment tag
$mt     = Mojo::Template->new;
$output = $mt->render('<%%# 1 + 1 %>');
is $output, "<%# 1 + 1 %>\n", 'comment tag has been replaced';

# Replace line
$mt     = Mojo::Template->new;
$output = $mt->render('%% my $foo = 23;');
is $output, "% my \$foo = 23;\n", 'line has been replaced';

# Replace expression line
$mt     = Mojo::Template->new;
$output = $mt->render('  %%= 1 + 1');
is $output, "  %= 1 + 1\n", 'expression line has been replaced';

# Replace expression line (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render('%%= 1 + 1');
is $output, "%= 1 + 1\n", 'expression line has been replaced';

# Replace comment line
$mt     = Mojo::Template->new;
$output = $mt->render('  %%# 1 + 1');
is $output, "  %# 1 + 1\n", 'comment line has been replaced';

# Replace mixed
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
%% my $number = <%= 20 + 3%>;
The number is <%%= <%= '$' %>number %>.
EOF
is $output, "% my \$number = 23;\nThe number is <%= \$number %>.\n",
  'mixed lines have been replaced';

# Helper starting with "end"
$mt = Mojo::Template->new(prepend => 'sub endpoint { "works!" }');
$output = $mt->render(<<'EOF');
% endpoint;
%= endpoint
%== endpoint
<% endpoint; %><%= endpoint %><%== endpoint =%>
EOF
is $output, "works!\nworks!\nworks!works!", 'helper worked';

# Helper ending with "begin"
$mt = Mojo::Template->new(prepend => 'sub funbegin { "works too!" }');
$output = $mt->render(<<'EOF');
% funbegin;
%= funbegin
%== funbegin
<% funbegin; %><%= funbegin %><%== funbegin =%>\
EOF
is $output, "works too!\nworks too!\nworks too!works too!", 'helper worked';

# Catched exception
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% eval { die {foo => 'bar'} };
%= $@->{foo}
EOF
is $output, "bar\n", 'exception passed through';

# Dummy exception object
package MyException;
use Mojo::Base -base;
use overload '""' => sub { shift->error }, fallback => 1;

has 'error';

package main;

# Catched exception object
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% eval { die MyException->new(error => 'works!') };
%= $@->error
EOF
is $output, "works!\n", 'exception object passed through';

# Recursive block
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block;
<% $block = begin =%>
% my $i = shift;
<html>
<%= $block->(--$i) if $i %>
<% end =%>
<%= $block->(2) %>
EOF
is $output, "<html>\n<html>\n<html>\n\n\n\n\n", 'recursive block';

# Recursive block (perl lines)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block;
% $block = begin
% my $i = shift;
<html>
%= $block->(--$i) if $i
% end
%= $block->(2)
EOF
is $output, "<html>\n<html>\n<html>\n\n\n\n\n", 'recursive block';

# Recursive block (indented perl lines)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
  % my $block;
  % $block = begin
    % my $i = shift;
<html>
    <%= $block->(--$i) if $i =%>
  % end
  %= $block->(2)
EOF
is $output, "  <html>\n<html>\n<html>\n\n", 'recursive block';

# Expression block (less whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $block =begin=%>
<html>
<%end=%>
<%= $block->() %>
EOF
is $output, "<html>\n\n", 'expression block';

# Expression block (perl lines and less whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block =begin
<html>
%end
<%= $block->() %>
EOF
is $output, "<html>\n\n", 'expression block';

# Expression block (indented perl lines and less whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
    % my $block =begin
<html>
    %end
<%= $block->() %>
EOF
is $output, "<html>\n\n", 'expression block';

# Escaped expression block (passed through with extra whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $block =  begin %>
<html>
<% end  %>
<%== $block->() %>
EOF
is $output, "\n\n<html>\n\n", 'escaped expression block';

# Escaped expression block
# (passed through with perl lines and extra whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block =  begin
<html>
<% end  %>
<%== $block->() %>
EOF
is $output, "\n<html>\n\n", 'escaped expression block';

# Escaped expression block
# (passed through with indented perl lines and extra whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
 % my $block =  begin
<html>
   % end
<%== $block->() %>
EOF
is $output, "<html>\n\n", 'escaped expression block';

# Capture lines (passed through with extra whitespace)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = capture begin                  %>
<html>
<%                        end %>
%== $result
EOF
is $output, "\n\n<html>\n\n", 'captured lines';

# Capture tags (passed through)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = capture begin %><html><% end %><%== $result %>
EOF
is $output, "<html>\n", 'capture tags';

# Capture tags (passed through alternative)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = capture begin %><html><% end %><%== $result %>
EOF
is $output, "<html>\n", 'capture tags';

# Capture tags with appended code (passed through)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = +(capture begin %><html><% end); %><%== $result %>
EOF
is $output, "<html>\n", 'capture tags with appended code';

# Capture tags with appended code (passed through alternative)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = +( capture begin %><html><% end ); %><%= $result %>
EOF
is $output, "<html>\n", 'capture tags with appended code';

# Nested capture tags (passed through)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = capture
  begin %><%= capture begin %><html><% end
  %><% end %><%== $result %>
EOF
is $output, "<html>\n", 'nested capture tags';

# Nested capture tags (passed through alternative)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
<% my $result = capture begin =%>
    <%== capture begin =%>
        <html>
    <% end =%>
<% end =%>
<%= $result =%>
EOF
is $output, "        <html>\n", 'nested capture tags';

# Advanced capturing (extra whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $block =  begin  =%>
<% my $name = shift; =%>
Hello <%= $name %>.
<%  end  =%>
<%= $block->('Baerbel') =%>
<%= $block->('Wolfgang') =%>
EOF
is $output, <<EOF, 'advanced capturing';
Hello Baerbel.
Hello Wolfgang.
EOF

# Advanced capturing (perl lines extra whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block =  begin
<% my $name = shift; =%>
Hello <%= $name %>.
%  end
<%= $block->('Baerbel') %>
<%= $block->('Wolfgang') %>
EOF
is $output, <<EOF, 'advanced capturing';
Hello Baerbel.

Hello Wolfgang.

EOF

# Advanced capturing (indented perl lines extra whitespace)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
    % my $block =  begin
<% my $name = shift; =%>
Hello <%= $name %>.
    %  end
<%= $block->('Baerbel') %>
<%= $block->('Wolfgang') %>
EOF
is $output, <<EOF, 'advanced capturing';
Hello Baerbel.

Hello Wolfgang.

EOF

# Advanced capturing with tags
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $block = begin =%>
    <% my $name = shift; =%>
    Hello <%= $name %>.
<% end =%>
<%= $block->('Sebastian') %>
<%= $block->('Sara') %>
EOF
is $output, <<EOF, 'advanced capturing with tags';
    Hello Sebastian.

    Hello Sara.

EOF

# Advanced capturing with tags (perl lines)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block = begin
    <% my $name = shift; =%>
    Hello <%= $name %>.
% end
%= $block->('Sebastian')
%= $block->('Sara')
EOF
is $output, <<EOF, 'advanced capturing with tags';
    Hello Sebastian.

    Hello Sara.

EOF

# Advanced capturing with tags (indented perl lines)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block = begin
    % my $name = shift;
    Hello <%= $name %>.
% end
    %= $block->('Sebastian')
%= $block->('Sara')
EOF
is $output, <<EOF, 'advanced capturing with tags';
        Hello Sebastian.

    Hello Sara.

EOF

# Advanced capturing with tags (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my $block = begin =%>
    <% my $name = shift; =%>
    Hello <%= $name %>.
<% end =%>
<%= $block->('Sebastian') %>
<%= $block->('Sara') %>
EOF
is $output, <<EOF, 'advanced capturing with tags';
    Hello Sebastian.

    Hello Sara.

EOF

# Advanced capturing with tags (perl lines and alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $block = begin
    <% my $name = shift; =%>
    Hello <%= $name %>.
% end
%= $block->('Sebastian')
%= $block->('Sara')
EOF
is $output, <<EOF, 'advanced capturing with tags';
    Hello Sebastian.

    Hello Sara.

EOF

# Advanced capturing with tags (indented perl lines and alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
 % my $block = begin
    % my $name = shift;
    Hello <%= $name %>.
 % end
%= $block->('Sebastian')
%= $block->('Sara')
EOF
is $output, <<EOF, 'advanced capturing with tags';
    Hello Sebastian.

    Hello Sara.

EOF

# More advanced capturing with tags (alternative)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<% my
$block1 = begin =%>
    <% my $name = shift; =%>
    Hello <%= $name %>.
<% end =%>
<% my
$block2 =
begin =%>
    <% my $name = shift; =%>
    Bye <%= $name %>.
<% end =%>
<%= $block1->('Sebastian') %>
<%= $block2->('Sara') %>
EOF
is $output, <<EOF, 'advanced capturing with tags';
    Hello Sebastian.

    Bye Sara.

EOF

# Block loop
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
% my $i = 2;
<%= capture begin %>
    <%= $i++ %>
<% end for 1 .. 3; %>
EOF
is $output, <<EOF, 'block loop';

    2

    3

    4

EOF

# Block loop (perl lines)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
% my $i = 2;
%= capture begin
    <%= $i++ =%>
% end for 1 .. 3;
EOF
is $output, "\n2\n3\n4", 'block loop';

# Block loop (indented perl lines)
$mt = Mojo::Template->new(prepend => $capture);
$output = $mt->render(<<'EOF');
  % my $i = 2;
 %= capture begin
    %= $i++
   % end for 1 .. 3;
EOF
is $output, " \n    2\n\n    3\n\n    4\n", 'block loop';

# Strict
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% $foo = 1;
EOF
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/^Global symbol "\$foo" requires/, 'right message';

# Importing into a template
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
is $output, "Mojo::Template::SandBox\nworks!\n", 'right result';
$output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
is $output, "Mojo::Template::SandBox\nworks!\n", 'right result';

# Unusable error message (stacktrace required)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% die "x\n";
test
EOF
isa_ok $output, 'Mojo::Exception', 'right exception';
is $output->message, "x\n", 'right message';
is $output->lines_before->[0]->[0], 1,      'right number';
is $output->lines_before->[0]->[1], 'test', 'right line';
is $output->lines_before->[1]->[0], 2,      'right number';
is $output->lines_before->[1]->[1], '123',  'right line';
is $output->line->[0], 3, 'right number';
is $output->line->[1], '% die "x\n";', 'right line';
like "$output", qr/^x/, 'right result';

# Compile time exception
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% {
%= 1 + 1
test
EOF
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/^Missing right curly or square bracket/,
  'right message';
like $output->message, qr/syntax error at template line 5.$/, 'right message';
is $output->lines_before->[0]->[0], 1,          'right number';
is $output->lines_before->[0]->[1], 'test',     'right line';
is $output->lines_before->[1]->[0], 2,          'right number';
is $output->lines_before->[1]->[1], '123',      'right line';
is $output->lines_before->[2]->[0], 3,          'right number';
is $output->lines_before->[2]->[1], '% {',      'right line';
is $output->lines_before->[3]->[0], 4,          'right number';
is $output->lines_before->[3]->[1], '%= 1 + 1', 'right line';
is $output->line->[0], 5,      'right number';
is $output->line->[1], 'test', 'right line';
like "$output", qr/^Missing right curly or square bracket/, 'right result';
like $output->frames->[0]->[1], qr/Template\.pm$/, 'right file';

# Exception in module
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
%= MyTemplateException->exception
%= 1 + 1
test
EOF
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/ohoh/, 'right message';
is $output->lines_before->[0]->[0], 8,   'right number';
is $output->lines_before->[0]->[1], '}', 'right line';
is $output->lines_before->[1]->[0], 9,   'right number';
is $output->lines_before->[1]->[1], '',  'right line';
is $output->lines_before->[2]->[0], 10,  'right number';
is $output->lines_before->[2]->[1], 'package MyTemplateException;',
  'right line';
is $output->lines_before->[3]->[0], 11,                        'right number';
is $output->lines_before->[3]->[1], 'use Mojo::Base -strict;', 'right line';
is $output->lines_before->[4]->[0], 12,                        'right number';
is $output->lines_before->[4]->[1], '',                        'right line';
is $output->line->[0], 13, 'right number';
is $output->line->[1], "sub exception { die 'ohoh' }", 'right line';
is $output->lines_after->[0]->[0], 14,              'right number';
is $output->lines_after->[0]->[1], '',              'right line';
is $output->lines_after->[1]->[0], 15,              'right number';
is $output->lines_after->[1]->[1], 'package main;', 'right line';
like "$output", qr/ohoh/, 'right result';

# Exception in template
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
% die 'oops!';
%= 1 + 1
test
EOF
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/oops\!/, 'right message';
is $output->lines_before->[0]->[0], 1,      'right number';
is $output->lines_before->[0]->[1], 'test', 'right line';
is $output->lines_before->[1]->[0], 2,      'right number';
is $output->lines_before->[1]->[1], '123',  'right line';
is $output->line->[0], 3, 'right number';
is $output->line->[1], "% die 'oops!';", 'right line';
is $output->lines_after->[0]->[0], 4,          'right number';
is $output->lines_after->[0]->[1], '%= 1 + 1', 'right line';
is $output->lines_after->[1]->[0], 5,          'right number';
is $output->lines_after->[1]->[1], 'test',     'right line';
like "$output", qr/oops\! at template line 3, near "%= 1 \+ 1"./,
  'right result';

# Exception in template (empty perl lines)
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
test
123
%
% die 'oops!';
%
  %
%
%= 1 + 1
test
EOF
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/oops\!/, 'right message';
is $output->lines_before->[0]->[0], 1,      'right number';
is $output->lines_before->[0]->[1], 'test', 'right line';
ok $output->lines_before->[0]->[2], 'contains code';
is $output->lines_before->[1]->[0], 2,      'right number';
is $output->lines_before->[1]->[1], '123',  'right line';
ok $output->lines_before->[1]->[2], 'contains code';
is $output->lines_before->[2]->[0], 3,      'right number';
is $output->lines_before->[2]->[1], '%',    'right line';
is $output->lines_before->[2]->[2], ' ',    'right code';
is $output->line->[0], 4, 'right number';
is $output->line->[1], "% die 'oops!';", 'right line';
is $output->lines_after->[0]->[0], 5,     'right number';
is $output->lines_after->[0]->[1], '%',   'right line';
is $output->lines_after->[0]->[2], ' ',   'right code';
is $output->lines_after->[1]->[0], 6,     'right number';
is $output->lines_after->[1]->[1], '  %', 'right line';
is $output->lines_after->[1]->[2], ' ',   'right code';
is $output->lines_after->[2]->[0], 7,     'right number';
is $output->lines_after->[2]->[1], '%',   'right line';
is $output->lines_after->[2]->[2], ' ',   'right code';
like "$output", qr/oops\! at template line 4, near "%"./, 'right result';

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
-$]
$-= $output
EOF
is $output, <<'EOF', 'exception in nested template';
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
is $output, "foo\nbar\n", 'control structure';

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
like $mt->code,   qr/^package /,        'right code';
like $mt->code,   qr/lala/,             'right code';
unlike $mt->code, qr/ comment lalala /, 'right code';
ok !defined($mt->compiled), 'nothing compiled';
$mt->compile;
isa_ok $mt->compiled, 'CODE', 'code compiled';
$output = $mt->interpret(2);
is $output, "<html foo=\"bar\">\n3 test 4 lala \n4\n\</html>\n", 'all tags';

# Arguments
$mt = Mojo::Template->new;
$output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
% my $message = shift;
<html><% my $hash = $_[0]; %>
%= $message . ' ' . $hash->{foo}
</html>
EOF
is $output, "<html>\ntest bar\n</html>\n", 'arguments';

# Ugly multiline loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
is $output, "<html>1234</html>\n", 'ugly multiline loop';

# Clean multiline loop
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html>
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
is $output, "<html>\n1\n2\n3\n4\n</html>\n", 'clean multiline loop';

# Escaped line ending
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html>\
%= '2' x 4
</html>\\\\
EOF
is $output, "<html>2222\n</html>\\\\\\\n", 'escaped line ending';

# XML escape
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%== '<html>' %>
%== '&lt;'
</html>
EOF
is $output, "<html>&lt;html&gt;\n&amp;lt;\n</html>\n", 'XML escape';

# XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF');
<html><%= '<html>' %>
%= '&lt;'
%== '&lt;'
</html>
EOF
is $output, <<EOF, 'XML auto escape';
<html>&lt;html&gt;
&amp;lt;
&lt;
</html>
EOF

# Complicated XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF', {foo => 23});
% use Data::Dumper;
%= Data::Dumper->new([shift])->Maxdepth(2)->Indent(1)->Terse(1)->Dump
EOF
is $output, <<'EOF', 'complicated XML auto escape';
{
  &#39;foo&#39; =&gt; 23
}

EOF

# Complicated XML auto escape
$mt = Mojo::Template->new;
$mt->auto_escape(1);
$output = $mt->render(<<'EOF');
<html><%= '<html>' for 1 .. 3 %></html>
EOF
is $output, <<EOF, 'complicated XML auto escape';
<html>&lt;html&gt;&lt;html&gt;&lt;html&gt;</html>
EOF

# Prepending code
$mt = Mojo::Template->new;
$mt->prepend('my $foo = shift; my $bar = "something\nelse"');
$output = $mt->render(<<'EOF', 23);
<%= $foo %>
%= $bar
% my $bar = 23;
%= $bar
EOF
is $output, "23\nsomething\nelse\n23\n", 'prepending code';
$mt = Mojo::Template->new;
$mt->prepend(q/{no warnings 'redefine'; no strict 'refs'; *foo = sub { 23 }}/);
$output = $mt->render('<%= foo() %>');
is $output, "23\n", 'right result';
$output = $mt->render('%= foo()');
is $output, "23\n", 'right result';

# Appending code
$mt = Mojo::Template->new;
$mt->append('$_M = "FOO!"');
$output = $mt->render('23');
is $output, "FOO!", 'appending code';

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
is $output, "<html>this not\n1\n2\n3\n4\n</html>\n", 'multiline comment';

# Oneliner
$mt     = Mojo::Template->new;
$output = $mt->render('<html><%= 3 * 3 %></html>\\');
is $output, '<html>9</html>', 'oneliner';

# Different line start
$mt = Mojo::Template->new;
$mt->line_start('$');
$output = $mt->render(<<'EOF');
<html>\
$= '2' x 4
</html>\\\\
EOF
is $output, "<html>2222\n</html>\\\\\\\n", 'different line start';

# Inline comments
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% if (1) { # test
works!
% }   # tset
great!
EOF
is $output, "works!\ngreat!\n", 'comments did not affect the result';

# Multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<html><%= do { my $i = '2';
$i x 4; }; %>\
</html>\
EOF
is $output, '<html>2222</html>', 'multiline expression';

# Different multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%= do { my $i = '2';
  $i x 4; };
%>\
EOF
is $output, '2222', 'multiline expression';

# Yet another multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%= 'hello' .
    ' world' %>\
EOF
is $output, 'hello world', 'multiline expression';

# And another multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%= 'hello' .

    ' world' %>\
EOF
is $output, 'hello world', 'multiline expression';

# And another multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%= 'hello' .

 ' wo' .

    'rld'
%>\
EOF
is $output, 'hello world', 'multiline expression';

# Escaped multiline expression
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
<%==
'hello '
.'world'
%>
EOF
is $output, "hello world\n", 'escaped multiline expression';

# Scoped scalar
$mt     = Mojo::Template->new;
$output = $mt->render(<<'EOF');
% my $foo = 'bar';
<%= $foo %>
EOF
is $output, "bar\n", 'scoped scalar';

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
is $output, "<html>\ntest bar\n</html>\n", 'different tags and line start';

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
is $output, <<EOF, 'different expression and comment mark';
<html>
test bar
</html>
EOF

# File
$mt = Mojo::Template->new;
my $file = catfile(splitdir($FindBin::Bin), qw/lib test.mt/);
$output = $mt->render_file($file, 3);
like $output, qr/23\nHello World!/, 'file';

# Exception in file
$mt     = Mojo::Template->new;
$file   = catfile(splitdir($FindBin::Bin), qw/lib exception.mt/);
$output = $mt->render_file($file);
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/exception\.mt line 2/, 'message contains file name';
is $output->lines_before->[0]->[0], 1,      'right number';
is $output->lines_before->[0]->[1], 'test', 'right line';
is $output->line->[0], 2,        'right number';
is $output->line->[1], '% die;', 'right line';
is $output->lines_after->[0]->[0], 3,     'right number';
is $output->lines_after->[0]->[1], '123', 'right line';
like "$output", qr/exception\.mt line 2/, 'right result';

# Exception in file (different name)
$mt     = Mojo::Template->new;
$file   = catfile(splitdir($FindBin::Bin), qw/lib exception.mt/);
$output = $mt->name('foo.mt')->render_file($file);
isa_ok $output, 'Mojo::Exception', 'right exception';
like $output->message, qr/foo\.mt line 2/, 'message contains file name';
is $output->lines_before->[0]->[0], 1,      'right number';
is $output->lines_before->[0]->[1], 'test', 'right line';
is $output->line->[0], 2,        'right number';
is $output->line->[1], '% die;', 'right line';
is $output->lines_after->[0]->[0], 3,     'right number';
is $output->lines_after->[0]->[1], '123', 'right line';
like "$output", qr/foo\.mt line 2/, 'right result';

# File to file with utf8 data
$mt = Mojo::Template->new;
$mt->tag_start('[$-');
$mt->tag_end('-$]');
my $dir = File::Temp::tempdir(CLEANUP => 1);
$file = catfile $dir, 'test.mt';
is $mt->render_to_file(<<"EOF", $file), undef, 'file rendered';
<% my \$i = 23; %> foo bar
\x{df}\x{0100}bar\x{263a} <%= \$i %>
test
EOF
$mt = Mojo::Template->new;
my $file2 = catfile $dir, 'test2.mt';
is $mt->render_file_to_file($file, $file2), undef, 'file rendered to file';
$mt     = Mojo::Template->new;
$output = $mt->render_file($file2);
is $output, " foo bar\n\x{df}\x{0100}bar\x{263a} 23\ntest\n", 'right result';

# Exception with utf8 context
$mt     = Mojo::Template->new;
$file   = catfile(splitdir($FindBin::Bin), qw/lib utf8_exception.mt/);
$output = $mt->render_file($file);
isa_ok $output, 'Mojo::Exception', 'right exception';
is $output->lines_before->[0]->[1], '☃', 'right line';
is $output->line->[1], '% die;♥', 'right line';
is $output->lines_after->[0]->[1], '☃', 'right line';
is utf8::is_utf8($output->lines_before->[0]->[1]), 1, 'context has utf8 flag';
is utf8::is_utf8($output->line->[1]), 1, 'context has utf8 flag';
is utf8::is_utf8($output->lines_after->[0]->[1]), 1, 'context has utf8 flag';

# Different encodings
$mt = Mojo::Template->new(encoding => 'ISO-8859-1');
$file = catfile $dir, 'test3.mt';
is $mt->render_to_file('ü', $file), undef, 'file rendered';
$mt = Mojo::Template->new(encoding => 'UTF-8');
ok !eval { $mt->render_file($file) }, 'file not rendered';
like $@, qr/invalid encoding/, 'right error';
