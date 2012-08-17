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
  my $id   = $self->{counter}++;
  return sub { shift; $self->_step($id, @_) };
}

sub _step {
  my ($self, $id) = (shift, shift);

  my $args = $self->{args} ||= [];
  $args->[$id] = [@_];

  return unless --$self->{counter} <= 0;
  return unless my $cb = shift @{$self->{steps}};
  $self->{args} = [];
  $self->$cb(map {@$_} @$args);
}

1;

=head1 NAME

Mojo::IOLoop::Steps - Sequentialize events

=head1 SYNOPSIS

  use Mojo::IOLoop::Steps;

  # Sequentialize multiple events
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

L<Mojo::IOLoop::Steps> sequentializes events for L<Mojo::IOLoop>.

=head1 METHODS

L<Mojo::IOLoop::Steps> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

  my $steps = Mojo::IOLoop::Steps->new(sub {...}, sub {...});

Construct a new L<Mojo::IOLoop::Steps> object.

=head2 C<next>

  my $cb = $steps->next;

Generate callback to next step, which will only be reached after all generated
callbacks have been invoked. The order in which callbacks have been generated
is preserved, and all arguments, except for the first one, will be queued and
passed through to the next step.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
