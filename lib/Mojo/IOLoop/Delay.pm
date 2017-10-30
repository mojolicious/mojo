package Mojo::IOLoop::Delay;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;
use Mojo::Util 'deprecated';
use Scalar::Util qw(blessed weaken);

has ioloop => sub { Mojo::IOLoop->singleton };

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

# DEPRECATED!
sub data {
  deprecated 'Mojo::IOLoop::Delay::data is DEPRECATED';
  Mojo::Util::_stash(data => @_);
}

sub finally {
  my ($self, $finally) = @_;

  my $new = $self->_clone;
  push @{$self->{resolve}}, sub { _finally($new, $finally, 'resolve', @_) };
  push @{$self->{reject}},  sub { _finally($new, $finally, 'reject',  @_) };

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

sub reject { shift->_settle('reject', @_) }

# DEPRECATED!
sub remaining {
  deprecated 'Mojo::IOLoop::Delay::remaining is DEPRECATED';
  my $self = shift;
  return $self->{steps} ||= [] unless @_;
  $self->{steps} = shift;
  return $self;
}

sub resolve { shift->_settle('resolve', @_) }

sub steps {
  my ($self, @steps) = @_;
  $self->{steps} = \@steps;
  $self->ioloop->next_tick($self->begin);

  # DEPRECATED!
  $self->on(error => sub { });

  return $self;
}

sub then {
  my ($self, $resolve, $reject) = @_;

  my $new = $self->_clone;
  push @{$self->{resolve}}, sub { _then($new, $resolve, 'resolve', @_) };
  push @{$self->{reject}},  sub { _then($new, $reject,  'reject',  @_) };

  $self->_defer if $self->{result};

  return $new;
}

sub wait {
  my $self = shift;
  return if (my $loop = $self->ioloop)->is_running;
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

  return unless my $result = $self->{result};
  my $cbs = $self->{status} eq 'resolve' ? $self->{resolve} : $self->{reject};
  @{$self}{qw(resolve reject)} = ([], []);

  $self->ioloop->next_tick(sub { $_->(@$result) for @$cbs });
}

sub _finally {
  my ($new, $finally, $method, @result) = @_;
  my ($res) = eval { $finally->(@result) };
  return $new->$method(@result)
    unless $res && blessed $res && $res->can('then');
  $res->then(sub { $new->$method(@result) }, sub { $new->$method(@result) });
}

sub _settle {
  my ($self, $status) = (shift, shift);
  return $self if $self->{result};
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
  if (my $cb = shift @{$self->{steps}}) {
    unless (eval { $self->$cb(@args); 1 }) {
      my $err = $@;
      @{$self}{qw(fail steps)} = (1, []);
      return $self->reject($err)->emit(error => $err);
    }
  }

  ($self->{steps} = []) and return $self->resolve(@args)->emit(finish => @args)
    unless $self->{counter};
  $self->ioloop->next_tick($self->begin) unless $self->{pending};
  return $self;
}

sub _then {
  my ($new, $cb, $method, @result) = @_;

  return $new->$method(@result) unless defined $cb;

  my @res;
  return $new->reject($@) unless eval { @res = $cb->(@result); 1 };

  return $new->$method(@res)
    unless @res == 1 && blessed $res[0] && $res[0]->can('then');

  $res[0]->then(sub { $new->resolve(@_); () }, sub { $new->reject(@_); () });
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Delay - Promises/A+ and flow-control helpers

=head1 SYNOPSIS

  use Mojo::IOLoop::Delay;

  # Wrap continuation-passing style APIs with promises
  my $ua = Mojo::UserAgent->new;
  sub get {
    my $promise = Mojo::IOLoop::Delay->new;
    $ua->get(@_ => sub {
      my ($ua, $tx) = @_;
      $promise->resolve($tx);
    });
    return $promise;
  }
  my $mojo = get('http://mojolicious.org');
  my $cpan = get('http://metacpan.org');
  $mojo->race($cpan)->then(sub { say shift->req->url })->wait;

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

  # Instead of nested closures we now have a simple chain of steps
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
exactly when our chain of L</"steps"> and/or promises has reached the end. So
L</"wait"> can stop the event loop automatically if it had to be started at all
in the first place.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Delay> implements the following attributes.

=head2 ioloop

  my $loop = $delay->ioloop;
  $delay   = $delay->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Delay> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 all

  my $new = $delay->all(@delays);

Returns a new L<Mojo::IOLoop::Delay> object that either fulfills when all of the
passed L<Mojo::IOLoop::Delay> objects have fulfilled or rejects as soon as one
of them rejects. If the returned promise fulfills, it is fulfilled with the
values from the fulfilled promises in the same order as the passed promises.
This method can be useful for aggregating results of multiple promises.

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

Appends a rejection handler callback to the promise, and returns a new
L<Mojo::IOLoop::Delay> object resolving to the return value of the callback if
it is called, or to its original fulfillment value if the promise is instead
fulfilled.

  # Longer version
  my $new = $delay->then(undef, sub {...});

  # Pass along the rejection reason
  $delay->catch(sub {
    my @reason = @_;
    warn "Something went wrong: $reason[0]";
    return @reason;
  });

  # Change the rejection reason
  $delay->catch(sub {
    my @reason = @_;
    return "This is bad: $reason[0]";
  });

=head2 finally

  my $new = $delay->finally(sub {...});

Appends a fulfillment and rejection handler to the promise, and returns a new
L<Mojo::IOLoop::Delay> object resolving to the original fulfillment value or
rejection reason.

  # Do something on fulfillment and rejection
  $delay->finally(sub {
    my @value_or_reason = @_;
    say "We are done!";
  });

=head2 pass

  $delay = $delay->pass;
  $delay = $delay->pass(@args);

Shortcut for passing values between L</"steps">.

  # Longer version
  $delay->begin(0)->(@args);

=head2 race

  my $new = $delay->race(@delays);

Returns a new L<Mojo::IOLoop::Delay> object that fulfills or rejects as soon as
one of the passed L<Mojo::IOLoop::Delay> objects fulfills or rejects, with the
value or reason from that promise.

=head2 reject

  $delay = $delay->reject(@reason);

Reject the promise with one or more rejection reasons.

=head2 resolve

  $delay = $delay->resolve(@value);

Resolve the promise with one or more fulfillment values.

=head2 steps

  $delay = $delay->steps(sub {...}, sub {...});

Sequentialize multiple events, every time the event counter reaches zero a
callback will run, the first one automatically runs during the next reactor tick
unless it is delayed by incrementing the event counter. This chain will continue
until there are no remaining callbacks, a callback does not increment the event
counter or an exception gets thrown in a callback. Finishing the chain will also
result in the promise being fulfilled, or if an exception got thrown it will be
rejected.

=head2 then

  my $new = $delay->then(sub {...});
  my $new = $delay->then(sub {...}, sub {...});
  my $new = $delay->then(undef, sub {...});

Appends fulfillment and rejection handlers to the promise, and returns a new
L<Mojo::IOLoop::Delay> object resolving to the return value of the called
handler.

  # Pass along the fulfillment value or rejection reason
  $delay->then(sub {
    my @value = @_;
    say "The result is $value[0]";
    return @value;
  },
  sub {
    my @reason = @_;
    warn "Something went wrong: $reason[0]";
    return @reason;
  });

  # Change the fulfillment value or rejection reason
  $delay->then(sub {
    my @value = @_;
    return "This is good: $value[0]";
  },
  sub {
    my @reason = @_;
    return "This is bad: $reason[0]";
  });

=head2 wait

  $delay->wait;

Start L</"ioloop"> and stop it again once the promise has been fulfilled or
rejected, does nothing when L</"ioloop"> is already running.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
