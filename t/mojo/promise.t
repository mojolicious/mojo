use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Scalar::Util 'refaddr';

subtest 'Resolved' => sub {
  my $promise = Mojo::Promise->new;
  my (@results, @errors);
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise->resolve('hello', 'world');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['hello', 'world'], 'promise resolved';
  is_deeply \@errors,  [],                 'promise not rejected';

  $promise = Mojo::Promise->resolve('test');
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['test'], 'promise resolved';
  is_deeply \@errors,  [],       'promise not rejected';
};

subtest 'Already resolved' => sub {
  my $promise = Mojo::Promise->new->resolve('early');
  my (@results, @errors);
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['early'], 'promise resolved';
  is_deeply \@errors,  [],        'promise not rejected';
};

subtest 'Resolved with finally' => sub {
  my $promise = Mojo::Promise->new;
  my @results;
  $promise->finally(sub { @results = ('finally'); 'fail' })->then(sub { push @results, @_ });
  $promise->resolve('hello', 'world');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['finally', 'hello', 'world'], 'promise settled';
};

subtest 'Rejected' => sub {
  my $promise = Mojo::Promise->new;
  my (@results, @errors);
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise->reject('bye', 'world');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],               'promise not resolved';
  is_deeply \@errors,  ['bye', 'world'], 'promise rejected';

  $promise = Mojo::Promise->reject('test');
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],       'promise not resolved';
  is_deeply \@errors,  ['test'], 'promise rejected';
};

subtest 'Rejected early' => sub {
  my $promise = Mojo::Promise->new->reject('early');
  my (@results, @errors);
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],        'promise not resolved';
  is_deeply \@errors,  ['early'], 'promise rejected';
};

subtest 'Rejected with finally' => sub {
  my $promise = Mojo::Promise->new;
  my @errors;
  $promise->finally(sub { @errors = ('finally'); 'fail' })->then(undef, sub { push @errors, @_ });
  $promise->reject('bye', 'world');
  Mojo::IOLoop->one_tick;
  is_deeply \@errors, ['finally', 'bye', 'world'], 'promise settled';
};

subtest 'Wrap' => sub {
  my (@results, @errors);
  my $promise = Mojo::Promise->new(sub {
    my ($resolve, $reject) = @_;
    Mojo::IOLoop->timer(0 => sub { $resolve->('resolved', '!') });
  });
  $promise->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, ['resolved', '!'], 'promise resolved';
  is_deeply \@errors,  [],                'promise not rejected';

  (@results, @errors) = ();
  $promise = Mojo::Promise->new(sub {
    my ($resolve, $reject) = @_;
    Mojo::IOLoop->timer(0 => sub { $reject->('rejected', '!') });
  });
  $promise->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [],                'promise not resolved';
  is_deeply \@errors,  ['rejected', '!'], 'promise rejected';
};

subtest 'No state change' => sub {
  my $promise = Mojo::Promise->new;
  my (@results, @errors);
  $promise->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise->resolve('pass')->reject('fail')->resolve('fail');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['pass'], 'promise resolved';
  is_deeply \@errors,  [],       'promise not rejected';
};

subtest 'Resolved chained' => sub {
  my $promise = Mojo::Promise->new;
  my @results;
  $promise->then(sub {"$_[0]:1"})->then(sub {"$_[0]:2"})->then(sub {"$_[0]:3"})->then(sub { push @results, "$_[0]:4" });
  $promise->resolve('test');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['test:1:2:3:4'], 'promises resolved';
};

subtest 'Rejected chained' => sub {
  my $promise = Mojo::Promise->new;
  my @errors;
  $promise->then(undef, sub {"$_[0]:1"})->then(sub {"$_[0]:2"}, sub {"$_[0]:fail"})->then(sub {"$_[0]:3"})
    ->then(sub { push @errors, "$_[0]:4" });
  $promise->reject('tset');
  Mojo::IOLoop->one_tick;
  is_deeply \@errors, ['tset:1:2:3:4'], 'promises rejected';
};

subtest 'Resolved nested' => sub {
  my $promise  = Mojo::Promise->new;
  my $promise2 = Mojo::Promise->new;
  my @results;
  $promise->then(sub {$promise2})->then(sub { @results = @_ });
  $promise->resolve;
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [], 'promise not resolved';

  $promise2->resolve('works too');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['works too'], 'promise resolved';
};

