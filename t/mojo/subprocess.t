use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_SUBPROCESS to enable this test (developer only!)'
  unless $ENV{TEST_SUBPROCESS} || $ENV{TEST_ALL};

use Mojo::IOLoop;
use Mojo::IOLoop::Subprocess;
use Mojo::File 'tempfile';

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
Mojo::IOLoop->start;
ok $subprocess->pid, 'process id available';
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

# Concurrent subprocesses
($fail, $result) = ();
Mojo::IOLoop->delay(
  sub {
    my $delay = shift;
    Mojo::IOLoop->subprocess(sub      {1}, $delay->begin);
    Mojo::IOLoop->subprocess->run(sub {2}, $delay->begin);
  },
  sub {
    my ($delay, $err1, $result1, $err2, $result2) = @_;
    $fail   = $err1 || $err2;
    $result = [$result1, $result2];
  }
)->wait;
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
my $delay = Mojo::IOLoop->delay;
my $me    = $$;
for (0 .. 1) {
  my $end        = $delay->begin;
  my $subprocess = Mojo::IOLoop::Subprocess->new;
  $subprocess->run(
    sub { 1 + 1 },
    sub {
      my ($subprocess, $err, $two) = @_;
      $fail ||= $err;
      push @$result, $two;
      is $me, $$, 'we are the parent';
      $end->();
    }
  );
}
$delay->wait;
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
$fail = undef;
Mojo::IOLoop::Subprocess->new->run(
  sub { exit 3 },
  sub {
    my ($subprocess, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
like $fail, qr/Storable/, 'right error';

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
is_deeply \@progress,
  [[20], [{percentage => 45}], [{percentage => 90}, {long_data => [1 .. 1e5]}]],
  'correct progress';

# Cleanup
($fail, $result) = ();
my $file   = tempfile;
my $called = 0;
$subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->on(
  cleanup => sub { $file->spurt(shift->serialize->({test => ++$called})) });
$subprocess->run(
  sub {'Hello Mojo!'},
  sub {
    my ($subprocess, $err, $hello) = @_;
    $fail   = $err;
    $result = $hello;
  }
);
Mojo::IOLoop->start;
is_deeply $subprocess->deserialize->($file->slurp), {test => 1},
  'cleanup event emitted once';
ok !$fail, 'no error';
is $result, 'Hello Mojo!', 'right result';

done_testing();
