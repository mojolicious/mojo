use Mojo::Base -strict;

use Test::More;
use Mojo::File qw(curfile path);
use Mojo::Template;

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

subtest 'Empty template' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('');
  is $output, '', 'empty string';
};

subtest 'Named template' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->name('foo/bar.mt')->render('<%= __FILE__ %>');
  is $output, "foo/bar.mt\n", 'template name';
};

subtest 'Consistent scalar context' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->prepend('my @foo = (3, 4);')->render('<%= @foo %>:<%== @foo %>');
  is $output, "2:2\n", 'same context';
};

subtest 'Parentheses' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<%= (1,2,3)[1] %><%== (1,2,3)[2] %>');
  is $output, "23\n", 'no ambiguity';
};

subtest 'String' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('Just a <%= "test" %>');
  is $output, "Just a test\n", 'rendered string';
};

subtest 'Trim tag' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(" ♥    <%= 'test♥' =%> \n");
  is $output, ' ♥test♥', 'tag trimmed';
};

subtest 'Trim expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("<%= '123' %><%= 'begin#test' =%>\n");
  is $output, '123begin#test', 'expression trimmed';
};

subtest 'Trim expression (multiple lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(" foo    \n    <%= 'test' =%>\n foo\n");
  is $output, " foo    \ntest foo\n", 'expression trimmed';
};

subtest 'Trim expression (at start of line)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("    \n<%= 'test' =%>\n    ");
  is $output, "    \ntest    \n", 'expression trimmed';
};

subtest 'Trim expression (multiple lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(" bar\n foo\n    <%= 'test' =%>\n foo\n bar\n");
  is $output, " bar\n foo\ntest foo\n bar\n", 'expression trimmed';
};

subtest 'Trim expression (multiple empty lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("    \n<%= 'test' =%>\n    ");
  is $output, "    \ntest    \n", 'expression trimmed';
};

subtest 'Trim expression tags' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render('    <%= capture begin =%><html><% end =%>    ');
  is $output, '<html>', 'expression tags trimmed';
};

subtest 'Trim expression tags (relaxed expression end)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render('    <%= capture begin =%><html><%= end =%>    ');
  is $output, '<html>', 'expression tags trimmed';
};

subtest 'Trim expression tags (relaxed escaped expression end)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render('    <%= capture begin =%><html><%== end =%>    ');
  is $output, '<html>', 'expression tags trimmed';
};

subtest 'Trim expression tags (trim reset)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('    <%= "one" =%><%= "two" %>  three');
  is $output, "onetwo  three\n", 'expression tags trimmed';
};

subtest 'Nothing to trim' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<% =%>');
  is $output, '', 'nothing trimmed';
};

subtest 'Replace tag' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<%% 1 + 1 %>');
  is $output, "<% 1 + 1 %>\n", 'tag has been replaced';
};

subtest 'Replace expression tag' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<%%= 1 + 1 %>');
  is $output, "<%= 1 + 1 %>\n", 'expression tag has been replaced';
};

subtest 'Replace expression tag (alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(' lalala <%%= 1 + 1 %> 1234 ');
  is $output, " lalala <%= 1 + 1 %> 1234 \n", 'expression tag has been replaced';
};

subtest 'Replace expression tag (another alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<EOF);
lalala <%%= 1 +
 1 %> 12
34
EOF
  is $output, "lalala <%= 1 +\n 1 %> 12\n34\n", 'expression tag has been replaced';
};

subtest 'Replace comment tag' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<%%# 1 + 1 %>');
  is $output, "<%# 1 + 1 %>\n", 'comment tag has been replaced';
};

subtest 'Replace line' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('%% my $foo = 23;');
  is $output, "% my \$foo = 23;\n", 'line has been replaced';
};

subtest 'Replace expression line' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('  %%= 1 + 1');
  is $output, "  %= 1 + 1\n", 'expression line has been replaced';
};

subtest 'Replace expression line (alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('%%= 1 + 1');
  is $output, "%= 1 + 1\n", 'expression line has been replaced';
};

subtest 'Replace comment line' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('  %%# 1 + 1');
  is $output, "  %# 1 + 1\n", 'comment line has been replaced';
};

subtest 'Replace mixed' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
%% my $num = <%= 20 + 3%>;
The number is <%%= <%= '$' %>num %>.
EOF
  is $output, "% my \$num = 23;\nThe number is <%= \$num %>.\n", 'mixed lines have been replaced';
};