subtest 'Rejected nested' => sub {
  my $promise  = Mojo::Promise->new;
  my $promise2 = Mojo::Promise->new;
  my @errors;
  $promise->then(undef, sub {$promise2})->then(undef, sub { @errors = @_ });
  $promise->reject;
  Mojo::IOLoop->one_tick;
  is_deeply \@errors, [], 'promise not resolved';

  $promise2->reject('hello world');
  Mojo::IOLoop->one_tick;
  is_deeply \@errors, ['hello world'], 'promise rejected';
};

subtest 'Double finally' => sub {
  my $promise = Mojo::Promise->new;
  my @results;
  $promise->finally(sub { push @results, 'finally1' })->finally(sub { push @results, 'finally2' });
  $promise->resolve('pass');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['finally1', 'finally2'], 'promise not resolved';
};

subtest 'Promise returned by finally' => sub {
  my $loop     = Mojo::IOLoop->new;
  my $promise  = Mojo::Promise->new->ioloop($loop);
  my $promise2 = Mojo::Promise->new->ioloop($loop);
  my @results;
  my $promise3 = $promise->finally(sub {
    $loop->next_tick(sub { $promise2->resolve });
    return $promise2;
  })->finally(sub { @results = ('finally') });
  $promise->resolve('pass');
  $promise3->wait;
  is_deeply \@results, ['finally'], 'promise already resolved';
};

subtest 'Promise returned by finally' => sub {
  my $promise  = Mojo::Promise->new;
  my $promise2 = Mojo::Promise->new;
  my @results;
  my $promise3 = $promise->finally(sub {
    Mojo::IOLoop->next_tick(sub { $promise2->resolve });
    return $promise2;
  })->finally(sub { @results = ('finally') });
  $promise->resolve('pass');
  $promise3->wait;
  is_deeply \@results, ['finally'], 'promise already resolved';
};

subtest 'Promise returned by finally (rejected)' => sub {
  my $promise  = Mojo::Promise->new;
  my $promise2 = Mojo::Promise->new;
  my (@results, @errors);
  my $promise3 = $promise->finally(sub {
    Mojo::IOLoop->next_tick(sub { $promise2->reject('works') });
    return $promise2;
  })->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise->resolve('failed');
  $promise3->wait;
  is_deeply \@results, [],        'promises not resolved';
  is_deeply \@errors,  ['works'], 'promises rejected';
};

subtest 'Exception in finally' => sub {
  my $promise = Mojo::Promise->new;
  my @results;
  $promise->finally(sub { die "Test!\n" })->catch(sub { push @results, @_ });
  $promise->resolve('pass');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ["Test!\n"], 'promise rejected';
};

subtest 'Clone' => sub {
  my $loop     = Mojo::IOLoop->new;
  my $promise  = Mojo::Promise->new->ioloop($loop)->resolve('failed');
  my $promise2 = $promise->clone;
  my (@results, @errors);
  $promise2->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise2->resolve('success');
  is $loop, $promise2->ioloop, 'same loop';
  $loop->one_tick;
  is_deeply \@results, ['success'], 'promise resolved';
  is_deeply \@errors,  [],          'promise not rejected';
};

subtest 'Exception in chain' => sub {
  my $promise = Mojo::Promise->new;
  my (@results, @errors);
  $promise->then(sub {@_})->then(sub {@_})->then(sub { die "test: $_[0]\n" })->then(sub { push @results, 'fail' })
    ->catch(sub { @errors = @_ });
  $promise->resolve('works');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],                'promises not resolved';
  is_deeply \@errors,  ["test: works\n"], 'promises rejected';
};

subtest 'Race' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my @results;
  Mojo::Promise->race($promise2, $promise, $promise3)->then(sub { @results = @_ });
  $promise2->resolve('second');
  $promise3->resolve('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['second'], 'promise resolved';
};

subtest 'Rejected race' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my (@results, @errors);
  Mojo::Promise->race($promise, $promise2, $promise3)->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise2->reject('second');
  $promise3->resolve('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],         'promises not resolved';
  is_deeply \@errors,  ['second'], 'promise rejected';
};

subtest 'Any' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my @results;
  Mojo::Promise->any($promise2, $promise, $promise3)->then(sub { @results = @_ });
  $promise2->reject('second');
  $promise3->resolve('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['third'], 'promise resolved';
};

subtest 'Any (all rejections)' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my (@results, @errors);
  Mojo::Promise->any($promise, $promise2, $promise3)->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise2->reject('second');
  $promise3->reject('third');
  $promise->reject('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],                                 'promises not resolved';
  is_deeply \@errors,  [['first'], ['second'], ['third']], 'promises rejected';
};

