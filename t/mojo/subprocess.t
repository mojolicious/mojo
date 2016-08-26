use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;

plan skip_all => 'set TEST_SUBPROCESS to enable this test (developer only!)'
  unless $ENV{TEST_SUBPROCESS};

use Mojo::IOLoop;
use Mojo::IOLoop::Subprocess;

# Huge result
my ($fail, $result);
my $sp = Mojo::IOLoop::Subprocess->new;
$sp->run(
  sub { shift->pid . $$ . ('x' x 100000) },
  sub {
    my ($sp, $err, $two) = @_;
    $fail   = $err;
    $result = $two;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is $result, 0 . $sp->pid . ('x' x 100000), 'right result';

# Multiple return values
($fail, $result) = ();
$sp = Mojo::IOLoop::Subprocess->new;
$sp->run(
  sub { return 1, [{two => 2}], 3 },
  sub {
    my ($sp, $err, @results) = @_;
    $fail   = $err;
    $result = \@results;
  }
);
Mojo::IOLoop->start;
ok !$fail, 'no error';
is_deeply $result, [1, [{two => 2}], 3], 'right structure';

# Event loop in subprocess
($fail, $result) = ();
$sp = Mojo::IOLoop::Subprocess->new;
$sp->run(
  sub {
    my $result;
    Mojo::IOLoop->next_tick(sub { $result = 23 });
    Mojo::IOLoop->start;
    return $result;
  },
  sub {
    my ($sp, $err, $twenty_three) = @_;
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

# Non-zero exit status
$fail = undef;
Mojo::IOLoop::Subprocess->new->run(
  sub { exit 3 },
  sub {
    my ($sp, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
is $fail, 'Non-zero exit status (3)', 'right error';

# Serialization error
$fail = undef;
$sp   = Mojo::IOLoop::Subprocess->new;
$sp->deserialize(sub { die 'Whatever' });
$sp->run(
  sub { 1 + 1 },
  sub {
    my ($sp, $err) = @_;
    $fail = $err;
  }
);
Mojo::IOLoop->start;
like $fail, qr/Whatever/, 'right error';

done_testing();
