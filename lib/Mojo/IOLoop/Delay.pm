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
}

sub wait {
  my $self = shift;
  $self->once(finish => sub { shift->ioloop->stop });
  $self->ioloop->start;
  return @{$self->{args}};
}

1;
__END__

=head1 NAME

Mojo::IOLoop::Delay - IOLoop delay

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

  # Wait for events
  $delay->wait;

=head1 DESCRIPTION

L<Mojo::IOLoop::Delay> synchronizes events for L<Mojo::IOLoop>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 EVENTS

L<Mojo::IOLoop::Delay> can emit the following events.

=head2 C<finish>

  $delay->on(finish => sub {
    my $delay = shift;
  });

Emitted once the active event counter reaches zero.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Delay> implements the following attributes.

=head2 C<ioloop>

  my $ioloop = $delay->ioloop;
  $delay     = $delay->ioloop(Mojo::IOLoop->new);

Loop object to control, defaults to the global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Delay> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<begin>

  my $cb = $delay->begin;

Increment active event counter, the returned callback can be used instead of
C<end>.

  my $delay = Mojo::IOLoop->delay;
  Mojo::IOLoop->resolver->lookup('mojolicio.us' => $delay->begin);
  my $address = $delay->wait;

=head2 C<end>

  $delay->end;
  $delay->end(@args);

Decrement active event counter.

=head2 C<wait>

  my @args = $delay->wait;

Start C<ioloop> and register C<finish> event that stops it again once the
active event counter reaches zero.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