subtest 'Timeout' => sub {
  my (@errors, @results);
  my $promise  = Mojo::Promise->timeout(0.25 => 'Timeout1');
  my $promise2 = Mojo::Promise->new->timeout(0.025 => 'Timeout2');
  my $promise3
    = Mojo::Promise->race($promise, $promise2)->then(sub { @results = @_ })->catch(sub { @errors = @_ })->wait;
  is_deeply \@results, [],           'promises not resolved';
  is_deeply \@errors,  ['Timeout2'], 'promise rejected';
};

subtest 'Timeout with default message' => sub {
  my @errors;
  Mojo::Promise->timeout(0.025)->catch(sub { @errors = @_ })->wait;
  is_deeply \@errors, ['Promise timeout'], 'default timeout message';
};

subtest 'Timer without value' => sub {
  my @results;
  Mojo::Promise->timer(0.025)->then(sub { @results = (@_, 'works!') })->wait;
  is_deeply \@results, ['works!'], 'default timer result';
};

subtest 'Timer with values' => sub {
  my @results;
  Mojo::Promise->new->timer(0, 'first', 'second')->then(sub { @results = (@_, 'works too!') })->wait;
  is_deeply \@results, ['first', 'second', 'works too!'], 'timer result';
};

subtest 'All' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my @results;
  Mojo::Promise->all($promise, $promise2, $promise3)->then(sub { @results = @_ });
  $promise2->resolve('second');
  $promise3->resolve('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [['first'], ['second'], ['third']], 'promises resolved';
};

subtest 'Rejected all' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my (@results, @errors);
  Mojo::Promise->all($promise, $promise2, $promise3)->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise2->resolve('second');
  $promise3->reject('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@results, [],        'promises not resolved';
  is_deeply \@errors,  ['third'], 'promise rejected';
};

subtest 'All settled' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my @results;
  Mojo::Promise->all_settled($promise, $promise2, $promise3)->then(sub { @results = @_ });
  $promise2->resolve('second');
  $promise3->resolve('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  my $result = [
    {status => 'fulfilled', value => ['first']},
    {status => 'fulfilled', value => ['second']},
    {status => 'fulfilled', value => ['third']}
  ];
  is_deeply \@results, $result, 'promise resolved';
};

subtest 'All settled (with rejection)' => sub {
  my $promise  = Mojo::Promise->new->then(sub {@_});
  my $promise2 = Mojo::Promise->new->then(sub {@_});
  my $promise3 = Mojo::Promise->new->then(sub {@_});
  my (@results, @errors);
  Mojo::Promise->all_settled($promise, $promise2, $promise3)->then(sub { @results = @_ }, sub { @errors = @_ });
  $promise2->resolve('second');
  $promise3->reject('third');
  $promise->resolve('first');
  Mojo::IOLoop->one_tick;
  is_deeply \@errors, [], 'promise not rejected';
  my $result = [
    {status => 'fulfilled', value  => ['first']},
    {status => 'fulfilled', value  => ['second']},
    {status => 'rejected',  reason => ['third']}
  ];
  is_deeply \@results, $result, 'promise resolved';
};

subtest 'Settle with promise' => sub {
  my $promise = Mojo::Promise->new->resolve('works');
  my @results;
  my $promise2 = Mojo::Promise->new->resolve($promise)->then(sub { push @results, 'first', @_; @_ });
  $promise2->then(sub { push @results, 'second', @_ });
  Mojo::IOLoop->one_tick;
  is_deeply \@results, ['first', 'works', 'second', 'works'], 'promises resolved';

  $promise = Mojo::Promise->new->reject('works too');
  my @errors;
  @results  = ();
  $promise2 = Mojo::Promise->new->reject($promise)->catch(sub { push @errors, 'first', @_; () });
  $promise2->then(sub { push @results, 'second', @_ });
  Mojo::IOLoop->one_tick;
  is_deeply \@errors,  ['first', $promise], 'promises rejected';
  is_deeply \@results, ['second'],          'promises resolved';
  $promise->catch(sub { });
};

subtest 'Promisify' => sub {
  is ref Mojo::Promise->resolve('foo'), 'Mojo::Promise', 'right class';

  my $promise = Mojo::Promise->reject('foo');
  is ref $promise, 'Mojo::Promise', 'right class';
  my @errors;
  $promise->catch(sub { push @errors, @_ })->wait;
  is_deeply \@errors, ['foo'], 'promise rejected';

  $promise = Mojo::Promise->resolve('foo');
  is refaddr(Mojo::Promise->resolve($promise)), refaddr($promise), 'same object';

  $promise = Mojo::Promise->resolve('foo');
  isnt refaddr(Mojo::Promise->new->resolve($promise)), refaddr($promise), 'different object';

  $promise = Mojo::Promise->reject('foo');
  is refaddr(Mojo::Promise->resolve($promise)), refaddr($promise), 'same object';
  @errors = ();
  $promise->catch(sub { push @errors, @_ })->wait;
  is_deeply \@errors, ['foo'], 'promise rejected';
};

