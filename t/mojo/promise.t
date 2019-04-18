use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Mojo::Promise;

# Resolved
my $promise = Mojo::Promise->new;
my (@results, @errors);
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
$promise->resolve('hello', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['hello', 'world'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';
$promise = Mojo::Promise->resolve('test');
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, ['test'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Already resolved
$promise = Mojo::Promise->new->resolve('early');
(@results, @errors) = ();
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, ['early'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Resolved with finally
$promise = Mojo::Promise->new;
@results = ();
$promise->finally(sub { @results = @_; 'fail' })
  ->then(sub { push @results, @_ });
$promise->resolve('hello', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['hello', 'world', 'hello', 'world'], 'promise settled';

# Rejected
$promise = Mojo::Promise->new;
(@results, @errors) = ();
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
$promise->reject('bye', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
is_deeply \@errors, ['bye', 'world'], 'promise rejected';
$promise = Mojo::Promise->reject('test');
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
is_deeply \@errors, ['test'], 'promise rejected';

# Rejected early
$promise = Mojo::Promise->new->reject('early');
(@results, @errors) = ();
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
is_deeply \@errors, ['early'], 'promise rejected';

# Rejected with finally
$promise = Mojo::Promise->new;
@errors  = ();
$promise->finally(sub { @errors = @_; 'fail' })
  ->then(undef, sub { push @errors, @_ });
$promise->reject('bye', 'world');
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['bye', 'world', 'bye', 'world'], 'promise settled';

# No state change
$promise = Mojo::Promise->new;
(@results, @errors) = ();
$promise->then(sub { @results = @_ }, sub { @errors = @_ });
$promise->resolve('pass')->reject('fail')->resolve('fail');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['pass'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Resolved chained
$promise = Mojo::Promise->new;
@results = ();
$promise->then(sub {"$_[0]:1"})->then(sub {"$_[0]:2"})->then(sub {"$_[0]:3"})
  ->then(sub { push @results, "$_[0]:4" });
$promise->resolve('test');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['test:1:2:3:4'], 'promises resolved';

# Rejected chained
$promise = Mojo::Promise->new;
@errors  = ();
$promise->then(undef, sub {"$_[0]:1"})
  ->then(sub {"$_[0]:2"}, sub {"$_[0]:fail"})->then(sub {"$_[0]:3"})
  ->then(sub { push @errors, "$_[0]:4" });
$promise->reject('tset');
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['tset:1:2:3:4'], 'promises rejected';

# Resolved nested
$promise = Mojo::Promise->new;
my $promise2 = Mojo::Promise->new;
@results = ();
$promise->then(sub {$promise2})->then(sub { @results = @_ });
$promise->resolve;
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promise not resolved';
$promise2->resolve('works too');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['works too'], 'promise resolved';

# Rejected nested
$promise  = Mojo::Promise->new;
$promise2 = Mojo::Promise->new;
@errors   = ();
$promise->then(undef, sub {$promise2})->then(undef, sub { @errors = @_ });
$promise->reject;
Mojo::IOLoop->one_tick;
is_deeply \@errors, [], 'promise not resolved';
$promise2->reject('hello world');
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['hello world'], 'promise rejected';

# Double finally
$promise = Mojo::Promise->new;
@results = ();
$promise->finally(sub { push @results, "@{_}s" })
  ->finally(sub { push @results, "@{_}ss" });
$promise->resolve('pass');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['passs', 'passss'], 'promise not resolved';

# Resolved nested with finally
$promise  = Mojo::Promise->new;
$promise2 = Mojo::Promise->new;
@results  = ();
$promise->finally(sub {$promise2})->finally(sub { @results = @_ });
$promise->resolve('pass');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['pass'], 'promise already resolved';

# Exception in finally
$promise = Mojo::Promise->new;
@results = ();
$promise->finally(sub { die "Test!\n" })->catch(sub { push @results, @_ });
$promise->resolve('pass');
Mojo::IOLoop->one_tick;
is_deeply \@results, ["Test!\n"], 'promise rejected';

# Clone
my $loop = Mojo::IOLoop->new;
$promise  = Mojo::Promise->new(ioloop => $loop)->resolve('failed');
$promise2 = $promise->clone;
(@results, @errors) = ();
$promise2->then(sub { @results = @_ }, sub { @errors = @_ });
$promise2->resolve('success');
is $loop, $promise2->ioloop, 'same loop';
$loop->one_tick;
is_deeply \@results, ['success'], 'promise resolved';
is_deeply \@errors, [], 'promise not rejected';

# Exception in chain
$promise = Mojo::Promise->new;
(@results, @errors) = ();
$promise->then(sub {@_})->then(sub {@_})->then(sub { die "test: $_[0]\n" })
  ->then(sub { push @results, 'fail' })->catch(sub { @errors = @_ });
$promise->resolve('works');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ["test: works\n"], 'promises rejected';

# Race
$promise  = Mojo::Promise->new->then(sub {@_});
$promise2 = Mojo::Promise->new->then(sub {@_});
my $promise3 = Mojo::Promise->new->then(sub {@_});
@results = ();
Mojo::Promise->race($promise2, $promise, $promise3)
  ->then(sub { @results = @_ });
$promise2->resolve('second');
$promise3->resolve('third');
$promise->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, ['second'], 'promises resolved';

# Rejected race
$promise  = Mojo::Promise->new->then(sub {@_});
$promise2 = Mojo::Promise->new->then(sub {@_});
$promise3 = Mojo::Promise->new->then(sub {@_});
(@results, @errors) = ();
Mojo::Promise->race($promise, $promise2, $promise3)
  ->then(sub { @results = @_ }, sub { @errors = @_ });
$promise2->reject('second');
$promise3->resolve('third');
$promise->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ['second'], 'promise rejected';

# Timeout
(@errors, @results) = @_;
$promise = Mojo::Promise->timeout(0.25 => 'Timeout1');
$promise2 = Mojo::Promise->new->timeout(0.025 => 'Timeout2');
$promise3
  = Mojo::Promise->race($promise, $promise2)->then(sub { @results = @_ })
  ->catch(sub { @errors = @_ })->wait;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ['Timeout2'], 'promise rejected';

# Timeout with default message
@errors = ();
Mojo::Promise->timeout(0.025)->catch(sub { @errors = @_ })->wait;
is_deeply \@errors, ['Promise timeout'], 'default timeout message';

# Timer without value
@results = ();
Mojo::Promise->timer(0.025)->then(sub { @results = (@_, 'works!') })->wait;
is_deeply \@results, ['works!'], 'default timer result';

# Timer with values
@results = ();
Mojo::Promise->new->timer(0, 'first', 'second')
  ->then(sub { @results = (@_, 'works too!') })->wait;
is_deeply \@results, ['first', 'second', 'works too!'], 'timer result';

# All
$promise  = Mojo::Promise->new->then(sub {@_});
$promise2 = Mojo::Promise->new->then(sub {@_});
$promise3 = Mojo::Promise->new->then(sub {@_});
@results  = ();
Mojo::Promise->all($promise, $promise2, $promise3)->then(sub { @results = @_ });
$promise2->resolve('second');
$promise3->resolve('third');
$promise->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [['first'], ['second'], ['third']], 'promises resolved';

# Rejected all
$promise  = Mojo::Promise->new->then(sub {@_});
$promise2 = Mojo::Promise->new->then(sub {@_});
$promise3 = Mojo::Promise->new->then(sub {@_});
(@results, @errors) = ();
Mojo::Promise->all($promise, $promise2, $promise3)
  ->then(sub { @results = @_ }, sub { @errors = @_ });
$promise2->resolve('second');
$promise3->reject('third');
$promise->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [], 'promises not resolved';
is_deeply \@errors, ['third'], 'promise rejected';

# Settle with promise
$promise  = Mojo::Promise->new->resolve('works');
@results  = ();
$promise2 = Mojo::Promise->new->resolve($promise)
  ->then(sub { push @results, 'first', @_; @_ });
$promise2->then(sub { push @results, 'second', @_ });
Mojo::IOLoop->one_tick;
is_deeply \@results, ['first', 'works', 'second', 'works'], 'promises resolved';
$promise  = Mojo::Promise->new->reject('works too');
@errors   = ();
$promise2 = Mojo::Promise->new->reject($promise)
  ->catch(sub { push @errors, 'first', @_; @_ });
$promise2->then(sub { push @errors, 'second', @_ });
Mojo::IOLoop->one_tick;
is_deeply \@errors, ['first', 'works too', 'second', 'works too'],
  'promises rejected';

# Map
my @started;
(@results, @errors) = ();
$promise = Mojo::Promise->map(sub { push @started, $_; $_ }, 1 .. 5)
  ->then(sub { @results = @_ }, sub { @errors = @_ });
is_deeply \@started, [1, 2, 3, 4, 5], 'all started without concurrency';
$promise->wait;
is_deeply \@results, [[1], [2], [3], [4], [5]], 'correct result';
is_deeply \@errors, [], 'promise not rejected';

# Map (with concurrency limit)
my $concurrent = 0;
(@results, @errors) = ();
Mojo::Promise->map(
  {concurrency => 3},
  sub {
    my $n = $_;
    fail 'Concurrency too high' if ++$concurrent > 3;
    Mojo::Promise->resolve->then(sub {
      fail 'Concurrency too high' if $concurrent-- > 3;
      $n;
    });
  },
  1 .. 5
)->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
is_deeply \@results, [[1], [2], [3], [4], [5]], 'correct result';
is_deeply \@errors, [], 'promise not rejected';

# Map (with reject)
(@started, @results, @errors) = ();
Mojo::Promise->map(
  {concurrency => 3},
  sub {
    my $n = $_;
    push @started, $n;
    Mojo::Promise->resolve->then(sub { Mojo::Promise->reject($n) });
  },
  1 .. 5
)->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
is_deeply \@results, [], 'promise not resolved';
is_deeply \@errors, [1], 'correct errors';
is_deeply \@started, [1, 2, 3], 'only initial batch started';

# Map (custom event loop)
my $ok;
$loop = Mojo::IOLoop->new;
$promise
  = Mojo::Promise->map(sub { Mojo::Promise->new(ioloop => $loop)->resolve }, 1);
is $promise->ioloop, $loop, 'same loop';
isnt $promise->ioloop, Mojo::IOLoop->singleton, 'not the singleton';
$promise->then(sub { $ok = 1; $loop->stop });
$loop->start;
ok $ok, 'loop completed';

done_testing();
