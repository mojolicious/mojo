package Mojo::IOLoop::Delay;
use Mojo::Base 'Mojo::EventEmitter';

use Mojo::IOLoop;

has ioloop => sub { Mojo::IOLoop->singleton };

# "Ah, alcohol and night-swimming. It's a winning combination."
sub begin {
  my $self = shift;
  $self->{counter}++;
  return sub { shift; $self->end(@_) };
}

sub end {
  my $self = shift;
  push @{$self->{args} ||= []}, @_;
  $self->emit_safe('finish', @{$self->{args}}) if --$self->{counter} <= 0;
  return $self->{counter};
}

# "Mrs. Simpson, bathroom is not for customers.
#  Please use the crack house across the street."
sub wait {
  my $self = shift;
  $self->once(finish => sub { shift->ioloop->stop });
  $self->ioloop->start;
  return wantarray ? @{$self->{args}} : $self->{args}[0];
}

1;

=head1 NAME

Mojo::IOLoop::Delay - Synchronize events

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

  # Wait for events if necessary
  $delay->wait unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Delay> synchronizes events for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Delay> can emit the following events.

=head2 C<finish>

  $delay->on(finish => sub {
    my ($delay, @args) = @_;
    ...
  });

Emitted safely once the active event counter reaches zero.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Delay> implements the following attributes.

=head2 C<ioloop>

  my $ioloop = $delay->ioloop;
  $delay     = $delay->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop>
singleton.

=head1 METHODS

L<Mojo::IOLoop::Delay> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<begin>

  my $cb = $delay->begin;

Increment active event counter, the returned callback can be used instead of
C<end>. Note that the first argument passed to the callback will be ignored.

  my $delay = Mojo::IOLoop->delay;
  Mojo::UserAgent->new->get('mojolicio.us' => $delay->begin);
  my $tx = $delay->wait;

=head2 C<end>

  my $remaining = $delay->end;
  my $remaining = $delay->end(@args);

Decrement active event counter, all arguments are queued for the C<finish>
event and C<wait> method.

=head2 C<wait>

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
