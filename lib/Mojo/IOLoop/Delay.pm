package Mojo::IOLoop::Delay;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;
use Mojo::Util;
use Scalar::Util qw(blessed weaken);

has ioloop    => sub { Mojo::IOLoop->singleton };
has remaining => sub { [] };

sub all {
  my @promises = @_;

  my $all = $promises[0]->_clone;

  my $results   = [];
  my $remaining = scalar @promises;
  for my $i (0 .. $#promises) {
    $promises[$i]->then(
      sub {
        $results->[$i] = [@_];
        $all->resolve(@$results) if --$remaining <= 0;
      },
      sub { $all->reject(@_) },
    );
  }

  return $all;
}

sub begin {
  my ($self, $offset, $len) = @_;
  $self->{pending}++;
  my $id = $self->{counter}++;
  return sub { $self->_step($id, $offset // 1, $len, @_) };
}

sub catch { shift->then(undef, shift) }

sub data { Mojo::Util::_stash(data => @_) }

sub finally {
  my ($self, $finally) = @_;

  my $new = $self->_clone;
  my $cb  = sub {
    my ($method, @result) = @_;
    my ($promise) = eval { $finally->(@result) };
    if ($promise && blessed $promise && $promise->can('then')) {
      return $promise->then(sub { $new->$method(@result) },
        sub { $new->$method(@result) });
    }
    $new->$method(@result);
    ();
  };

  push @{$self->{resolve}}, sub { $cb->('resolve', @_) };
  push @{$self->{reject}},  sub { $cb->('reject',  @_) };

  $self->_defer if $self->{result};

  return $new;
}

sub pass { $_[0]->begin->(@_) }

sub race {
  my @promises = @_;
  my $race     = $promises[0]->_clone;
  $_->then(sub { $race->resolve(@_) }, sub { $race->reject(@_) }) for @promises;
  return $race;
}

sub reject  { shift->_settle('reject',  @_) }
sub resolve { shift->_settle('resolve', @_) }

sub steps {
  my $self = shift->remaining([@_]);
  $self->ioloop->next_tick($self->begin);
  return $self;
}

sub then {
  my ($self, $resolve, $reject) = @_;

  my $new = $self->_clone;
  push @{$self->{resolve}}, $self->_wrap('resolve', $new, $resolve);
  push @{$self->{reject}},  $self->_wrap('reject',  $new, $reject);

  $self->_defer if $self->{result};

  return $new;
}

sub wait {
  my $self = shift;
  return if $self->ioloop->is_running;
  my $loop = $self->ioloop;
  $self->finally(sub { $loop->stop });
  $loop->start;
}

sub _clone {
  my $self  = shift;
  my $clone = $self->new;
  weaken $clone->ioloop($self->ioloop)->{ioloop};
  return $clone;
}

sub _defer {
  my $self = shift;

  my $cbs = $self->{status} eq 'resolve' ? $self->{resolve} : $self->{reject};
  @$self{qw(resolve reject)} = ([], []);
  my $results = $self->{result};

  $self->ioloop->next_tick(sub { $_->(@$results) for @$cbs });
}

sub _die { $_[0]->has_subscribers('error') ? $_[0]->ioloop->stop : die $_[1] }

sub _settle {
  my ($self, $status) = (shift, shift);
  @{$self}{qw(result status)} = ([@_], $status);
  $self->_defer;
  return $self;
}

sub _step {
  my ($self, $id, $offset, $len) = (shift, shift, shift, shift);

  $self->{args}[$id]
    = [@_ ? defined $len ? splice @_, $offset, $len : splice @_, $offset : ()];
  return $self if $self->{fail} || --$self->{pending} || $self->{lock};
  local $self->{lock} = 1;
  my @args = map {@$_} @{delete $self->{args}};

  $self->{counter} = 0;
  if (my $cb = shift @{$self->remaining}) {
    unless (eval { $self->$cb(@args); 1 }) {
      my $err = $@;
      $self->{fail}++;
      return $self->remaining([])->reject($err)->emit(error => $err);
    }
  }

  return $self->remaining([])->resolve(@args)->emit(finish => @args)
    unless $self->{counter};
  $self->ioloop->next_tick($self->begin) unless $self->{pending};
  return $self;
}

sub _wrap {
  my ($self, $method, $new, $cb) = @_;

  return sub { $new->$method(@{$self->{result}}) }
    unless defined $cb;

  return sub {
    my @result;
    unless (eval { @result = $cb->(@_); 1 }) {
      $new->reject($@);
    }

    elsif (@result == 1 and blessed $result[0] and $result[0]->can('then')) {
      $result[0]
        ->then(sub { $new->resolve(@_); () }, sub { $new->reject(@_); () });
    }

    else { $new->resolve(@result) }
  };
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Delay - Promises/A+ and flow-control helpers

=head1 SYNOPSIS

  use Mojo::IOLoop::Delay;

  # Synchronize multiple non-blocking operations
  my $delay = Mojo::IOLoop::Delay->new;
  $delay->steps(sub { say 'BOOM!' });
  for my $i (1 .. 10) {
    my $end = $delay->begin;
    Mojo::IOLoop->timer($i => sub {
      say 10 - $i;
      $end->();
    });
  }
  $delay->wait;

  # Sequentialize multiple non-blocking operations
  Mojo::IOLoop::Delay->new->steps(

    # First step (simple timer)
    sub {
      my $delay = shift;
      Mojo::IOLoop->timer(2 => $delay->begin);
      say 'Second step in 2 seconds.';
    },

    # Second step (concurrent timers)
    sub {
      my ($delay, @args) = @_;
      Mojo::IOLoop->timer(1 => $delay->begin);
      Mojo::IOLoop->timer(3 => $delay->begin);
      say 'Third step in 3 seconds.';
    },

    # Third step (the end)
    sub {
      my ($delay, @args) = @_;
      say 'And done after 5 seconds total.';
    }
  )->wait;

  # Handle exceptions in all steps
  Mojo::IOLoop::Delay->new->steps(
    sub {
      my $delay = shift;
      die 'Intentional error';
    },
    sub {
      my ($delay, @args) = @_;
      say 'Never actually reached.';
    }
  )->catch(sub {
    my $err = shift;
    say "Something went wrong: $err";
  })->wait;

=head1 DESCRIPTION

L<Mojo::IOLoop::Delay> is a Perl-ish implementation of
L<Promises/A+|https://promisesaplus.com> and provides flow-control helpers for
L<Mojo::IOLoop>, which can help you avoid deep nested closures that often result
from continuation-passing style.

  use Mojo::IOLoop;

  # These deep nested closures are often referred to as "Callback Hell"
  Mojo::IOLoop->timer(3 => sub {
    my loop = shift;

    say '3 seconds';
    Mojo::IOLoop->timer(3 => sub {
      my $loop = shift;

      say '6 seconds';
      Mojo::IOLoop->timer(3 => sub {
        my $loop = shift;

        say '9 seconds';
        Mojo::IOLoop->stop;
      });
    });
  });

  Mojo::IOLoop->start;

The idea behind L<Mojo::IOLoop::Delay> is to turn the nested closures above into
a flat series of closures. In the example below, the call to L</"begin"> creates
a code reference that we can pass to L<Mojo::IOLoop/"timer"> as a callback, and
that leads to the next closure in the series when executed.

  use Mojo::IOLoop;

  # Instead of nested closures we now have a simple chain
  my $delay = Mojo::IOloop->delay(
    sub {
      my $delay = shift;
      Mojo::IOLoop->timer(3 => $delay->begin);
    },
    sub {
      my $delay = shift;
      say '3 seconds';
      Mojo::IOLoop->timer(3 => $delay->begin);
    },
    sub {
      my $delay = shift;
      say '6 seconds';
      Mojo::IOLoop->timer(3 => $delay->begin);
    },
    sub {
      my $delay = shift;
      say '9 seconds';
    }
  );
  $delay->wait;

Another positive side effect of this pattern is that we do not need to call
L<Mojo::IOLoop/"start"> and L<Mojo::IOLoop/"stop"> manually, because we know
exactly when our series of closures has reached the end. So L</"wait"> can stop
the event loop automatically if it had to be started at all in the first place.

=head1 EVENTS

L<Mojo::IOLoop::Delay> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 error

  $delay->on(error => sub {
    my ($delay, $err) = @_;
    ...
  });

Emitted if an exception gets thrown in one of the steps, breaking the chain,
fatal if unhandled.

=head2 finish

  $delay->on(finish => sub {
    my ($delay, @args) = @_;
    ...
  });

Emitted once the event counter reaches zero and there are no more steps.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Delay> implements the following attributes.

=head2 ioloop

  my $loop = $delay->ioloop;
  $delay   = $delay->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop> singleton.

=head2 remaining

  my $remaining = $delay->remaining;
  $delay        = $delay->remaining([sub {...}]);

Remaining L</"steps"> in chain.

=head1 METHODS

L<Mojo::IOLoop::Delay> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 all

  my $new = $delay->all(@delays);

=head2 begin

  my $cb = $delay->begin;
  my $cb = $delay->begin($offset);
  my $cb = $delay->begin($offset, $len);

Indicate an active event by incrementing the event counter, the returned
code reference can be used as a callback, and needs to be executed when the
event has completed to decrement the event counter again. When all code
references generated by this method have been executed and the event counter has
reached zero, L</"steps"> will continue.

  # Capture all arguments except for the first one (invocant)
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, $err, $stream) = @_;
    ...
  });
  Mojo::IOLoop->client({port => 3000} => $delay->begin);
  $delay->wait;

