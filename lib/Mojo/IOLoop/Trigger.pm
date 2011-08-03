package Mojo::IOLoop::Trigger;
use Mojo::Base 'Mojo::IOLoop::EventEmitter';

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
  $self->emit('done', @{$self->{args}}) if --$self->{counter} <= 0;
}

sub start {
  my $self = shift;
  $self->once(done => sub { shift->ioloop->stop });
  $self->ioloop->start;
  return @{$self->{args}};
}

1;
__END__

=head1 NAME

Mojo::IOLoop::Trigger - IOLoop Trigger

=head1 SYNOPSIS

  use Mojo::IOLoop::Trigger;

  # Synchronize multiple events
  my $t = Mojo::IOLoop::Trigger->new;
  $t->on(done => sub { print "BOOM!\n" });
  for my $i (1 .. 10) {
    $t->begin;
    Mojo::IOLoop->timer($i => sub {
      print 10 - $i, "\n";
      $t->end;
    });
  }

  # Stop automatically when done
  $t->start;

=head1 DESCRIPTION

L<Mojo::IOLoop::Trigger> is a remote control for L<Mojo::IOLoop>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::IOLoop::Trigger> implements the following attributes.

=head2 C<ioloop>

  my $ioloop = $t->ioloop;
  $t         = $t->ioloop(Mojo::IOLoop->new);

Loop object to control, defaults to a L<Mojo::IOLoop> object.

=head1 METHODS

L<Mojo::IOLoop::Trigger> inherits all methods from
L<Mojo::IOLoop::EventEmitter> and implements the following new ones.

=head2 C<begin>

  my $cb = $t->begin;

Increment active event counter, the returned callback can be used instead of
C<end>.

  my $t = Mojo::IOLoop->trigger;
  Mojo::IOLoop->resolver->lookup('mojolicio.us' => $t->begin);
  my $address = $t->start;

=head2 C<end>

  $t->end;
  $t->end(@args);

Decrement active event counter.

=head2 C<start>

  my @args = $t->start;

Start C<ioloop> and register C<done> event that stops it again once the
active event counter reaches zero.

=head1 EVENTS

L<Mojo::IOLoop::Trigger> can emit the following events.

=head2 C<done>

Emitted once the active event counter reaches zero.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