subtest 'Warnings' => sub {
  my @warn;
  local $SIG{__WARN__} = sub { push @warn, shift };
  Mojo::Promise->reject('one');
  like $warn[0], qr/Unhandled rejected promise: one/, 'unhandled';
  is $warn[1], undef, 'no more warnings';

  @warn = ();
  Mojo::Promise->reject('two')->then(sub { })->wait;
  like $warn[0], qr/Unhandled rejected promise: two/, 'unhandled';
  is $warn[1], undef, 'no more warnings';

  @warn = ();
  Mojo::Promise->reject('three')->finally(sub { })->wait;
  like $warn[0], qr/Unhandled rejected promise: three/, 'unhandled';
  is $warn[1], undef, 'no more warnings';

  @warn = ();
  my $promise = Mojo::Promise->new;
  $promise->reject('four');
  Mojo::IOLoop->one_tick;
  is $warn[0], undef, 'no warnings';
  undef $promise;
  like $warn[0], qr/Unhandled rejected promise: four/, 'unhandled';
  is $warn[1], undef, 'no more warnings';
};

subtest 'Warnings (multiple branches)' => sub {
  my @warn;
  local $SIG{__WARN__} = sub { push @warn, shift };
  my @errors;
  my $promise = Mojo::Promise->new;
  $promise->catch(sub { push @errors, @_ });
  $promise->reject('branches');
  $promise->wait;
  is_deeply \@errors, ['branches'], 'promise rejected';
  is $warn[0], undef, 'no warnings';

  @errors  = @warn = ();
  $promise = Mojo::Promise->new;
  $promise->catch(sub { push @errors, @_ });
  $promise->then(sub { });
  $promise->reject('branches2');
  $promise->wait;
  is_deeply \@errors, ['branches2'], 'promise rejected';
  like $warn[0], qr/Unhandled rejected promise: branches2/, 'unhandled';
  is $warn[1], undef, 'no more warnings';

  @warn    = ();
  $promise = Mojo::Promise->new;
  $promise->then(sub { })->then(sub { })->then(sub { });
  $promise->then(sub { });
  $promise->reject('branches3');
  $promise->wait;
  like $warn[0], qr/Unhandled rejected promise: branches3/, 'unhandled';
  like $warn[1], qr/Unhandled rejected promise: branches3/, 'unhandled';
  is $warn[2], undef, 'no more warnings';
};

subtest 'Map' => sub {
  my (@results, @errors, @started);
  my $promise = Mojo::Promise->map(sub { push @started, $_; Mojo::Promise->resolve($_) }, 1 .. 5)
    ->then(sub { @results = @_ }, sub { @errors = @_ });
  is_deeply \@started, [1, 2, 3, 4, 5], 'all started without concurrency';
  $promise->wait;
  is_deeply \@results, [[1], [2], [3], [4], [5]], 'correct result';
  is_deeply \@errors,  [],                        'promise not rejected';
};

subtest 'Map (with concurrency limit)' => sub {
  my $concurrent = 0;
  my (@results, @errors);
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
    1 .. 7
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [[1], [2], [3], [4], [5], [6], [7]], 'correct result';
  is_deeply \@errors,  [],                                  'promise not rejected';
};

subtest 'Map (with early reject)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub { Mojo::Promise->reject($n) });
    },
    1 .. 5
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [],        'promise not resolved';
  is_deeply \@errors,  [1],       'correct errors';
  is_deeply \@started, [1, 2, 3], 'only initial batch started';
};

subtest 'Map (with later reject)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub {
        if   ($n >= 5) { Mojo::Promise->reject($n) }
        else           { Mojo::Promise->resolve($n) }
      });
    },
    1 .. 8
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [], 'promise not resolved';
  is_deeply \@errors,  [5], 'correct errors';
  is_deeply \@started, [1, 2, 3, 4, 5, 6, 7], 'only maximum concurrent promises started';
};

subtest 'Map (any, with early success)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3, aggregation => 'any'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub { Mojo::Promise->resolve($n) });
    },
    1 .. 5
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [1], 'promise resolved';
  is_deeply \@errors,  [], 'correct errors';
  is_deeply \@started, [1, 2, 3], 'only initial batch started';
};