subtest 'Helper starting with "end"' => sub {
  my $mt     = Mojo::Template->new(prepend => 'sub endpoint { "works!" }');
  my $output = $mt->render(<<'EOF');
% endpoint;
%= endpoint
%== endpoint
<% endpoint; %><%= endpoint %><%== endpoint =%>
EOF
  is $output, "works!\nworks!\nworks!works!", 'helper worked';
};

subtest 'Helper ending with "begin"' => sub {
  my $mt     = Mojo::Template->new(prepend => 'sub funbegin { "works too!" }');
  my $output = $mt->render(<<'EOF');
% funbegin;
%= funbegin
%== funbegin
<% funbegin; %><%= funbegin %><%== funbegin =%>\
EOF
  is $output, "works too!\nworks too!\nworks too!works too!", 'helper worked';
};

subtest 'Catched exception' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% eval { die {foo => 'bar'} };
%= $@->{foo}
EOF
  is $output, "bar\n", 'exception passed through';
};

# Dummy exception object
package MyException;
use Mojo::Base -base;
use overload '""' => sub { shift->error }, fallback => 1;

has 'error';

package main;

subtest 'Catched exception object' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% eval { die MyException->new(error => 'works!') };
%= $@->error
EOF
  is $output, "works!\n", 'exception object passed through';
};

subtest 'Recursive block' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% my $block;
<% $block = begin =%>
% my $i = shift;
<html>
<%= $block->(--$i) if $i %>
<% end =%>
<%= $block->(2) %>
EOF
  is $output, "<html>\n<html>\n<html>\n\n\n\n\n", 'recursive block';
};

subtest 'Recursive block (perl lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% my $block;
% $block = begin
% my $i = shift;
<html>
%= $block->(--$i) if $i
% end
%= $block->(2)
EOF
  is $output, "<html>\n<html>\n<html>\n\n\n\n\n", 'recursive block';
};

subtest 'Recursive block (indented perl lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
  % my $block;
  % $block = begin
    % my $i = shift;
<html>
    <%= $block->(--$i) if $i =%>
  % end
  %= $block->(2)
EOF
  is $output, "  <html>\n<html>\n<html>\n\n", 'recursive block';
};

subtest 'Expression block (less whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<% my $block =begin=%>
<html>
<%end=%>
<%= $block->() %>
EOF
  is $output, "<html>\n\n", 'expression block';
};

subtest 'Expression block (perl lines and less whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% my $block =begin
<html>
%end
<%= $block->() %>
EOF
  is $output, "<html>\n\n", 'expression block';
};

subtest 'Expression block (indented perl lines and less whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
    % my $block =begin
<html>
    %end
<%= $block->() %>
EOF
  is $output, "<html>\n\n", 'expression block';
};

subtest 'Escaped expression block (passed through with extra whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<% my $block =  begin %>
<html>
<% end  %>
<%== $block->() %>
EOF
  is $output, "\n\n<html>\n\n", 'escaped expression block';
};

subtest 'Escaped expression block (passed through with perl lines and extra whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% my $block =  begin
<html>
<% end  %>
<%== $block->() %>
EOF
  is $output, "\n<html>\n\n", 'escaped expression block';
};

subtest 'Escaped expression block (passed through with indented perl lines and extra whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
 % my $block =  begin
<html>
   % end
<%== $block->() %>
EOF
  is $output, "<html>\n\n", 'escaped expression block';
};

subtest 'Capture lines (passed through with extra whitespace)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = capture begin                  %>
<html>
<%                        end %>
%== $result
EOF
  is $output, "\n\n<html>\n\n", 'captured lines';
};

subtest 'Capture tags (passed through)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = capture begin %><html><% end %><%== $result %>
EOF
  is $output, "<html>\n", 'capture tags';
};

subtest 'Capture tags (passed through alternative)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = capture begin %><html><% end %><%== $result %>
EOF
  is $output, "<html>\n", 'capture tags';
};

subtest 'Capture tags with appended code (passed through)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = +(capture begin %><html><% end); %><%== $result %>
EOF
  is $output, "<html>\n", 'capture tags with appended code';
};

subtest 'Capture tags with appended code (passed through alternative)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = +( capture begin %><html><% end ); %><%= $result %>
EOF
  is $output, "<html>\n", 'capture tags with appended code';
};

