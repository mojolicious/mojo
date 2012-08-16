package Mojo::IOLoop::Steps;
use Mojo::Base -base;

sub new {
  my $self = shift->SUPER::new(steps => [@_]);
  $self->_step();
  return $self;
}

# "My god, it's full of geezers."
sub _step {
  my $self = shift;

  # Arguments
  my $args = $self->{args} ||= [];
  push @$args, @_;
  $self->{args} = [];

  # Next step
  return unless my $cb = shift @{$self->{steps}};
  $cb->(sub { shift; $self->_step(@_) }, @$args);
}

1;

=head1 NAME

Mojo::IOLoop::Steps - Control flow of events

=head1 SYNOPSIS

  use Mojo::IOLoop::Steps;

  # Control the flow of multiple events
  Mojo::IOLoop::Steps->new(

    # First step
    sub {
      my $next = shift;
      say 'Waiting 2 seconds.';
      Mojo::IOLoop->timer(2 => $next);
    },

    # Second step
    sub {
      my ($next, @args) = @_;
      say 'Waiting 3 seconds.';
      Mojo::IOLoop->timer(3 => $next);
    },

    # Third step
    sub {
      my ($next, @args) = @_;
      say 'And done after 5 seconds.';
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

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
