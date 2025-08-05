use Mojo::Base -strict;

use Test::More;

plan skip_all => 'set TEST_EV to enable this test (developer only!)' unless $ENV{TEST_EV} || $ENV{TEST_ALL};
plan skip_all => 'EV 4.32+ required for this test!'                  unless eval { require EV; EV->VERSION('4.32'); 1 };

use IO::Socket::INET;
use Mojo::Util qw(steady_time);

subtest 'Instantiation' => sub {
  use_ok 'Mojo::Reactor::EV';

  my $reactor = Mojo::Reactor::EV->new;
  is ref $reactor,               'Mojo::Reactor::EV',   'right object';
  is ref Mojo::Reactor::EV->new, 'Mojo::Reactor::Poll', 'right object';

  undef $reactor;
  is ref Mojo::Reactor::EV->new, 'Mojo::Reactor::EV', 'right object';

  use_ok 'Mojo::IOLoop';
  $reactor = Mojo::IOLoop->singleton->reactor;
  is ref $reactor, 'Mojo::Reactor::EV', 'right object';
};

subtest 'Make sure it stops automatically when not watching for events' => sub {
  my $reactor = Mojo::IOLoop->singleton->reactor;

  my $triggered;
  Mojo::IOLoop->next_tick(sub { $triggered++ });
  Mojo::IOLoop->start;
  ok $triggered, 'reactor waited for one event';

  my $time = time;
  Mojo::IOLoop->start;
  Mojo::IOLoop->one_tick;
  ok time < ($time + 10), 'stopped automatically';
};

my $listen = IO::Socket::INET->new(Listen => 5, LocalAddr => '127.0.0.1');

subtest 'Listen' => sub {
  my $reactor = Mojo::IOLoop->singleton->reactor;
  my ($readable, $writable);
  $reactor->io($listen => sub { pop() ? $writable++ : $readable++ })->watch($listen, 0, 0)->watch($listen, 1, 1);
  $reactor->timer(0.025 => sub { shift->stop });
  $reactor->start;
  ok !$readable, 'handle is not readable';
  ok !$writable, 'handle is not writable';
};

