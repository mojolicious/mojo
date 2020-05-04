use Mojo::Base -strict;
use Test::More;
use Mojo::DOM;
use ojo 'x';

# API tests, void context
x('')->walk(sub {
  isa_ok $_,   'Mojo::DOM';
  is $_->type, 'root', 'DOM root';
  is @_,       2,      'two args';
  is $_[0],    $_,     'first arg: node';
  is $_[1],    0,      'second arg: depth';
});
x('')->walk(sub {
  is @_,          3,      'three args';
  is $_[0]->type, 'root', 'first arg: node';
  is $_[1],       0,      'second arg: depth';
  is $_[2],       'abc',  'third arg: passed thru';
}, 'abc');
{
  my $dom = x('<div>a</div>');
  $dom->walk('append','x');
  is $dom->to_string, '<div>ax</div>x', 'method call with args';
}

# API tests, non-void context
isa_ok x('')->walk(sub {
  isa_ok $_,   'Mojo::DOM';
  is $_->type, 'root', 'DOM root';
  is @_,       2,      'two args';
  is $_[0],    $_,     'first arg: node';
  is $_[1],    0,      'second arg: depth';
}), 'Mojo::Collection';
isa_ok x('')->walk(sub {
  is @_,          3,      'three args';
  is $_[0]->type, 'root', 'first arg: node';
  is $_[1],       0,      'second arg: depth';
  is $_[2],       'abc',  'third arg: passed thru';
}, 'abc'), 'Mojo::Collection';
{
  my $dom = x('<div>a</div>');
  isa_ok $dom->walk('append','x'), 'Mojo::Collection';
  is $dom->to_string, '<div>ax</div>x', 'method call with args';
}
{
  my $c = x('<b>a<i>b</i>c</b>')->walk(sub {});
  isa_ok $c, 'Mojo::Collection';
  is_deeply $c, [], 'callback returning nothing' or diag explain $c;
}

# Test several use cases
my $dom = Mojo::DOM->new(<<'END_HTML');
<!doctype html>
<html lang="en">
<head>
	<meta charset="utf-8">
	<title>Testing</title>
	<style>body { margin: 1em; }</style>
	<script>alert('Hello, World!');</script>
</head>
<body>
	<h1>Example</h1>
	<p>Foo <button id="my_button">Bar!</button></p>
	<div id="test">Quz</div>
</body>
</html>
END_HTML

my $types = $dom->walk('type');
is_deeply $types, [
    'root',
    ['doctype'],              # doctype
    ['text'],                 # WS
    [ 'tag',                  # html
      ['text'],               # WS
      [ 'tag',                # head
        ['text'],             # WS
        ['tag'],              # meta
        ['text'],             # WS
        ['tag', ['raw']],     # title
        ['text'],             # WS
        ['tag', ['raw']],     # style
        ['text'],             # WS
        ['tag', ['raw']],     # script
        ['text'],             # WS
      ],
      ['text'],               # WS
      [ 'tag',                # body
        ['text'],             # WS
        ['tag', ['text']],    # h1
        ['text'],             # WS
        [ 'tag', ['text'],    # p
          ['tag', ['text']],  # button
        ],
        ['text'],             # WS
        ['tag', ['text']],    # div
        ['text'],             # WS
      ],
      ['text'],               # WS
    ],
    ['text'],                 # WS
  ], 'type method' or diag explain $types;

my @texts;
$dom->at('body')->walk(sub {
  my ($node, $depth) = @_;
  push @texts, [$depth, $node->content] if $node->type eq 'text';
});
is_deeply \@texts, [
    [1, "\n\t"],
      [2, "Example"],
    [1, "\n\t"],
      [2, "Foo "],
        [3, "Bar!"],
    [1, "\n\t"],
      [2, "Quz"],
    [1, "\n"],
  ], 'text nodes' or diag explain \@texts;

my $selectors = $dom->walk('selector')->flatten->grep(sub {defined});
is_deeply $selectors, [
    'html:nth-child(1)',
    'html:nth-child(1) > head:nth-child(1)',
    'html:nth-child(1) > head:nth-child(1) > meta:nth-child(1)',
    'html:nth-child(1) > head:nth-child(1) > title:nth-child(2)',
    'html:nth-child(1) > head:nth-child(1) > style:nth-child(3)',
    'html:nth-child(1) > head:nth-child(1) > script:nth-child(4)',
    'html:nth-child(1) > body:nth-child(2)',
    'html:nth-child(1) > body:nth-child(2) > h1:nth-child(1)',
    'html:nth-child(1) > body:nth-child(2) > p:nth-child(2)',
    'html:nth-child(1) > body:nth-child(2) > p:nth-child(2) > button:nth-child(1)',
    'html:nth-child(1) > body:nth-child(2) > div:nth-child(3)'
  ], 'selectors' or diag explain $selectors;

my $struct_texts = $dom->walk(sub {
  if ($_->type =~ /^(text|cdata|raw)$/ && $_->content =~ /\S/) {
    ( my $txt = $_->content ) =~ s/^\s+|\s+$//g;
    return $txt;
  } else { return }
});
is_deeply $struct_texts, [
    [                                     # html
      [                                   # head
        [['Testing']],                    # title
        [['body { margin: 1em; }']],      # style
        [["alert('Hello, World!');"]],    # script
      ],
      [                                   # body
        [['Example']],                    # h1
        [
          ['Foo'],                        # p
          [['Bar!']],                     # button
        ],
        [['Quz']],                        # div
      ],
    ],
  ], 'text nodes, nested, no ws' or diag explain $struct_texts;

if (0) {
  diag "Running benchmark...";
  require Benchmark;
  Benchmark::cmpthese(-3, {
         void => sub {         $dom->walk(sub { $_->type }); 1 },
      nonvoid => sub { my $x = $dom->walk(sub { $_->type })    },
    });
}

done_testing;