subtest 'Nested capture tags (passed through)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = capture
  begin %><%= capture begin %><html><% end
  %><% end %><%== $result %>
EOF
  is $output, "<html>\n", 'nested capture tags';
};

subtest 'Nested capture tags (passed through alternative)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
<% my $result = capture begin =%>
    <%== capture begin =%>
        <html>
    <% end =%>
<% end =%>
<%= $result =%>
EOF
  is $output, "        <html>\n", 'nested capture tags';
};

subtest 'Advanced capturing (extra whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing (perl lines extra whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing (indented perl lines extra whitespace)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing with tags' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing with tags (perl lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing with tags (indented perl lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing with tags (alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing with tags (perl lines and alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Advanced capturing with tags (indented perl lines and alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'More advanced capturing with tags (alternative)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Block loop' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
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
};

subtest 'Block loop (perl lines)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
% my $i = 2;
%= capture begin
    <%= $i++ =%>
% end for 1 .. 3;
EOF
  is $output, "\n2\n3\n4", 'block loop';
};

subtest 'Block loop (indented perl lines)' => sub {
  my $capture = 'no warnings "redefine"; sub capture { shift->(@_) }';
  my $mt      = Mojo::Template->new(prepend => $capture);
  my $output  = $mt->render(<<'EOF');
  % my $i = 2;
 %= capture begin
    %= $i++
   % end for 1 .. 3;
EOF
  is $output, " \n    2\n\n    3\n\n    4\n", 'block loop';
};

subtest 'End and begin in the same perl line' => sub {
  my $concat = 'no warnings "redefine"; sub concat { $_[0]->() . $_[1]->() }';
  my $mt     = Mojo::Template->new(prepend => $concat);
  my $output = $mt->render(<<'EOF');
  %= concat begin
    1
  % end, begin
    2
  % end
EOF
  is $output, "  \n    1\n    2\n", 'end, begin';
};

subtest 'Strict' => sub {
  my $output = Mojo::Template->new->render('% $foo = 1;');
  isa_ok $output, 'Mojo::Exception', 'right exception';
  like $output->message, qr/^Global symbol "\$foo" requires/, 'right message';
};

subtest 'Importing into a template' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
  is $output, "Mojo::Template::Sandbox\nworks!\n", 'right result';
  $output = $mt->render(<<'EOF');
% BEGIN { MyTemplateExporter->import }
%= __PACKAGE__
%= foo
EOF
  is $output, "Mojo::Template::Sandbox\nworks!\n", 'right result';
};

subtest 'Unusable error message (stack trace required)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
test
123
% die "x\n";
test
EOF
  isa_ok $output, 'Mojo::Exception', 'right exception';
  is $output->message,              "x\n",  'right message';
  is $output->lines_before->[0][0], 1,      'right number';
  is $output->lines_before->[0][1], 'test', 'right line';
  is $output->lines_before->[1][0], 2,      'right number';
  is $output->lines_before->[1][1], '123',  'right line';
  ok $output->lines_before->[1][2], 'contains code';
  is $output->line->[0], 3,              'right number';
  is $output->line->[1], '% die "x\n";', 'right line';
  ok $output->line->[2], 'contains code';
  like "$output", qr/^x/, 'right result';
};

subtest 'Compile time exception' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
test
123
% {
%= 1 + 1
test
EOF
  isa_ok $output, 'Mojo::Exception', 'right exception';
  like $output->message, qr/Missing right curly/, 'right message';
  is $output->lines_before->[0][0], 1,          'right number';
  is $output->lines_before->[0][1], 'test',     'right line';
  is $output->lines_before->[1][0], 2,          'right number';
  is $output->lines_before->[1][1], '123',      'right line';
  is $output->lines_before->[2][0], 3,          'right number';
  is $output->lines_before->[2][1], '% {',      'right line';
  is $output->lines_before->[3][0], 4,          'right number';
  is $output->lines_before->[3][1], '%= 1 + 1', 'right line';
  is $output->line->[0],            5,          'right number';
  is $output->line->[1],            'test',     'right line';
  like "$output",               qr/Missing right curly/, 'right result';
  like $output->frames->[0][1], qr/Template\.pm$/,       'right file';
};

subtest 'Exception in module' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
test
123
%= MyTemplateException->exception
%= 1 + 1
test
EOF
  isa_ok $output, 'Mojo::Exception', 'right exception';
  like $output->message, qr/ohoh/, 'right message';
  is $output->lines_before->[0][0], 14,                             'right number';
  is $output->lines_before->[0][1], '}',                            'right line';
  is $output->lines_before->[1][0], 15,                             'right number';
  is $output->lines_before->[1][1], '',                             'right line';
  is $output->lines_before->[2][0], 16,                             'right number';
  is $output->lines_before->[2][1], 'package MyTemplateException;', 'right line';
  is $output->lines_before->[3][0], 17,                             'right number';
  is $output->lines_before->[3][1], 'use Mojo::Base -strict;',      'right line';
  is $output->lines_before->[4][0], 18,                             'right number';
  is $output->lines_before->[4][1], '',                             'right line';
  is $output->line->[0],            19,                             'right number';
  is $output->line->[1],            "sub exception { die 'ohoh' }", 'right line';
  is $output->lines_after->[0][0],  20,                             'right number';
  is $output->lines_after->[0][1],  '',                             'right line';
  is $output->lines_after->[1][0],  21,                             'right number';
  is $output->lines_after->[1][1],  'package main;',                'right line';
  like "$output", qr/ohoh/, 'right result';
};

