use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_SUBPROCESS to enable this test (developer only!)'
  unless $ENV{TEST_SUBPROCESS} || $ENV{TEST_ALL};

use Mojo::IOLoop;
use Mojo::IOLoop::Subprocess;
use Mojo::Promise;
use Mojo::File qw(tempfile);

# Huge result
my ($fail, $result, @start);
my $subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->on(spawn => sub { push @start, shift->pid });
$subprocess->run(
  sub { shift->pid . $$ . ('x' x 100000) },
  sub {
    my ($subprocess, $err, $two) = @_;
    $fail = $err;
    $result .= $two;
  }
);
$result = $$;
ok !$subprocess->pid, 'no process id available yet';
is $subprocess->exit_code, undef, 'no exit code';
Mojo::IOLoop->start;
ok $subprocess->pid, 'process id available';
is $subprocess->exit_code, 0, 'zero exit code';
ok !$fail, 'no error';
is $result, $$ . 0 . $subprocess->pid . ('x' x 100000), 'right result';
is_deeply \@start, [$subprocess->pid], 'spawn event has been emitted once';

# Custom event loop
($fail, $result) = ();
my $loop = Mojo::IOLoop->new;
$loop->subprocess(
  sub {'♥'},
  sub {
    my ($subprocess, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
$loop->start;
ok !$fail, 'no error';
is_deeply $result, ['♥'], 'right structure';

# Multiple return values
($fail, $result) = ();
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->run(
  sub { return '♥', [{two => 2}], 3 },
  sub {
    my ($subprocess, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is_deeply $result, ['♥', [{two => 2}], 3], 'right structure';

# Promises
$result     = [];
$subprocess = Mojo::IOLoop::Subprocess->new;
is $subprocess->exit_code, undef, 'no exit code';
$subprocess->run_p(sub { return '♥', [{two => 2}], 3 })->then(sub { $result = [@_] })->wait;
is_deeply $result, ['♥', [{two => 2}], 3], 'right structure';
$fail       = undef;
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->run_p(sub { die 'Whatever' })->catch(sub { $fail = shift })->wait;
is $subprocess->exit_code, 0, 'zero exit code';
like $fail, qr/Whatever/, 'right error';
$result = [];
Mojo::IOLoop->subprocess->run_p(sub { return '♥' })->then(sub { $result = [@_] })->wait;
is_deeply $result, ['♥'], 'right structure';

# Event loop in subprocess
($fail, $result) = ();
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->run(
  sub {
    my $result;
    Mojo::IOLoop->next_tick(sub { $result = 23 });
    Mojo::IOLoop->start;
    return $result;
  },
  sub {
    my ($subprocess, $err, $twenty_three) = @_;
    $fail   = $err;
    $result = $twenty_three;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is $result, 23, 'right result';

# Event loop in subprocess (already running event loop)
($fail, $result) = ();
Mojo::IOLoop->next_tick(sub {
  Mojo::IOLoop->subprocess(
    sub {
      my $result;
      my $promise = Mojo::Promise->new;
      $promise->then(sub { $result = shift });
      Mojo::IOLoop->next_tick(sub { $promise->resolve(25) });
      $promise->wait;
      return $result;
    },
    sub {
      my ($subprocess, $err, $twenty_five) = @_;
      $fail   = $err;
      $result = $twenty_five;
    }
  );
});
Mojo::IOLoop->start;
ok !$fail, 'no error';
is $result, 25, 'right result';

# Concurrent subprocesses
($fail, $result) = ();
my $promise  = Mojo::IOLoop->subprocess->run_p(sub {1});
my $promise2 = Mojo::IOLoop->subprocess->run_p(sub {2});
Mojo::Promise->all($promise, $promise2)->then(sub {
  $result = [map { $_->[0] } @_];
})->catch(sub { $fail = shift })->wait;
ok !$fail, 'no error';
is_deeply $result, [1, 2], 'right structure';

# No result
($fail, $result) = ();
Mojo::IOLoop::Subprocess->new->run(
  sub {return},
  sub {
    my ($subprocess, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is_deeply $result, [], 'right structure';

# Stream inherited from previous subprocesses
($fail, $result) = ();
my @promises;
my $me = $$;
for (0 .. 1) {
  push @promises, my $promise = Mojo::Promise->new;
  my $subprocess = Mojo::IOLoop::Subprocess->new;
  $subprocess->run(
    sub { 1 + 1 },
    sub {
      my ($subprocess, $err, $two) = @_;
      $fail ||= $err;
      push @$result, $two;
      is $me, $$, 'we are the parent';
      $promise->resolve;
    }
  );
}
Mojo::Promise->all(@promises)->wait;
ok !$fail, 'no error';
is_deeply $result, [2, 2], 'right structure';

# Exception
$fail = undef;
Mojo::IOLoop::Subprocess->new->run(
  sub { die 'Whatever' },
  sub {
    my ($subprocess, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
like $fail, qr/Whatever/, 'right error';

# Non-zero exit status
$fail       = undef;
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->run(
  sub { exit 3 },
  sub {
    my ($subprocess, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
is $subprocess->exit_code, 3, 'right exit code';
like $fail, qr/offset 0/, 'right error';

# Serialization error
$fail       = undef;
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->deserialize(sub { die 'Whatever' });
$subprocess->run(
  sub { 1 + 1 },
  sub {
    my ($subprocess, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
like $fail, qr/Whatever/, 'right error';

# Progress
($fail, $result) = (undef, undef);
my @progress;
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->run(
  sub {
    my $s = shift;
    $s->progress(20);
    $s->progress({percentage => 45});
    $s->progress({percentage => 90}, {long_data => [1 .. 1e5]});
    'yay';
  },
  sub {
    my ($subprocess, $err, @res) = @_;
    $fail   = $err;
    $result = \@res;
  }
);
$subprocess->on(
  progress => sub {
    my ($subprocess, @args) = @_;
    push @progress, \@args;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is_deeply $result, ['yay'], 'correct result';
is_deeply \@progress, [[20], [{percentage => 45}], [{percentage => 90}, {long_data => [1 .. 1e5]}]], 'correct progress';

# Cleanup
($fail, $result) = ();
my $file   = tempfile;
my $called = 0;
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->on(cleanup => sub { $file->spurt(shift->serialize->({test => ++$called})) });
$subprocess->run(
  sub {'Hello Mojo!'},
  sub {
    my ($subprocess, $err, $hello) = @_;
    $fail   = $err;
    $result = $hello;
  }
);
Mojo::IOLoop->start;
is_deeply $subprocess->deserialize->($file->slurp), {test => 1}, 'cleanup event emitted once';
ok !$fail, 'no error';
is $result, 'Hello Mojo!', 'right result';

done_testing();
