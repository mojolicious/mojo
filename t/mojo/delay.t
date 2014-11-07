use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Basic functionality
my $delay = Mojo::IOLoop::Delay->new;
my @results;
for my $i (1, 1) {
  my $end = $delay->begin;
  Mojo::IOLoop->next_tick(sub { push @results, $i; $end->() });
}
my $end  = $delay->begin;
my $end2 = $delay->begin;
$end->();
$end2->();
$delay->wait;
is_deeply \@results, [1, 1], 'right results';

# Argument splicing
$delay = Mojo::IOLoop::Delay->new;
Mojo::IOLoop->next_tick($delay->begin);
$delay->begin(1)->(1, 2, 3);
$delay->begin(1, 1)->(4, 5, 6);
$delay->begin(0, 1)->(7, 8);
$delay->begin(2)->(9, 10, 11);
$delay->begin(0, 0)->(12, 13);
$delay->begin(0, 2)->(14, 15, 16);
$delay->begin(2, 5)->(17, 18, 19, 20);
my @numbers;
$delay->steps(sub { (undef, @numbers) = @_ })->wait;
is_deeply \@numbers, [2, 3, 5, 7, 11, 14, 15, 19, 20], 'right values';

# Data
is $delay->data('foo'), undef, 'no value';
is_deeply $delay->data(foo => 'bar')->data, {foo => 'bar'}, 'right value';
is $delay->data('foo'), 'bar', 'right value';
delete $delay->data->{foo};
is $delay->data('foo'), undef, 'no value';
$delay->data(foo => 'bar', baz => 'yada');
is $delay->data({test => 23})->data->{test}, 23, 'right value';
is_deeply $delay->data, {foo => 'bar', baz => 'yada', test => 23},
  'right value';

# Steps
my ($finished, $result);
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub {
    my $delay = shift;
    my $end   = $delay->begin;
    $delay->begin->(3, 2, 1);
    Mojo::IOLoop->next_tick(sub { $end->(1, 2, 3)->pass(5) });
  },
  sub {
    my ($delay, @numbers) = @_;
    my $end = $delay->begin;
    Mojo::IOLoop->next_tick(
      sub { $end->(undef, @numbers, 4)->data(foo => 'bar') });
  },
  sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
)->wait;
is $finished, 1, 'finish event has been emitted once';
is_deeply $result, [2, 3, 2, 1, 4, 5], 'right results';
is $delay->data('foo'), 'bar', 'right value';

# One step
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->steps(sub { ++$result });
$delay->begin->();
is $result, undef, 'no result';
Mojo::IOLoop->next_tick($delay->begin);
is $result, undef, 'no result';
$end = $delay->begin;
Mojo::IOLoop->next_tick(sub { $end->() });
is $result, undef, 'no result';
$delay->wait;
is $result, 1, 'right result';

# One step (reverse)
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$end    = $delay->begin(0);
Mojo::IOLoop->next_tick(sub { $end->(23) });
$delay->steps(sub { $result = pop });
is $result, undef, 'no result';
$delay->wait;
is $result, 23, 'right result';

# End chain after first step
($finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(sub { $result = 'success' }, sub { $result = 'fail' });
$delay->wait;
is $finished, 1,         'finish event has been emitted once';
is $result,   'success', 'right result';

# End chain after third step
($finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub {
    $result = 'fail';
    shift->pass;
  },
  sub { $result = 'success' },
  sub { $result = 'fail' }
)->wait;
is $finished, 1,         'finish event has been emitted once';
is $result,   'success', 'right result';

# End chain after second step
@results = ();
$delay   = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { shift; push @results, [@_] });
$delay->steps(
  sub { shift->pass(23) },
  sub { shift; push @results, [@_] },
  sub { push @results, 'fail' }
)->wait;
is_deeply $delay->remaining, [], 'no remaining steps';
is_deeply \@results, [[23], [23]], 'right results';

# Finish steps with event
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->on(
  finish => sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
);
$delay->steps(
  sub {
    my $delay = shift;
    my $end   = $delay->begin;
    Mojo::IOLoop->next_tick(sub { $end->(1, 2, 3) });
  },
  sub {
    my ($delay, @numbers) = @_;
    my $end = $delay->begin;
    Mojo::IOLoop->next_tick(sub { $end->(undef, @numbers, 4) });
  }
)->wait;
is_deeply $result, [2, 3, 4], 'right results';