subtest 'Exception in template' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
test
123\
456
 %# This dies
% die 'oops!';
%= 1 + 1
test
EOF
  isa_ok $output, 'Mojo::Exception', 'right exception';
  like $output->message, qr/oops!/, 'right message';
  is $output->lines_before->[0][0], 1,                'right number';
  is $output->lines_before->[0][1], 'test',           'right line';
  is $output->lines_before->[1][0], 2,                'right number';
  is $output->lines_before->[1][1], '123\\',          'right line';
  is $output->lines_before->[2][0], 3,                'right number';
  is $output->lines_before->[2][1], '456',            'right line';
  is $output->lines_before->[3][0], 4,                'right number';
  is $output->lines_before->[3][1], ' %# This dies',  'right line';
  is $output->line->[0],            5,                'right number';
  is $output->line->[1],            "% die 'oops!';", 'right line';
  is $output->lines_after->[0][0],  6,                'right number';
  is $output->lines_after->[0][1],  '%= 1 + 1',       'right line';
  is $output->lines_after->[1][0],  7,                'right number';
  is $output->lines_after->[1][1],  'test',           'right line';
  $output->frames([['Sandbox', 'template', 5], ['main', 'template.t', 673]]);
  is $output, <<EOF, 'right result';
oops! at template line 5.
Context:
  1: test
  2: 123\\
  3: 456
  4:  %# This dies
  5: % die 'oops!';
  6: %= 1 + 1
  7: test
Traceback (most recent call first):
  File "template", line 5, in "Sandbox"
  File "template.t", line 673, in "main"
EOF
};

subtest 'Exception in template (empty perl lines)' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
test\\
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
  like $output->message, qr/oops!/, 'right message';
  is $output->lines_before->[0][0], 1,          'right number';
  is $output->lines_before->[0][1], 'test\\\\', 'right line';
  ok $output->lines_before->[0][2], 'contains code';
  is $output->lines_before->[1][0], 2,     'right number';
  is $output->lines_before->[1][1], '123', 'right line';
  ok $output->lines_before->[1][2], 'contains code';
  is $output->lines_before->[2][0], 3,                'right number';
  is $output->lines_before->[2][1], '%',              'right line';
  is $output->lines_before->[2][2], ' ',              'right code';
  is $output->line->[0],            4,                'right number';
  is $output->line->[1],            "% die 'oops!';", 'right line';
  is $output->lines_after->[0][0],  5,                'right number';
  is $output->lines_after->[0][1],  '%',              'right line';
  is $output->lines_after->[0][2],  ' ',              'right code';
  is $output->lines_after->[1][0],  6,                'right number';
  is $output->lines_after->[1][1],  '  %',            'right line';
  is $output->lines_after->[1][2],  ' ',              'right code';
  is $output->lines_after->[2][0],  7,                'right number';
  is $output->lines_after->[2][1],  '%',              'right line';
  is $output->lines_after->[2][2],  ' ',              'right code';
  like "$output", qr/oops! at template line 4/, 'right result';
};

