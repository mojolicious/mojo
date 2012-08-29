use Mojo::Base -strict;

use Test::More tests => 46;

use Mojo::EventEmitter;

# Normal event
my $e = Mojo::EventEmitter->new;
my $called;
$e->on(test1 => sub { $called++ });
$e->emit('test1');
is $called, 1, 'event was emitted once';

# Error
$e->on(die => sub { die "works!\n" });
eval { $e->emit('die') };
is $@, "works!\n", 'right error';

# Error fallback
my ($echo, $err);
$e->on(error => sub { $err = pop });
$e->on(test2 => sub { $echo .= 'echo: ' . pop });
$e->on(
  test2 => sub {
    my ($self, $msg) = @_;
    die "test2: $msg\n";
  }
);
my $cb = sub { $echo .= 'echo2: ' . pop };
$e->on(test2 => $cb);
$e->emit_safe('test2', 'works!');
is $echo, 'echo: works!echo2: works!', 'right echo';
is $err, qq{Event "test2" failed: test2: works!\n}, 'right error';
$echo = $err = undef;
is scalar @{$e->subscribers('test2')}, 3, 'three subscribers';
$e->unsubscribe(test2 => $cb);
is scalar @{$e->subscribers('test2')}, 2, 'two subscribers';
$e->emit_safe('test2', 'works!');
is $echo, 'echo: works!', 'right echo';
is $err, qq{Event "test2" failed: test2: works!\n}, 'right error';

# Normal event again
$e->emit('test1');
is $called, 2, 'event was emitted twice';
is scalar @{$e->subscribers('test1')}, 1, 'one subscriber';
$e->emit('test1');
$e->unsubscribe(test1 => $e->subscribers('test1')->[0]);
is $called, 3, 'event was emitted three times';
is scalar @{$e->subscribers('test1')}, 0, 'no subscribers';
$e->emit('test1');
is $called, 3, 'event was not emitted again';
$e->emit('test1');
is $called, 3, 'event was not emitted again';

# One time event
my $once;
$e->once(one_time => sub { $once++ });
is scalar @{$e->subscribers('one_time')}, 1, 'one subscriber';
$e->emit('one_time');
is $once, 1, 'event was emitted once';
is scalar @{$e->subscribers('one_time')}, 0, 'no subscribers';
$e->emit('one_time');
is $once, 1, 'event was not emitted again';
$e->emit('one_time');
is $once, 1, 'event was not emitted again';
$e->emit('one_time');
is $once, 1, 'event was not emitted again';
$e->once(
  one_time => sub {
    shift->once(one_time => sub { $once++ });
  }
);
$e->emit('one_time');
is $once, 1, 'event was emitted once';
$e->emit('one_time');
is $once, 2, 'event was emitted again';
$e->emit('one_time');
is $once, 2, 'event was not emitted again';
$e->once(one_time => sub { $once = shift->has_subscribers('one_time') });
$e->emit('one_time');
ok !$once, 'no subscribers';

# Nested one time events
$once = 0;
$e->once(
  one_time => sub {
    shift->once(
      one_time => sub {
        shift->once(one_time => sub { $once++ });
      }
    );
  }
);
is scalar @{$e->subscribers('one_time')}, 1, 'one subscriber';
$e->emit('one_time');
is $once, 0, 'only first event was emitted';
is scalar @{$e->subscribers('one_time')}, 1, 'one subscriber';
$e->emit('one_time');
is $once, 0, 'only second event was emitted';
is scalar @{$e->subscribers('one_time')}, 1, 'one subscriber';
$e->emit('one_time');
is $once, 1, 'third event was emitted';
is scalar @{$e->subscribers('one_time')}, 0, 'no subscribers';
$e->emit('one_time');
is $once, 1, 'event was not emitted again';
$e->emit('one_time');
is $once, 1, 'event was not emitted again';
$e->emit('one_time');
is $once, 1, 'event was not emitted again';

# Unsubscribe
$e = Mojo::EventEmitter->new;
my $counter;
$cb = $e->on(foo => sub { $counter++ });
$e->on(foo => sub { $counter++ });
$e->on(foo => sub { $counter++ });
$e->unsubscribe(foo => $e->once(foo => sub { $counter++ }));
is scalar @{$e->subscribers('foo')}, 3, 'three subscribers';
$e->emit('foo')->unsubscribe(foo => $cb);
is $counter, 3, 'event was emitted three times';
is scalar @{$e->subscribers('foo')}, 2, 'two subscribers';
$e->emit('foo');
is $counter, 5, 'event was emitted two times';
ok $e->has_subscribers('foo'), 'has subscribers';
ok !$e->unsubscribe('foo')->has_subscribers('foo'), 'no subscribers';
is scalar @{$e->subscribers('foo')}, 0, 'no subscribers';
$e->emit('foo');
is $counter, 5, 'event was not emitted again';

# Pass by reference
$e = Mojo::EventEmitter->new;
my $buffer = '';
$e->on(one => sub { $_[1] .= 'abc' . $_[2] });
$e->on(one => sub { $_[1] .= '123' . pop });
is $buffer, '', 'right result';
$e->emit(one => $buffer => 'two');
is $buffer, 'abctwo123two', 'right result';
$e->once(one => sub { $_[1] .= 'def' });
$e->emit(one => $buffer => 'three');
is $buffer, 'abctwo123twoabcthree123threedef', 'right result';
$e->emit(one => $buffer => 'x');
is $buffer, 'abctwo123twoabcthree123threedefabcx123x', 'right result';
