package Mojo::IOLoop::Delay;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;
use Mojo::Util;
use Hash::Util::FieldHash 'fieldhash';

has ioloop => sub { Mojo::IOLoop->singleton };

fieldhash my %REMAINING;

sub begin {
  my ($self, $offset, $len) = @_;
  $self->{pending}++;
  my $id = $self->{counter}++;
  return sub { $self->_step($id, $offset // 1, $len, @_) };
}

sub data { Mojo::Util::_stash(data => @_) }

sub pass { $_[0]->begin->(@_) }

sub remaining {
  my $self = shift;
  return $REMAINING{$self} //= [] unless @_;
  $REMAINING{$self} = shift;
  return $self;
}

sub steps {
  my $self = shift->remaining([@_]);
  $self->ioloop->next_tick($self->begin);
  return $self;
}

sub wait {
  my $self = shift;
  return if $self->ioloop->is_running;
  $self->once(error => \&_die);
  $self->once(finish => sub { shift->ioloop->stop });
  $self->ioloop->start;
}

sub _die { $_[0]->has_subscribers('error') ? $_[0]->ioloop->stop : die $_[1] }

sub _step {
  my ($self, $id, $offset, $len) = (shift, shift, shift, shift);

  $self->{args}[$id]
    = [@_ ? defined $len ? splice @_, $offset, $len : splice @_, $offset : ()];
  return $self if $self->{fail} || --$self->{pending} || $self->{lock};
  local $self->{lock} = 1;
  my @args = map {@$_} @{delete $self->{args}};

  $self->{counter} = 0;
  if (my $cb = shift @{$self->remaining}) {
    eval { $self->$cb(@args); 1 }
      or (++$self->{fail} and return $self->remaining([])->emit(error => $@));
  }

  return $self->remaining([])->emit(finish => @args) unless $self->{counter};
  $self->ioloop->next_tick($self->begin) unless $self->{pending};
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Delay - Manage callbacks and control the flow of events

=head1 SYNOPSIS

  use Mojo::IOLoop::Delay;

  # Synchronize multiple events
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

  # Sequentialize multiple events
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
    my ($delay, $err) = @_;
    say "Something went wrong: $err";
  })->wait;

=head1 DESCRIPTION

L<Mojo::IOLoop::Delay> manages callbacks and controls the flow of events for
L<Mojo::IOLoop>, which can help you avoid deep nested closures and memory
leaks that often result from continuation-passing style.

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

Emitted once the active event counter reaches zero and there are no more
steps.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Delay> implements the following attributes.

=head2 ioloop

  my $ioloop = $delay->ioloop;
  $delay     = $delay->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop>
singleton.

=head1 METHODS

L<Mojo::IOLoop::Delay> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 begin

  my $cb = $delay->begin;
  my $cb = $delay->begin($offset);
  my $cb = $delay->begin($offset, $len);

Indicate an active event by incrementing the active event counter, the
returned callback needs to be called when the event has completed, to
decrement the active event counter again. When all callbacks have been called
and the active event counter reached zero, L</"steps"> will continue.

  # Capture all arguments except for the first one (invocant)
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, $err, $stream) = @_;
    ...
  });
  Mojo::IOLoop->client({port => 3000} => $delay->begin);
  $delay->wait;

Arguments passed to the returned callback are spliced with the given offset
and length, defaulting to an offset of C<1> with no default length. The
arguments are then combined in the same order L</"begin"> was called, and
passed together to the next step or L</"finish"> event.

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

=head2 data

  my $hash = $delay->data;
  my $foo  = $delay->data('foo');
  $delay   = $delay->data({foo => 'bar'});
  $delay   = $delay->data(foo => 'bar');

Data shared between all L</"steps">.

  # Remove value
  my $foo = delete $delay->data->{foo};

  # Assign multiple values at once
  $delay->data(foo => 'test', bar => 23);

=head2 pass

  $delay = $delay->pass;
  $delay = $delay->pass(@args);

Increment active event counter and decrement it again right away to pass
values to the next step.

  # Longer version
  $delay->begin(0)->(@args);

=head2 remaining

  my $remaining = $delay->remaining;
  $delay        = $delay->remaining([]);

Remaining L</"steps"> in chain, stored outside the object to protect from
circular references.

=head2 steps

  $delay = $delay->steps(sub {...}, sub {...});

Sequentialize multiple events, every time the active event counter reaches
zero a callback will run, the first one automatically runs during the next
reactor tick unless it is delayed by incrementing the active event counter.
This chain will continue until there are no more callbacks, a callback does
not increment the active event counter or an exception gets thrown in a
callback.

=head2 wait

  $delay->wait;

Start L</"ioloop"> and stop it again once an L</"error"> or L</"finish"> event
gets emitted, does nothing when L</"ioloop"> is already running.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