subtest 'Exception in nested template' => sub {
  my $mt = Mojo::Template->new;
  $mt->tag_start('[$-');
  $mt->tag_end('-$]');
  $mt->line_start('$-');
  my $output = $mt->render(<<'EOF');
test
$- my $mt = Mojo::Template->new;
[$- my $output = $mt->render(<<'EOT');
%= bar
EOT
-$]
$-= $output
EOF
  like $output, qr/test\n\nBareword "bar".+in use at template line 1\./, 'exception in nested template';
};

subtest 'Control structures' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
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
};

subtest 'Mixed tags' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF', 2);
<html foo="bar">
<%= $_[0] + 1 %> test <%= 2 + 2 %> lala <%# comment lalala %>
%# This is a comment!
% my $i = 2;
%= $i * 2
</html>
EOF
  is $output, "<html foo=\"bar\">\n3 test 4 lala \n4\n\</html>\n", 'all tags';
  like $mt->code,   qr/lala/,             'right code';
  unlike $mt->code, qr/ comment lalala /, 'right code';
  is ref $mt->compiled, 'CODE', 'code compiled';
};

subtest 'Arguments' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
% my $msg = shift;
<html><% my $hash = $_[0]; %>
%= $msg . ' ' . $hash->{foo}
</html>
EOF
  is $output, "<html>\ntest bar\n</html>\n", 'arguments';
  is $mt->process('tset', {foo => 'baz'}),  "<html>\ntset baz\n</html>\n",  'arguments again';
  is $mt->process('tset', {foo => 'yada'}), "<html>\ntset yada\n</html>\n", 'arguments again';
};

subtest 'Variables' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->vars(1)->render('<%= $foo %><%= $bar %>', {foo => 'works', bar => '!'});
  is $output, "works!\n", 'variables';
};

subtest 'No variables' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->vars(1)->render('works too!');
  is $output, "works too!\n", 'no variables';
};

subtest 'Bad variables' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->vars(1)->render('bad variables!', {'not good' => 23});
  is $output, "bad variables!\n", 'bad variables';
};

subtest 'Ugly multiline loop' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% my $nums = '';
<html><% for my $i (1..4) {
    $nums .= "$i";
} %><%= $nums%></html>
EOF
  is $output, "<html>1234</html>\n", 'ugly multiline loop';
};

subtest 'Clean multiline loop' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<html>
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
  is $output, "<html>\n1\n2\n3\n4\n</html>\n", 'clean multiline loop';
};

subtest 'Escaped line ending' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<html>\
%= '2' x 4
</html>\\\\
EOF
  is $output, "<html>2222\n</html>\\\\\\\n", 'escaped line ending';
};

subtest 'XML escape' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<html><%== '<html>' %>
%== '&lt;'
</html>
EOF
  is $output, "<html>&lt;html&gt;\n&amp;lt;\n</html>\n", 'XML escape';
};

subtest 'XML auto escape' => sub {
  my $mt = Mojo::Template->new;
  $mt->auto_escape(1);
  my $output = $mt->render(<<'EOF');
<html><%= '<html>' %>
%= 'begin#&lt;'
%== 'begin#&lt;'
</html>
EOF
  is $output, <<EOF, 'XML auto escape';
<html>&lt;html&gt;
begin#&amp;lt;
begin#&lt;
</html>
EOF
};

subtest 'Complicated XML auto escape' => sub {
  my $mt = Mojo::Template->new;
  $mt->auto_escape(1);
  my $output = $mt->render(<<'EOF', {foo => 23});
% use Data::Dumper;
%= Data::Dumper->new([shift])->Maxdepth(2)->Indent(1)->Terse(1)->Dump
EOF
  is $output, <<'EOF', 'complicated XML auto escape';
{
  &#39;foo&#39; =&gt; 23
}

EOF
};

subtest 'Complicated XML auto escape' => sub {
  my $mt = Mojo::Template->new;
  $mt->auto_escape(1);
  my $output = $mt->render(<<'EOF');
<html><%= '<html>' for 1 .. 3 %></html>
EOF
  is $output, <<EOF, 'complicated XML auto escape';
<html>&lt;html&gt;&lt;html&gt;&lt;html&gt;</html>
EOF
};

