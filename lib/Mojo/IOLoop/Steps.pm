package Mojo::IOLoop::Steps;
use Mojo::Base -base;

sub new {
  my $self = shift->SUPER::new(steps => [@_]);
  $self->next->();
  return $self;
}

# "My god, it's full of geezers."
sub next {
  my $self = shift;
  $self->{counter}++;
  return sub { shift; $self->_step(@_) };
}

sub _step {
  my $self = shift;

  my $args = $self->{args} ||= [];
  push @$args, @_;

  return unless --$self->{counter} <= 0;
  return unless my $cb = shift @{$self->{steps}};
  $self->{args} = [];
  $self->$cb(@$args);
}

1;

=head1 NAME

Mojo::IOLoop::Steps - Control flow of events

=head1 SYNOPSIS

  use Mojo::IOLoop::Steps;

  # Control the flow of multiple events
  Mojo::IOLoop::Steps->new(

    # First step (simple timer)
    sub {
      my $steps = shift;
      Mojo::IOLoop->timer(2 => $steps->next);
      say 'Second step in 2 seconds.';
    },

    # Second step (parallel timers)
    sub {
      my ($steps, @args) = @_;
      Mojo::IOLoop->timer(1 => $steps->next);
      Mojo::IOLoop->timer(3 => $steps->next);
      say 'Third step in 3 seconds.';
    },

    # Third step (the end)
    sub {
      my ($steps, @args) = @_;
      say 'And done after 5 seconds total.';
    }
  );

  # Start event loop if necessary
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Steps> controls the flow of events for L<Mojo::IOLoop>.

=head1 METHODS

L<Mojo::IOLoop::Steps> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

  my $steps = Mojo::IOLoop::Steps->new(sub {...}, sub {...});

Construct a new L<Mojo::IOLoop::Steps> object.

=head2 C<next>

  my $cb = $steps->next;

Generate callback for next step, all generated callbacks need to be invoked
before the next step can be reached. All arguments passed to the callback,
except for the first one, are queued and passed through to the next step.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
