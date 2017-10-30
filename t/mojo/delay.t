use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Promise (resolved)
my $delay = Mojo::IOLoop::Delay->new;
my (@results, @errors);
$delay->then(sub { @results = @_ }, sub { @errors = @_ });
$delay->resolve('hello', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['hello', 'world'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Promise (already resolved)
$delay = Mojo::IOLoop::Delay->new->resolve('early');
(@results, @errors) = ();
$delay->then(sub { @results = @_ }, sub { @errors = @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, ['early'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Promise (resolved with finally)
$delay   = Mojo::IOLoop::Delay->new;
@results = ();
$delay->finally(sub { @results = @_; 'fail' })->then(sub { push @results, @_ });
$delay->resolve('hello', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['hello', 'world', 'hello', 'world'], 'promise settled';

# Promise (rejected)
$delay = Mojo::IOLoop::Delay->new;
(@results, @errors) = ();
$delay->then(sub { @results = @_ }, sub { @errors = @_ });
$delay->reject('bye', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
is_deeply \@errors, ['bye', 'world'], 'promise rejected';

# Promise (rejected early)
$delay = Mojo::IOLoop::Delay->new->reject('early');
(@results, @errors) = ();
$delay->then(sub { @results = @_ }, sub { @errors = @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
is_deeply \@errors, ['early'], 'promise rejected';

# Promise (rejected with finally)
$delay  = Mojo::IOLoop::Delay->new;
@errors = ();
$delay->finally(sub { @errors = @_; 'fail' })
  ->then(undef, sub { push @errors, @_ });
$delay->reject('bye', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['bye', 'world', 'bye', 'world'], 'promise settled';

# Promise (no state change)
$delay = Mojo::IOLoop::Delay->new;
(@results, @errors) = ();
$delay->then(sub { @results = @_ }, sub { @errors = @_ });
$delay->resolve('pass')->reject('fail')->resolve('fail');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['pass'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Promise (resolved chained)
$delay   = Mojo::IOLoop::Delay->new;
@results = ();
$delay->then(sub {"$_[0]:1"})->then(sub {"$_[0]:2"})->then(sub {"$_[0]:3"})
  ->then(sub { push @results, "$_[0]:4" });
$delay->resolve('test');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['test:1:2:3:4'], 'promises resolved';

# Promise (rejected chained)
$delay  = Mojo::IOLoop::Delay->new;
@errors = ();
$delay->then(undef, sub {"$_[0]:1"})->then(undef, sub {"$_[0]:2"})
  ->then(undef, sub {"$_[0]:3"})->then(undef, sub { push @errors, "$_[0]:4" });
$delay->reject('tset');
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['tset:1:2:3:4'], 'promises rejected';

# Promise (resolved nested)
$delay = Mojo::IOLoop::Delay->new;
my $delay2 = Mojo::IOLoop::Delay->new;
@results = ();
$delay->then(sub {$delay2})->then(sub { @results = @_ });
$delay->resolve;
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
$delay2->resolve('works too');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['works too'], 'promise resolved';

# Promise (rejected nested)
$delay  = Mojo::IOLoop::Delay->new;
$delay2 = Mojo::IOLoop::Delay->new;
@errors = ();
$delay->then(undef, sub {$delay2})->then(undef, sub { @errors = @_ });
$delay->reject;
Mojo::IOLoop->one_tick;
is_deeply \@errors, [], 'promise not resolved';
$delay2->reject('hello world');
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['hello world'], 'promise rejected';

# Promise (resolved nested with finally)
$delay   = Mojo::IOLoop::Delay->new;
$delay2  = Mojo::IOLoop::Delay->new;
@results = ();
$delay->finally(sub {$delay2})->finally(sub { @results = @_ });
$delay->resolve('pass');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
$delay2->resolve('fail');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['pass'], 'promise resolved';

# Promise (exception in chain)
$delay = Mojo::IOLoop::Delay->new;
(@results, @errors) = ();
$delay->then(sub {@_})->then(sub {@_})->then(sub { die "test: $_[0]\n" })
  ->then(sub { push @results, 'fail' })->catch(sub { @errors = @_ });
$delay->resolve('works');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ["test: works\n"], 'promises rejected';

# Promise (race)
$delay  = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay2 = Mojo::IOLoop::Delay->new->then(sub {@_});
my $delay3 = Mojo::IOLoop::Delay->new->then(sub {@_});
@results = ();
$delay->race($delay2, $delay3)->then(sub { @results = @_ });
$delay2->resolve('second');
$delay3->resolve('third');
$delay->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['second'], 'promises resolved';

# Promise (rejected race)
$delay  = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay2 = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay3 = Mojo::IOLoop::Delay->new->then(sub {@_});
(@results, @errors) = ();
$delay->race($delay2, $delay3)
  ->then(sub { @results = @_ }, sub { @errors = @_ });
$delay2->reject('second');
$delay3->resolve('third');
$delay->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ['second'], 'promise rejected';

# Promise (all)
$delay  = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay2 = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay3 = Mojo::IOLoop::Delay->new->then(sub {@_});
@results = ();
$delay->all($delay2, $delay3)->then(sub { @results = @_ });
$delay2->resolve('second');
$delay3->resolve('third');
$delay->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [['first'], ['second'], ['third']], 'promises resolved';

# Promise (rejected all)
$delay  = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay2 = Mojo::IOLoop::Delay->new->then(sub {@_});
$delay3 = Mojo::IOLoop::Delay->new->then(sub {@_});
(@results, @errors) = ();
$delay->all($delay2, $delay3)
  ->then(sub { @results = @_ }, sub { @errors = @_ });
$delay2->resolve('second');
$delay3->reject('third');
$delay->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ['third'], 'promise rejected';

# Basic functionality
$delay   = Mojo::IOLoop::Delay->new;
@results = ();
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

# Steps
my $result;
$delay = Mojo::IOLoop::Delay->new;
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
    Mojo::IOLoop->next_tick(sub { $end->(undef, @numbers, 4) });
  },
  sub {
    my ($delay, @numbers) = @_;
    $result = \@numbers;
  }
)->wait;
is_deeply $result, [2, 3, 2, 1, 4, 5], 'right results';

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
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->steps(sub { $result = 'success' }, sub { $result = 'fail' });
$delay->wait;
is $result, 'success', 'right result';

# End chain after third step
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->steps(
  sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub {
    $result = 'fail';
    shift->pass;
  },
  sub { $result = 'success' },
  sub { $result = 'fail' }
)->wait;
is $result, 'success', 'right result';

# End chain after second step
@results = ();
$delay   = Mojo::IOLoop::Delay->new;
$delay->on(finish => sub { shift; push @results, [@_] });
$delay->steps(
  sub { shift->pass(23) },
  sub { shift; push @results, [@_] },
  sub { push @results, 'fail' }
)->wait;
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
$result = undef;
$delay  = Mojo::IOLoop->delay(
  sub {
    my $first  = shift;
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
is_deeply $result, [1, 2, 3, 2, 3, 2, 1, 4, 5, 6, 23, 24], 'right results';

# Exception in first step
my $failed;
$result = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->steps(sub { die 'First step!' }, sub { $result = 'failed' })
  ->catch(sub { $failed = shift })->wait;
like $failed, qr/^First step!/, 'right error';
ok !$result, 'no result';

# Exception in last step
$failed = undef;
$delay  = Mojo::IOLoop::Delay->new;
$delay->steps(sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub { die 'Last step!' })->catch(sub { $failed = pop })->wait;
like $failed, qr/^Last step!/, 'right error';

# Exception in second step
($failed, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->steps(
  sub {
    my $end = shift->begin;
    Mojo::IOLoop->next_tick(
      sub {
        $result = 'pass';
        $end->();
      }
    );
  },
  sub { die 'Second step!' },
  sub { $result = 'failed' }
);
$delay->catch(sub { $failed = shift })->wait;
like $failed, qr/^Second step!/, 'right error';
is $result,   'pass',            'right result';

# Exception in second step (with active event)
($failed, $result) = ();
$delay = Mojo::IOLoop::Delay->new;
$delay->steps(
  sub { Mojo::IOLoop->next_tick(shift->begin) },
  sub {
    Mojo::IOLoop->next_tick(sub { Mojo::IOLoop->stop });
    Mojo::IOLoop->next_tick(shift->begin);
    die 'Second step!';
  },
  sub { $result = 'failed' }
)->catch(sub { $failed = shift });
Mojo::IOLoop->start;
like $failed, qr/^Second step!/, 'right error';
ok !$result, 'no result';

done_testing();