subtest 'Prepending code' => sub {
  my $mt = Mojo::Template->new;
  $mt->prepend('my $foo = shift; my $bar = "something\nelse"');
  my $output = $mt->render(<<'EOF', 23);
<%= $foo %>
%= $bar
% my $bar = 23;
%= $bar
EOF
  is $output, "23\nsomething\nelse\n23\n", 'prepending code';
  $mt = Mojo::Template->new;
  $mt->prepend(q[{no warnings 'redefine'; no strict 'refs'; *foo = sub { 23 }}]);
  $output = $mt->render('<%= foo() %>');
  is $output, "23\n", 'right result';
  $output = $mt->render('%= foo()');
  is $output, "23\n", 'right result';
};

subtest 'Appending code' => sub {
  my $mt = Mojo::Template->new;
  $mt->append('$_O = "FOO!"');
  my $output = $mt->render('23');
  is $output, "FOO!", 'appending code';
};

subtest 'Multiline comment' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<html><%# this is
a
comment %>this not
%  for my $i (1..4) {
%=    $i
%  }
</html>
EOF
  is $output, "<html>this not\n1\n2\n3\n4\n</html>\n", 'multiline comment';
};

subtest 'Commented out tags' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<html>
 %# '<%= 23 %>test<%= 24 %>'
</html>
EOF
  is $output, "<html>\n</html>\n", 'commented out tags';
};

subtest 'One-liner' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<html><%= 3 * 3 %></html>\\');
  is $output, '<html>9</html>', 'one-liner';
};

subtest 'Different line start' => sub {
  my $mt = Mojo::Template->new;
  $mt->line_start('$');
  my $output = $mt->render(<<'EOF');
<html>\
$= '2' x 4
</html>\\\\
EOF
  is $output, "<html>2222\n</html>\\\\\\\n", 'different line start';
};

subtest 'Inline comments' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% if (1) { # test
works!
% }   # tset
great!
EOF
  is $output, "works!\ngreat!\n", 'comments did not affect the result';
};

subtest 'Inline comment on last line' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% if (1) {
works!
% }   # tset
EOF
  is $output, "works!\n", 'comment did not affect the result';
};

subtest 'Multiline expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<html><%= do { my $i = '2';
$i x 4; }; %>\
</html>\
EOF
  is $output, '<html>2222</html>', 'multiline expression';
};

subtest 'Different multiline expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<%= do { my $i = '2';
  $i x 4; };
%>\
EOF
  is $output, '2222', 'multiline expression';
};

subtest 'Yet another multiline expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<%= 'hello' .
    ' world' %>\
EOF
  is $output, 'hello world', 'multiline expression';
};

subtest 'And another multiline expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<%= 'hello' .

    ' world' %>\
EOF
  is $output, 'hello world', 'multiline expression';
};

subtest 'And another multiline expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<%= 'hello' .

 ' wo' .

    'rld'
%>\
EOF
  is $output, 'hello world', 'multiline expression';
};

subtest 'Escaped multiline expression' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
<%==
'hello '
.'world'
%>
EOF
  is $output, "hello world\n", 'escaped multiline expression';
};

subtest 'Empty statement' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("test\n\n123\n\n<% %>456\n789");
  is $output, "test\n\n123\n\n456\n789\n", 'empty statement';
};

subtest 'No newline' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('test');
  is $output, "test\n", 'just one newline';
};

subtest 'Multiple newlines at the end' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("test\n\n\n\n");
  is $output, "test\n", 'just one newline';
};

subtest 'Escaped newline at the end' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("test\\\n");
  is $output, 'test', 'no newline';
};

subtest 'Multiple escaped newlines at the end' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render("test\\\n\n\n\n");
  is $output, 'test', 'no newline';
};

subtest 'Optimize successive text lines ending with newlines' => sub {
  my $mt = Mojo::Template->new;
  $mt->parse(<<'EOF');
test
123
456\
789\\
987
654
321
EOF
  is $mt->tree->[0][1], "test\n123\n456", 'optimized text lines';
  my $output = $mt->process;
  is_deeply $mt->tree, [], 'has been consumed';
  is $output, "test\n123\n456789\\\n987\n654\n321\n", 'just text';
};

subtest 'Scoped scalar' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render(<<'EOF');
% my $foo = 'bar';
<%= $foo %>
EOF
  is $output, "bar\n", 'scoped scalar';
};

