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

  # Cache arguments
  my $args = $self->{args} ||= [];
  push @$args, @_;

  # Next step
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
  my $steps = Mojo::IOLoop::Steps->new(
    sub {
      my $steps = shift;
      Mojo::IOLoop->timer(3 => $steps->next);
      Mojo::IOLoop->timer(1 => $steps->next);
    },
    sub {
      my ($steps, @args) = @_;
      Mojo::IOLoop->timer(2 => $steps->next);
    },
    sub {
      my ($steps, @args) = @_;
      say "Thank you for waiting 5 seconds.";
    }
  );

  # Start event loop if necessary
  Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Delay> controls the flow of events for L<Mojo::IOLoop>.

=head1 METHODS

L<Mojo::IOLoop::Steps> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<new>

  my $steps = Mojo::IOLoop::Steps->new(sub {...}, sub {...});

Construct a new L<Mojo::IOLoop::Steps> object.

=head2 C<next>

  my $cb = $steps->next;

Generate callback for getting to the next step. If more than one is generated,
they all have to be invoked before the next step can be reached. Note that the
first argument passed to the callback will be ignored.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
