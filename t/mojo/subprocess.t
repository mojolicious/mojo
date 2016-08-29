use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_SUBPROCESS to enable this test (developer only!)'
  unless $ENV{TEST_SUBPROCESS};

use Mojo::IOLoop;
use Mojo::IOLoop::Subprocess;

# Huge result
my ($fail, $result);
my $subprocess = Mojo::IOLoop::Subprocess->new;
$subprocess->run(
  sub { shift->pid . $$ . ('x' x 100000) },
  sub {
    my ($subprocess, $err, $two) = @_;
    $fail = $err;
    $result .= $two;
  }
);
$result = $$;
Mojo::IOLoop->start;
ok !$fail, 'no error';
is $result, $$ . 0 . $subprocess->pid . ('x' x 100000), 'right result';

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
    Mojo::IOLoop->subprocess(sub {1}, $delay->begin);
    Mojo::IOLoop->subprocess(sub {2}, $delay->begin);
  },
  sub {
    my ($delay, $err1, $result1, $err2, $result2) = @_;
    $fail = $err1 || $err2;
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

done_testing();
