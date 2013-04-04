package Mojo::IOLoop::Delay;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;

has ioloop => sub { Mojo::IOLoop->singleton };

sub begin {
  my $self = shift;
  $self->{counter}++;
  my $id = $self->{id}++;
  return sub { shift; $self->_step($id, @_) };
}

sub end { shift->_step(undef, @_) }

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

  # Arguments
  my $ordered   = $self->{ordered}   ||= [];
  my $unordered = $self->{unordered} ||= [];
  if (defined $id) { $ordered->[$id] = [@_] }
  else             { push @$unordered, @_ }

  # Wait for more events
  return $self->{counter} if --$self->{counter} || $self->{step};

  # Next step
  my $cb = shift @{$self->{steps} ||= []};
  $self->{$_} = [] for qw(ordered unordered);
  my @args = ((map {@$_} grep {defined} @$ordered), @$unordered);
  local $self->{step} = 1;
  $self->$cb(@args) if $cb;
  $self->emit('finish', @args) unless $self->{counter};

  return 0;
}

1;

=head1 NAME

Mojo::IOLoop::Delay - Control the flow of events

=head1 SYNOPSIS

  use Mojo::IOLoop::Delay;

  # Synchronize multiple events
  my $delay = Mojo::IOLoop::Delay->new;
  $delay->on(finish => sub { say 'BOOM!' });
  for my $i (1 .. 10) {
    $delay->begin;
    Mojo::IOLoop->timer($i => sub {
      say 10 - $i;
      $delay->end;
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

L<Mojo::IOLoop::Delay> controls the flow of events for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Delay> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 finish

  $delay->on(finish => sub {
    my ($delay, @args) = @_;
    ...
  });

Emitted once the active event counter reaches zero or there are no more steps.

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

Increment active event counter, the returned callback can be used instead of
C<end>, which has the advantage of preserving the order of arguments. Note
that the first argument passed to the callback will be ignored.

  my $delay = Mojo::IOLoop->delay;
  Mojo::UserAgent->new->get('mojolicio.us' => $delay->begin);
  my $tx = $delay->wait;

=head2 end

  my $remaining = $delay->end;
  my $remaining = $delay->end(@args);

Decrement active event counter, all arguments are queued for the next step or
C<finish> event and C<wait> method.

=head2 steps

  $delay = $delay->steps(sub {...}, sub {...});

Sequentialize multiple events, the first callback will run right away, and the
next one once the active event counter reaches zero, this chain will continue
until there are no more callbacks left.

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