Arguments passed to the returned code reference are spliced with the given
offset and length, defaulting to an offset of C<1> with no default length. The
arguments are then combined in the same order L</"begin"> was called, and passed
together to the next step or L</"finish"> event.

  # Capture all arguments
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, $loop, $err, $stream) = @_;
    ...
  });
  Mojo::IOLoop->client({port => 3000} => $delay->begin(0));
  $delay->wait;

  # Capture only the second argument
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, $err) = @_;
    ...
  });
  Mojo::IOLoop->client({port => 3000} => $delay->begin(1, 1));
  $delay->wait;

  # Capture and combine arguments
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, $three_err, $three_stream, $four_err, $four_stream) = @_;
    ...
  });
  Mojo::IOLoop->client({port => 3000} => $delay->begin);
  Mojo::IOLoop->client({port => 4000} => $delay->begin);
  $delay->wait;

=head2 catch

  my $new = $delay->catch(sub {...});

=head2 data

  my $hash = $delay->data;
  my $foo  = $delay->data('foo');
  $delay   = $delay->data({foo => 'bar', baz => 23});
  $delay   = $delay->data(foo => 'bar', baz => 23);

Data shared between all L</"steps">.

  # Remove value
  my $foo = delete $delay->data->{foo};

  # Assign multiple values at once
  $delay->data(foo => 'test', bar => 23);

=head2 finally

  my $new = $delay->finally(sub {...});

=head2 pass

  $delay = $delay->pass;
  $delay = $delay->pass(@args);

Increment event counter and decrement it again right away to pass values to the
next step.

  # Longer version
  $delay->begin(0)->(@args);

=head2 race

  my $new = $delay->race(@delays);

=head2 reject

  $delay = $delay->reject(@args);

=head2 resolve

  $delay = $delay->resolve(@args);

=head2 steps

  $delay = $delay->steps(sub {...}, sub {...});

Sequentialize multiple events, every time the event counter reaches zero a
callback will run, the first one automatically runs during the next reactor tick
unless it is delayed by incrementing the event counter. This chain will continue
until there are no L</"remaining"> callbacks, a callback does not increment the
event counter or an exception gets thrown in a callback.

=head2 then

  my $new = $delay->then(sub {...}, sub {...});

=head2 wait

  $delay->wait;

Start L</"ioloop"> and stop it again once an L</"error"> or L</"finish"> event
gets emitted, does nothing when L</"ioloop"> is already running.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
