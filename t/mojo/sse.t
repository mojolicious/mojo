use Mojo::Base -strict;

use Test::More;
use Mojo::SSE  qw(build_event parse_event);
use Mojo::Util qw(encode);

subtest 'Simple event roundtrip' => sub {
  my $bytes = build_event {type => 'foo', text => 'bar', id => 23};
  is $bytes, "event: foo\x0d\x0adata: bar\x0d\x0aid: 23\x0d\x0a\x0d\x0a", 'right event';
  my $event = parse_event \(my $dummy = $bytes);
  is $event->{type}, 'foo', 'right event type';
  is $event->{text}, 'bar', 'right event text';
  is $event->{id},   23,    'right event id';
};

subtest 'No id and type' => sub {
  my $bytes = build_event {text => 'bar'};
  is $bytes, "data: bar\x0d\x0a\x0d\x0a", 'right event';
  my $event = parse_event \(my $dummy = $bytes);
  is $event->{type}, 'message', 'default event type';
  is $event->{text}, 'bar',     'right event text';
  is $event->{id},   undef,     'no event id';
};

subtest 'Unicode roundtrip' => sub {
  my $bytes = build_event {type => 'fo♥o', text => 'I ♥ Mojolicious', id => '1♥3'};
  my $event = parse_event \(my $dummy = $bytes);
  is $event->{type}, 'fo♥o',            'right event type';
  is $event->{text}, 'I ♥ Mojolicious', 'right event text';
  is $event->{id},   '1♥3',             'right event id';
};

subtest 'Event with multiple data sections' => sub {
  my $event = parse_event \(my $dummy = "data: YHOO\x0d\x0adata: +2\x0d\x0adata: 10\x0d\x0a\x0d\x0a");
  is $event->{type}, 'message',      'right event type';
  is $event->{text}, "YHOO\n+2\n10", 'right event text';
  is $event->{id},   undef,          'no event id';
};

subtest 'Multiple lines' => sub {
  my $buffer = "data: This is the first message.\x0a\x0adata: This is the second message, it\x0a"
    . "data: has two lines.\x0a\x0adata: This is the third message.\x0a\x0a";
  my $event1 = parse_event \$buffer;
  is $event1->{type}, 'message',                    'right event type';
  is $event1->{text}, 'This is the first message.', 'right event text';
  is $event1->{id},   undef,                        'no event id';
  my $event2 = parse_event \$buffer;
  is $event2->{type}, 'message',                                        'right event type';
  is $event2->{text}, "This is the second message, it\nhas two lines.", 'right event text';
  is $event2->{id},   undef,                                            'no event id';
  my $event3 = parse_event \$buffer;
  is $event3->{type},       'message',                    'right event type';
  is $event3->{text},       'This is the third message.', 'right event text';
  is $event3->{id},         undef,                        'no event id';
  is parse_event(\$buffer), undef,                        'no more events';
};

subtest 'Event types' => sub {
  my $buffer
    = "event: add\x0ddata: 73857293\x0d\x0devent: remove\x0ddata: 2153\x0d\x0devent: add\x0ddata: 113411\x0d\x0d";
  my $event1 = parse_event \$buffer;
  is $event1->{type}, 'add',    'right event type';
  is $event1->{text}, 73857293, 'right event text';
  is $event1->{id},   undef,    'no event id';
  my $event2 = parse_event \$buffer;
  is $event2->{type}, 'remove', 'right event type';
  is $event2->{text}, 2153,     'right event text';
  is $event2->{id},   undef,    'no event id';
  my $event3 = parse_event \$buffer;
  is $event3->{type},       'add',  'right event type';
  is $event3->{text},       113411, 'right event text';
  is $event3->{id},         undef,  'no event id';
  is parse_event(\$buffer), undef,  'no more events';
};

subtest 'Insignificant whitespace' => sub {
  my $buffer = "data:test\x0d\x0a\x0d\x0adata: test\x0d\x0a\x0d\x0a";
  my $event1 = parse_event \$buffer;
  is $event1->{type}, 'message', 'right event type';
  is $event1->{text}, 'test',    'right event text';
  is $event1->{id},   undef,     'no event id';
  my $event2 = parse_event \$buffer;
  is $event2->{type},       'message', 'right event type';
  is $event2->{text},       'test',    'right event text';
  is $event2->{id},         undef,     'no event id';
  is parse_event(\$buffer), undef,     'no more events';
};