subtest 'With client' => sub {
  my $port   = $listen->sockport;
  my $client = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port);

  subtest 'Connect' => sub {
    my ($readable, $writable);
    my $reactor = Mojo::IOLoop->singleton->reactor;
    $reactor->io($listen => sub { pop() ? $writable++ : $readable++ })->watch($listen, 0, 0)->watch($listen, 1, 1);
    $reactor->timer(1 => sub { shift->stop });
    $reactor->start;
    ok $readable,  'handle is readable';
    ok !$writable, 'handle is not writable';
  };

  subtest 'With server' => sub {
    my $reactor = Mojo::IOLoop->singleton->reactor;
    ok $reactor->remove($listen),  'removed';
    ok !$reactor->remove($listen), 'not removed again';
    my $server = $listen->accept;

    subtest 'Accept' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my ($readable, $writable);
      $reactor->io($client => sub { pop() ? $writable++ : $readable++ });
      $reactor->again($reactor->timer(0.025 => sub { shift->stop }));
      $reactor->start;
      ok !$readable, 'handle is not readable';
      ok $writable,  'handle is writable';

      print $client "hello!\n";
      sleep 1;
      ok $reactor->remove($client), 'removed';

      ($readable, $writable) = ();
      $reactor->io($server => sub { pop() ? $writable++ : $readable++ });
      $reactor->watch($server, 1, 0);
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable,  'handle is readable';
      ok !$writable, 'handle is not writable';

      ($readable, $writable) = ();
      $reactor->watch($server, 1, 1);
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable, 'handle is readable';
      ok $writable, 'handle is writable';

      ($readable, $writable) = ();
      $reactor->watch($server, 0, 0);
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok !$readable, 'handle is not readable';
      ok !$writable, 'handle is not writable';

      ($readable, $writable) = ();
      $reactor->watch($server, 1, 0);
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable,  'handle is readable';
      ok !$writable, 'handle is not writable';

      ($readable, $writable) = ();
      $reactor->io($server => sub { pop() ? $writable++ : $readable++ });
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable, 'handle is readable';
      ok $writable, 'handle is writable';
    };

    subtest 'Timers' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my ($timer, $recurring);
      $reactor->timer(0 => sub { $timer++ });
      ok $reactor->remove($reactor->timer(0 => sub { $timer++ })), 'removed';

      my $id = $reactor->recurring(0 => sub { $recurring++ });
      my ($readable, $writable);
      $reactor->io($server => sub { pop() ? $writable++ : $readable++ });
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable,  'handle is readable again';
      ok $writable,  'handle is writable again';
      ok $timer,     'timer was triggered';
      ok $recurring, 'recurring was triggered';

      my $done;
      ($readable, $writable, $timer, $recurring) = ();
      $reactor->timer(0.025 => sub { $done = shift->is_running });
      $reactor->one_tick while !$done;
      ok $readable,  'handle is readable again';
      ok $writable,  'handle is writable again';
      ok !$timer,    'timer was not triggered';
      ok $recurring, 'recurring was triggered again';

      ($readable, $writable, $timer, $recurring) = ();
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable,              'handle is readable again';
      ok $writable,              'handle is writable again';
      ok !$timer,                'timer was not triggered';
      ok $recurring,             'recurring was triggered again';
      ok $reactor->remove($id),  'removed';
      ok !$reactor->remove($id), 'not removed again';

      ($readable, $writable, $timer, $recurring) = ();
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable,   'handle is readable again';
      ok $writable,   'handle is writable again';
      ok !$timer,     'timer was not triggered';
      ok !$recurring, 'recurring was not triggered again';

      ($readable, $writable, $timer, $recurring) = ();
      my $next_tick;
      is $reactor->next_tick(sub { $next_tick++ }), undef, 'returned undef';

      $id = $reactor->recurring(0 => sub { $recurring++ });
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $readable,  'handle is readable again';
      ok $writable,  'handle is writable again';
      ok !$timer,    'timer was not triggered';
      ok $recurring, 'recurring was triggered again';
      ok $next_tick, 'next tick was triggered';
    };

    subtest 'Reset' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      $reactor->next_tick(sub { die 'Reset failed' });
      $reactor->reset;
      my ($readable, $writable, $recurring);
      $reactor->next_tick(sub { shift->stop });
      $reactor->start;
      ok !$readable,  'io event was not triggered again';
      ok !$writable,  'io event was not triggered again';
      ok !$recurring, 'recurring was not triggered again';

      my $reactor2 = Mojo::Reactor::EV->new;
      is ref $reactor2, 'Mojo::Reactor::Poll', 'right object';
    };

    subtest 'Ordered next_tick' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my $result  = [];
      for my $i (1 .. 10) {
        $reactor->next_tick(sub { push @$result, $i });
      }
      $reactor->start;
      is_deeply $result, [1 .. 10], 'right result';
    };

    subtest 'Reset while watchers are active' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my ($writable);
      $reactor->io($_ => sub { ++$writable and shift->reset })->watch($_, 0, 1) for $client, $server;
      $reactor->start;
      is $writable, 1, 'only one handle was writable';
    };

    subtest 'Concurrent reactors' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my $timer   = 0;
      $reactor->recurring(0 => sub { $timer++ });
      my $timer2;
      my $reactor2 = Mojo::Reactor::EV->new;
      $reactor2->recurring(0 => sub { $timer2++ });
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $timer,   'timer was triggered';
      ok !$timer2, 'timer was not triggered';

      $timer = $timer2 = 0;
      $reactor2->timer(0.025 => sub { shift->stop });
      $reactor2->start;
      ok !$timer, 'timer was not triggered';
      ok $timer2, 'timer was triggered';

      $timer = $timer2 = 0;
      $reactor->timer(0.025 => sub { shift->stop });
      $reactor->start;
      ok $timer,   'timer was triggered';
      ok !$timer2, 'timer was not triggered';

      $timer = $timer2 = 0;
      $reactor2->timer(0.025 => sub { shift->stop });
      $reactor2->start;
      ok !$timer, 'timer was not triggered';
      ok $timer2, 'timer was triggered';

      $reactor->reset;
    };

    subtest 'Restart timer' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my ($single, $pair, $one, $two, $last);
      $reactor->timer(0.025 => sub { $single++ });
      $one = $reactor->timer(
        0.025 => sub {
          my $reactor = shift;
          $last++ if $single && $pair;
          $pair++ ? $reactor->stop : $reactor->again($two);
        }
      );
      $two = $reactor->timer(
        0.025 => sub {
          my $reactor = shift;
          $last++ if $single && $pair;
          $pair++ ? $reactor->stop : $reactor->again($one);
        }
      );
      $reactor->start;
      is $pair, 2, 'timer pair was triggered';
      ok $single, 'single timer was triggered';
      ok $last,   'timers were triggered in the right order';
    };

    subtest 'Reset timer' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my $before  = steady_time;
      my ($after, $again);
      my ($one,   $two);
      $one = $reactor->timer(300 => sub { $after = steady_time });
      $two = $reactor->recurring(
        300 => sub {
          my $reactor = shift;
          $reactor->remove($two) if ++$again > 3;
        }
      );
      $reactor->timer(
        0.025 => sub {
          my $reactor = shift;
          $reactor->again($one, 0.025);
          $reactor->again($two, 0.025);
        }
      );
      $reactor->start;
      ok $after, 'timer was triggered';
      ok(($after - $before) < 200, 'less than 200 seconds');
      is $again, 4, 'recurring timer triggered four times';
    };

    subtest 'Restart inactive timer' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my $id      = $reactor->timer(0 => sub { });
      ok $reactor->remove($id), 'removed';

      eval { $reactor->again($id) };
      like $@, qr/Timer not active/, 'right error';
    };

    subtest 'Change inactive I/O watcher' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      ok !$reactor->remove($listen), 'not removed again';

      eval { $reactor->watch($listen, 1, 1) };
      like $@, qr!I/O watcher not active!, 'right error';
    };

    subtest 'Error' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my $err;
      $reactor->unsubscribe('error')->on(
        error => sub {
          shift->stop;
          $err = pop;
        }
      );
      $reactor->timer(0 => sub { die "works!\n" });
      $reactor->start;
      like $err, qr/works!/, 'right error';
    };

    subtest 'Reset events' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      $reactor->on(error => sub { });
      ok $reactor->has_subscribers('error'), 'has subscribers';

      $reactor->reset;
      ok !$reactor->has_subscribers('error'), 'no subscribers';
    };

    subtest 'Recursion' => sub {
      my $reactor = Mojo::IOLoop->singleton->reactor;
      my $timer;
      $reactor = $reactor->new;
      $reactor->timer(0 => sub { ++$timer and shift->one_tick });
      $reactor->one_tick;
      is $timer, 1, 'timer was triggered once';
    };

    subtest 'Detection' => sub {
      is(Mojo::Reactor->detect, 'Mojo::Reactor::EV', 'right class');
    };

    subtest 'Reactor in control' => sub {
      is ref Mojo::IOLoop->singleton->reactor, 'Mojo::Reactor::EV', 'right object';
      ok !Mojo::IOLoop->is_running, 'loop is not running';

      my ($buffer, $server_err, $server_running, $client_err, $client_running);
      my $id = Mojo::IOLoop->server(
        {address => '127.0.0.1'} => sub {
          my ($loop, $stream) = @_;
          $stream->write('test' => sub { shift->write('321') });
          $server_running = Mojo::IOLoop->is_running;
          eval { Mojo::IOLoop->start };
          $server_err = $@;
        }
      );
      $port = Mojo::IOLoop->acceptor($id)->port;
      Mojo::IOLoop->client(
        {port => $port} => sub {
          my ($loop, $err, $stream) = @_;
          $stream->on(
            read => sub {
              my ($stream, $chunk) = @_;
              $buffer .= $chunk;
              return unless $buffer eq 'test321';
              Mojo::IOLoop->singleton->reactor->stop;
            }
          );
          $client_running = Mojo::IOLoop->is_running;
          eval { Mojo::IOLoop->start };
          $client_err = $@;
        }
      );

      Mojo::IOLoop->singleton->reactor->start;
      ok !Mojo::IOLoop->is_running, 'loop is not running';
      like $server_err, qr/^Mojo::IOLoop already running/, 'right error';
      like $client_err, qr/^Mojo::IOLoop already running/, 'right error';
      ok $server_running, 'loop is running';
      ok $client_running, 'loop is running';
    };
  };
};

done_testing();
