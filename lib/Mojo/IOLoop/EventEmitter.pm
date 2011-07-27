package Mojo::IOLoop::EventEmitter;
use Mojo::Base -base;

use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_EVENTEMITTER_DEBUG} || 0;

# "Back you robots!
#  Nobody ruins my family vacation but me!
#  And maybe the boy."
sub emit {
  my $self = shift;
  my $name = shift;

  # Emit event sequentially to all subscribers
  my @subscribers = @{$self->subscribers($name)};
  warn "EMIT $name (" . scalar(@subscribers) . ")\n" if DEBUG;
  for my $cb (@subscribers) {
    $self->emit('error', qq/Event "$name" failed: $@/)
      if !eval { $self->$cb(@_); 1 } && $name ne 'error';
  }

  return $self;
}

sub on {
  my ($self, $name, $cb) = @_;
  my $subscribers = $self->{events}->{$name} ||= [];
  push @$subscribers, $cb;
  return $cb;
}

sub once {
  my ($self, $name, $cb) = @_;
  my $wrapper;
  $wrapper = sub {
    my $self = shift;
    $self->$cb(@_);
    $self->unsubscribe($name => $wrapper);
  };
  $self->on($name => $wrapper);
  weaken $wrapper;
  return $wrapper;
}

sub subscribers {
  my ($self, $name) = @_;
  $self->{events}->{error} ||= [sub { warn $_[1] }] if $name eq 'error';
  return [@{$self->{events}->{$name} || []}];
}

sub unsubscribe {
  my ($self, $name, $cb) = @_;
  my $subscribers = $self->{events}->{$name} || [];
  my @callbacks;
  for my $subscriber (@$subscribers) {
    next if $cb eq $subscriber;
    push @callbacks, $subscriber;
  }
  $self->{events}->{$name} = \@callbacks;
  return $self;
}

1;
__END__

=head1 NAME

Mojo::IOLoop::EventEmitter - IOLoop Event Emitter

=head1 SYNOPSIS

  use Mojo::IOLoop::EventEmitter;

  # Create new event emitter
  my $e = Mojo::IOLoop::EventEmitter->new;

  # Subscribe to events
  $e->on(error => sub {
    my ($self, $error) = @_;
    warn "Catched: $error";
  });
  $e->on(test => sub {
    my ($self, $message) = @_;
    die "test: $message";
  });

  # Emit events
  $e->emit(test => 'Hello!');

=head1 DESCRIPTION

L<Mojo::IOLoop::EventEmitter> is the event emitter used by L<Mojo::IOLoop>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 METHODS

L<Mojo::IOLoop::EventEmitter> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<emit>

  $e->emit('foo');
  $e->emit('foo', 123);

Emit event.

=head2 C<on>

  my $cb = $e->on(foo => sub {...});

Subscribe to event.

=head2 C<once>

  my $cb = $e->once(foo => sub {...});

Subscribe to event and unsubscribe again after it has been emitted once.

=head2 C<subscribers>

  my $subscribers = $e->subscribers('foo');

All subscribers for event.

=head2 C<unsubscribe>

  $e->unsubscribe(foo => $cb);

Unsubscribe from event.

=head1 DEBUGGING

You can set the C<MOJO_EVENTEMITTER_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_EVENTEMITTER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