subtest 'Different tags and line start' => sub {
  my $mt = Mojo::Template->new;
  $mt->tag_start('[$-');
  $mt->tag_end('-$]');
  $mt->line_start('$-');
  my $output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
$- my $msg = shift;
<html>[$- my $hash = $_[0]; -$]
$-= $msg . ' ' . $hash->{foo}
</html>
EOF
  is $output, "<html>\ntest bar\n</html>\n", 'different tags and line start';
};

subtest 'Different expression and comment marks' => sub {
  my $mt = Mojo::Template->new;
  $mt->comment_mark('@@@');
  $mt->expression_mark('---');
  my $output = $mt->render(<<'EOF', 'test', {foo => 'bar'});
% my $msg = shift;
<html><% my $hash = $_[0]; %><%@@@ comment lalala %>
%--- $msg . ' ' . $hash->{foo}
</html>
EOF
  is $output, <<EOF, 'different expression and comment mark';
<html>
test bar
</html>
EOF
};

subtest 'File' => sub {
  my $mt     = Mojo::Template->new;
  my $file   = curfile->sibling('templates', 'test.mt');
  my $output = $mt->render_file($file, 3);
  like $output, qr/23\nHello World!/, 'file';
};

subtest 'Exception in file' => sub {
  my $mt     = Mojo::Template->new;
  my $file   = curfile->sibling('templates', 'exception.mt');
  my $output = $mt->render_file($file);
  isa_ok $output, 'Mojo::Exception', 'right exception';
  like $output->message, qr/exception\.mt line 2/, 'message contains filename';
  is $output->lines_before->[0][0], 1,        'right number';
  is $output->lines_before->[0][1], 'test',   'right line';
  is $output->line->[0],            2,        'right number';
  is $output->line->[1],            '% die;', 'right line';
  is $output->lines_after->[0][0],  3,        'right number';
  is $output->lines_after->[0][1],  '123',    'right line';
  like "$output", qr/exception\.mt line 2/, 'right result';
};

subtest 'Exception in file (different name)' => sub {
  my $mt     = Mojo::Template->new;
  my $file   = curfile->sibling('templates', 'exception.mt');
  my $output = $mt->name('"foo.mt" from DATA section')->render_file($file);
  isa_ok $output, 'Mojo::Exception', 'right exception';
  like $output->message, qr/foo\.mt from DATA section line 2/, 'message contains filename';
  is $output->lines_before->[0][0], 1,        'right number';
  is $output->lines_before->[0][1], 'test',   'right line';
  is $output->line->[0],            2,        'right number';
  is $output->line->[1],            '% die;', 'right line';
  is $output->lines_after->[0][0],  3,        'right number';
  is $output->lines_after->[0][1],  '123',    'right line';
  like "$output", qr/foo\.mt from DATA section line 2/, 'right result';
};

subtest 'Exception with UTF-8 context' => sub {
  my $mt     = Mojo::Template->new;
  my $file   = curfile->sibling('templates', 'utf8_exception.mt');
  my $output = $mt->render_file($file);
  isa_ok $output, 'Mojo::Exception', 'right exception';
  is $output->lines_before->[0][1], '☃',       'right line';
  is $output->line->[1],            '% die;♥', 'right line';
  is $output->lines_after->[0][1],  '☃',       'right line';
};

subtest 'Exception in first line with bad message' => sub {
  my $mt     = Mojo::Template->new;
  my $output = $mt->render('<% die "Test at template line 99\n"; %>');
  isa_ok $output, 'Mojo::Exception', 'right exception';
  is $output->message,           "Test at template line 99\n",              'right message';
  is $output->lines_before->[0], undef,                                     'no lines before';
  is $output->line->[0],         1,                                         'right number';
  is $output->line->[1],         '<% die "Test at template line 99\n"; %>', 'right line';
  is $output->lines_after->[0],  undef,                                     'no lines after';
};

subtest 'Different encodings' => sub {
  my $mt   = Mojo::Template->new(encoding => 'shift_jis');
  my $file = curfile->sibling('templates', 'utf8_exception.mt');
  ok !eval { $mt->render_file($file) }, 'file not rendered';
  like $@, qr/invalid encoding/, 'right error';
};

subtest 'Custom escape function' => sub {
  my $mt = Mojo::Template->new(escape => sub { '+' . $_[0] });
  is $mt->render('<%== "hi" =%>'), '+hi', 'right escaped string';
};

done_testing();
