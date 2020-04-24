use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_SUBPROCESS to enable this test (developer only!)'
  unless $ENV{TEST_SUBPROCESS} || $ENV{TEST_ALL};
plan skip_all => 'set TEST_EV to enable this test (developer only!)'
  unless $ENV{TEST_EV} || $ENV{TEST_ALL};
plan skip_all => 'EV 4.32+ required for this test!'
  unless eval { require EV; EV->VERSION('4.32'); 1 };

use Mojo::IOLoop;
use Mojo::Promise;

# Event loop in subprocess (already running event loop)
my ($fail, $result);
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

done_testing;