# Nested delays
($finished, $result) = ();
$delay = Mojo::IOLoop->delay(
  sub {
    my $first = shift;
    $first->on(finish => sub { $finished++ });
    my $second = Mojo::IOLoop->delay($first->begin);
    Mojo::IOLoop->next_tick($second->begin);
    Mojo::IOLoop->next_tick($first->begin);
    my $end = $second->begin(0);
    Mojo::IOLoop->next_tick(sub { $end->(1, 2, 3) });
  },
  sub {
    my ($first, @numbers) = @_;
    $result = \@numbers;
    my $end = $first->begin;
    $first->begin->(3, 2, 1);
    my $end2 = $first->begin(0);
    my $end3 = $first->begin(0);
    $end2->(4);
    $end3->(5, 6);
    $first->pass(23)->pass(24);
    $end->(1, 2, 3);
  },
  sub {
    my ($first, @numbers) = @_;
    push @$result, @numbers;
  }
)->wait;
is $finished, 1, 'finish event has been emitted once';
is_deeply $result, [1, 2, 3, 2, 3, 2, 1, 4, 5, 6, 23, 24], 'right results';

# Dynamic step
my $double = sub {
  my ($delay, $num) = @_;
  my $end = $delay->begin(0);
  Mojo::IOLoop->next_tick(sub { $end->($num * 2) });
};
$result = undef;
$delay = Mojo::IOLoop::Delay->new->data(num => 9)->steps(
  sub {
    my $delay = shift;
    my $end   = $delay->begin(0);
    Mojo::IOLoop->next_tick(sub { $end->($delay->data('num')) });
    unshift @{$delay->remaining}, $double;
  },
  sub {
    my ($delay, $num) = @_;
    $result = $num;
  }
);
is scalar @{$delay->remaining}, 2, 'two steps remaining';
$delay->wait;
is scalar @{$delay->remaining}, 0, 'no steps remaining';
is $delay->data('num'), 9, 'right value';
is $result, 18, 'right result';

# Exception in first step
my $failed;
($finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(error => sub { $failed = pop });
$delay->on(finish => sub { $finished++ });
$delay->steps(sub { die 'First step!' }, sub { $result = 'failed' })->wait;
is_deeply $delay->remaining, [], 'no remaining steps';
like $failed, qr/^First step!/, 'right error';
ok !$finished, 'finish event has not been emitted';
ok !$result,   'no result';

# Exception in last step
($failed, $finished) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(error => sub { $failed = pop });
$delay->on(finish => sub { $finished++ });
$delay->steps(sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub { die 'Last step!' })->wait;
is_deeply $delay->remaining, [], 'no remaining steps';
like $failed, qr/^Last step!/, 'right error';
ok !$finished, 'finish event has not been emitted';

# Exception in second step
($failed, $finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub {
    my $end = shift->begin;
    Mojo::IOLoop->next_tick(sub { $end->()->data(foo => 'bar') });
  },
  sub { die 'Second step!' },
  sub { $result = 'failed' }
)->catch(sub { $failed = pop })->wait;
is_deeply $delay->remaining, [], 'no remaining steps';
like $failed, qr/^Second step!/, 'right error';
ok !$finished, 'finish event has not been emitted';
ok !$result,   'no result';
is $delay->data('foo'), 'bar', 'right value';

# Exception in second step (with active event)
($failed, $finished, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->on(error => sub { $failed = pop });
$delay->on(finish => sub { $finished++ });
$delay->steps(
  sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub {
    Mojo::IOLoop->next_tick(sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->next_tick(shift->begin);
    die 'Second step!';
  },
  sub { $result = 'failed' }
);
Mojo::IOLoop->start;
is_deeply $delay->remaining, [], 'no remaining steps';
like $failed, qr/^Second step!/, 'right error';
ok !$finished, 'finish event has not been emitted';
ok !$result,   'no result';

# Fatal exception in second step
Mojo::IOLoop->singleton->reactor->unsubscribe('error');
$delay = Mojo::IOLoop::Delay->new;
ok !$delay->has_subscribers('error'), 'no subscribers';
$delay->steps(sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub { die 'Oops!' });
eval { $delay->wait };
like $@, qr/Oops!/, 'right error';

done_testing();