subtest 'Events with comment' => sub {
  my $buffer
    = ": test stream\x0a\x0ddata: first event\x0did: 1\x0d\x0ddata:second event\x0did\x0d\x0ddata:  third event\x0a\x0a";
  my $event1 = parse_event \$buffer;
  is $event1->{type}, 'message',     'right event type';
  is $event1->{text}, 'first event', 'right event text';
  is $event1->{id},   1,             'right event id';
  my $event2 = parse_event \$buffer;
  is $event2->{type}, 'message',      'right event type';
  is $event2->{text}, 'second event', 'right event text';
  is $event2->{id},   undef,          'no event id';
  my $event3 = parse_event \$buffer;
  is $event3->{type},       'message',     'right event type';
  is $event3->{text},       'third event', 'right event text';
  is $event3->{id},         undef,         'no event id';
  is parse_event(\$buffer), undef,         'no more events';
};

subtest 'Lots of data' => sub {
  my $buffer = "data\x0a\x0adata\x0adata\x0a\x0adata:\x0a\x0a";
  my $event1 = parse_event \$buffer;
  is $event1->{type}, 'message', 'right event type';
  is $event1->{text}, '',        'right event text';
  is $event1->{id},   undef,     'no event id';
  my $event2 = parse_event \$buffer;
  is $event2->{type}, 'message', 'right event type';
  is $event2->{text}, "\n",      'right event text';
  is $event2->{id},   undef,     'no event id';
  my $event3 = parse_event \$buffer;
  is $event3->{type},       'message', 'right event type';
  is $event3->{text},       '',        'right event text';
  is $event3->{id},         undef,     'no event id';
  is parse_event(\$buffer), undef,     'no more events';
};

subtest 'Comments' => sub {
  my $buffer = build_event {comment => 'This is a comment'};
  is $buffer,               ": This is a comment\x0d\x0a\x0d\x0a", 'right event';
  is parse_event(\$buffer), undef,                                 'no event';
  is $buffer,               '',                                    'buffer is empty';

  $buffer = build_event {comment => "This will be\x0atwo comments"};
  is $buffer,               ": This will be\x0d\x0a: two comments\x0d\x0a\x0d\x0a", 'right event';
  is parse_event(\$buffer), undef,                                                  'no event';
  is $buffer,               '',                                                     'buffer is empty';
};

subtest 'Unallowed characters' => sub {
  my $buffer = build_event {type => 'foo', text => "bar\x0abaz"};
  is $buffer, "event: foo\x0d\x0adata: bar\x0d\x0adata: baz\x0d\x0a\x0d\x0a", 'right event';
  my $event = parse_event \$buffer;
  is $event->{type}, 'foo',      'right event type';
  is $event->{text}, "bar\nbaz", 'right event text';
  is $event->{id},   undef,      'no event id';
  is $buffer,        '',         'buffer is empty';

  $buffer = build_event {type => 'foo', text => "bar\x0dbaz"};
  is $buffer, "event: foo\x0d\x0adata: bar\x0d\x0adata: baz\x0d\x0a\x0d\x0a", 'right event';
  $event = parse_event \$buffer;
  is $event->{type}, 'foo',      'right event type';
  is $event->{text}, "bar\nbaz", 'right event text';
  is $event->{id},   undef,      'no event id';
  is $buffer,        '',         'buffer is empty';

  $buffer = build_event {type => 'foo', text => "bar\x0d\x0abaz"};
  is $buffer, "event: foo\x0d\x0adata: bar\x0d\x0adata: baz\x0d\x0a\x0d\x0a", 'right event';
  $event = parse_event \$buffer;
  is $event->{type}, 'foo',      'right event type';
  is $event->{text}, "bar\nbaz", 'right event text';
  is $event->{id},   undef,      'no event id';
  is $buffer,        '',         'buffer is empty';
};

done_testing();