subtest 'Map (any, with later success)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3, aggregation => 'any'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub {
        if   ($n >= 5) { Mojo::Promise->resolve($n) }
        else           { Mojo::Promise->reject($n) }
      });
    },
    1 .. 7
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [5], 'promise resolved';
  is_deeply \@errors,  [], 'correct errors';
  is_deeply \@started, [1, 2, 3, 4, 5, 6, 7], 'only maximum concurrent promises started';
};

subtest 'Map (any, all rejected)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {aggregation => 'any'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub { Mojo::Promise->reject($n) });
    },
    1 .. 3
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [], 'promise rejected';
  is_deeply \@errors,  [[1], [2], [3]], 'correct errors';
  is_deeply \@started, [1, 2, 3], 'all started without concurrency';
};

subtest 'Map (concurrency, any, all rejected)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3, aggregation => 'any'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub { Mojo::Promise->reject($n) });
    },
    1 .. 5
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [], 'promise rejected';
  is_deeply \@errors,  [[1], [2], [3], [4], [5]], 'correct errors';
  is_deeply \@started, [1, 2, 3, 4, 5], 'all started with concurrency';
};

subtest 'Map (concurrency, race, 2 of 3 rejected)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3, aggregation => 'race'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub {
        if   ($n % 2) { Mojo::Promise->reject($n) }
        else          { Mojo::Promise->resolve($n) }
      });
    },
    1 .. 5
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  is_deeply \@results, [], 'promise rejected';
  is_deeply \@errors,  [1], 'correct errors';
  is_deeply \@started, [1, 2, 3], 'only 3 of 5 started with concurrency';
};

subtest 'Map (concurrency, all settled, partially rejected)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 3, aggregation => 'all_settled'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub {
        if   ($n % 2) { Mojo::Promise->resolve($n) }
        else          { Mojo::Promise->reject($n) }
      });
    },
    1 .. 5
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  my $result = [
    {status => 'fulfilled', value  => [1]},
    {status => 'rejected',  reason => [2]},
    {status => 'fulfilled', value  => [3]},
    {status => 'rejected',  reason => [4]},
    {status => 'fulfilled', value  => [5]}
  ];
  is_deeply \@results, $result, 'promise resolved';
  is_deeply \@errors,  [], 'correct errors';
  is_deeply \@started, [1, 2, 3, 4, 5], 'all started with concurrency';
};

subtest 'Map (concurrency, delay, all settled, partially rejected)' => sub {
  my (@results, @errors, @started);
  Mojo::Promise->map(
    {concurrency => 2, delay => 0.1, aggregation => 'all_settled'},
    sub {
      my $n = $_;
      push @started, $n;
      Mojo::Promise->resolve->then(sub {
        if   ($n % 2) { Mojo::Promise->reject($n) }
        else          { Mojo::Promise->resolve($n) }
      });
    },
    1 .. 5
  )->then(sub { @results = @_ }, sub { @errors = @_ })->wait;
  my $result = [
    {status => 'rejected',  reason => [1]},
    {status => 'fulfilled', value  => [2]},
    {status => 'rejected',  reason => [3]},
    {status => 'fulfilled', value  => [4]},
    {status => 'rejected',  reason => [5]},
  ];
  is_deeply \@results, $result, 'promise resolved';
  is_deeply \@errors, [], 'correct errors';

  # is_deeply \@started, [1, 2, 3, 4, 5], 'all started with concurrency';
  is scalar @started, 5, 'all started with concurrency';
};

subtest 'Map (custom event loop)' => sub {
  my $ok;
  my $loop    = Mojo::IOLoop->new;
  my $promise = Mojo::Promise->map(sub { Mojo::Promise->new->ioloop($loop)->resolve }, 1);
  is $promise->ioloop,   $loop,                   'same loop';
  isnt $promise->ioloop, Mojo::IOLoop->singleton, 'not the singleton';
  $promise->then(sub { $ok = 1; $loop->stop });
  $loop->start;
  ok $ok, 'loop completed';
};

subtest 'Wait for stopped loop' => sub {
  my @results;
  my $promise = Mojo::Promise->new;
  Mojo::IOLoop->next_tick(sub {
    Mojo::IOLoop->stop;
    Mojo::IOLoop->timer(0.1 => sub { $promise->resolve('wait') });
  });
  $promise->then(sub { @results = @_ })->wait;
  is_deeply \@results, ['wait'], 'promise resolved';
};

done_testing();
