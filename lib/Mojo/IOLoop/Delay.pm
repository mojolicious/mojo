package Mojo::IOLoop::Delay;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;

has ioloop => sub { Mojo::IOLoop->singleton };

sub begin {
  my ($self, $ignore) = @_;
  $self->{pending}++;
  my $id = $self->{counter}++;
  return sub { $ignore // 1 and shift; $self->_step($id, @_) };
}

sub steps {
  my $self = shift;
  $self->{steps} = [@_];
  $self->begin->();
  return $self;
}

sub wait {
  my $self = shift;
  my @args;
  $self->once(finish => sub { shift->ioloop->stop; @args = @_ });
  $self->ioloop->start;
  return wantarray ? @args : $args[0];
}

sub _step {
  my ($self, $id) = (shift, shift);

  $self->{args}[$id] = [@_];
  return $self->{pending} if --$self->{pending} || $self->{lock};
  local $self->{lock} = 1;
  my @args = map {@$_} @{delete $self->{args}};

  $self->{counter} = 0;
  if (my $cb = shift @{$self->{steps} ||= []}) { $self->$cb(@args) }

  if (!$self->{counter}) { $self->emit(finish => @args) }
  elsif (!$self->{pending}) { $self->ioloop->timer(0 => $self->begin) }
  return 0;
}

1;

=head1 NAME

Mojo::IOLoop::Delay - Manage callbacks and control the flow of events

=head1 SYNOPSIS

  use Mojo::IOLoop::Delay;

  # Synchronize multiple events
  my $delay = Mojo::IOLoop::Delay->new;
  $delay->on(finish => sub { say 'BOOM!' });
  for my $i (1 .. 10) {
    my $end = $delay->begin;
    Mojo::IOLoop->timer($i => sub {
      say 10 - $i;
      $end->();
    });
  }

  # Sequentialize multiple events
  my $delay = Mojo::IOLoop::Delay->new;
  $delay->steps(

    # First step (simple timer)
    sub {
      my $delay = shift;
      Mojo::IOLoop->timer(2 => $delay->begin);
      say 'Second step in 2 seconds.';
    },

    # Second step (parallel timers)
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
  );

  # Wait for events if necessary
  $delay->wait unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Delay> manages callbacks and controls the flow of events for
L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Delay> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

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
  my $cb = $delay->begin(0);

Increment active event counter, the returned callback can be used to decrement
the active event counter again. Arguments passed to the callback are queued in
the right order for the next step or C<finish> event and C<wait> method, the
first argument will be ignored by default.

  # Capture all arguments
  my $delay = Mojo::IOLoop->delay;
  Mojo::IOLoop->client({port => 3000} => $delay->begin(0));
  my ($loop, $err, $stream) = $delay->wait;

=head2 steps

  $delay = $delay->steps(sub {...}, sub {...});

Sequentialize multiple events, the first callback will run right away, and the
next one once the active event counter reaches zero, this chain will continue
until there are no more callbacks or a callback does not increment the active
event counter.

=head2 wait

  my @args = $delay->wait;

Start C<ioloop> and stop it again once the C<finish> event gets emitted, only
works when C<ioloop> is not running already.

  # Use the "finish" event to synchronize portably
  $delay->on(finish => sub {
    my ($delay, @args) = @_;
    ...
  });
  $delay->wait unless $delay->ioloop->is_running;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
