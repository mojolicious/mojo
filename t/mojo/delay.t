use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::IOLoop;
use Mojo::IOLoop::Delay;

# Promise (all)
my $delay  = Mojo::IOLoop::Delay->new->then(sub {@_});
my $delay2 = Mojo::IOLoop::Delay->new->then(sub {@_});
my $delay3 = Mojo::IOLoop::Delay->new->then(sub {@_});
my @results;
$delay->all($delay2, $delay3)->then(sub { @results = @_ });
$delay2->resolve('second');
$delay3->resolve('third');
$delay->resolve('first');
Mojo::IOLoop->one_tick;
is_deeply \@results, [['first'], ['second'], ['third']], 'promises resolved';

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
