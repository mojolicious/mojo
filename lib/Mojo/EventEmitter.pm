package Mojo::EventEmitter;
use Mojo::Base -base;

use Scalar::Util qw/blessed weaken/;

use constant DEBUG => $ENV{MOJO_EVENTEMITTER_DEBUG} || 0;

# "Are we there yet?
#  No
#  Are we there yet?
#  No
#  Are we there yet?
#  No
#  ...Where are we going?"
sub emit {
  my ($self, $name) = (shift, shift);
  if (my $s = $self->{events}{$name}) {
    warn "-- Emit @{[blessed($self)]} $name (@{[scalar(@$s)]})\n" if DEBUG;
    for my $cb (@$s) { $self->$cb(@_) }
  }
  elsif (DEBUG) { warn "-- Emit @{[blessed($self)]} $name (0)\n" }
  return $self;
}

sub emit_safe {
  my ($self, $name) = (shift, shift);

  if (my $s = $self->{events}{$name}) {
    warn "-- Safe @{[blessed($self)]} $name (@{[scalar(@$s)]})\n" if DEBUG;
    for my $cb (@$s) {
      if (!eval { $self->$cb(@_); 1 } && $name ne 'error') {
        $self->once(error => sub { warn $_[1] })
          unless $self->has_subscribers('error');
        $self->emit_safe('error', qq/Event "$name" failed: $@/);
      }
    }
  }
  elsif (DEBUG) { warn "-- Safe @{[blessed($self)]} $name (0)\n" }

  return $self;
}

sub has_subscribers { scalar @{shift->subscribers(shift)} }

sub on {
  my ($self, $name, $cb) = @_;
  push @{$self->{events}{$name} ||= []}, $cb;
  return $cb;
}

sub once {
  my ($self, $name, $cb) = @_;

  weaken $self;
  my $wrapper;
  $wrapper = sub {
    $self->unsubscribe($name => $wrapper);
    $cb->(@_);
  };
  $self->on($name => $wrapper);
  weaken $wrapper;

  return $wrapper;
}

sub subscribers { shift->{events}{shift()} || [] }

# "Back you robots!
#  Nobody ruins my family vacation but me!
#  And maybe the boy."
sub unsubscribe {
  my ($self, $name, $cb) = @_;

  # All
  unless ($cb) {
    delete $self->{events}{$name};
    return $self;
  }

  # One
  $self->{events}{$name} = [grep { $cb ne $_ } @{$self->{events}{$name}}];

  return $self;
}

1;

=head1 NAME

Mojo::EventEmitter - Event emitter base class

=head1 SYNOPSIS

  package Cat;
  use Mojo::Base 'Mojo::EventEmitter';

  # Emit events
  sub poke {
    my $self = shift;
    $self->emit(roar => 3);
  }

  package main;

  # Subscribe to events
  my $tiger = Cat->new;
  $tiger->on(roar => sub {
    my ($tiger, $times) = @_;
    say 'RAWR!' for 1 .. $times;
  });
  $tiger->poke;

=head1 DESCRIPTION

L<Mojo::EventEmitter> is a simple base class for event emitting objects.

=head1 METHODS

L<Mojo::EventEmitter> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<emit>

  $e = $e->emit('foo');
  $e = $e->emit('foo', 123);

Emit event.

=head2 C<emit_safe>

  $e = $e->emit_safe('foo');
  $e = $e->emit_safe('foo', 123);

Emit event safely and emit C<error> event on failure.

=head2 C<has_subscribers>

  my $success = $e->has_subscribers('foo');

Check if event has subscribers.

=head2 C<on>

  my $cb = $e->on(foo => sub {...});

Subscribe to event.

  $e->on(foo => sub {
    my ($e, @args) = @_;
    ...
  });

=head2 C<once>

  my $cb = $e->once(foo => sub {...});

Subscribe to event and unsubscribe again after it has been emitted once.

  $e->once(foo => sub {
    my ($e, @args) = @_;
    ...
  });

=head2 C<subscribers>

  my $subscribers = $e->subscribers('foo');

All subscribers for event.

  # Unsubscribe last subscriber
  $e->unsubscribe(foo => $e->subscribers('foo')->[-1]);

=head2 C<unsubscribe>

  $e = $e->unsubscribe('foo');
  $e = $e->unsubscribe(foo => $cb);

Unsubscribe from event.

=head1 DEBUGGING

You can set the C<MOJO_EVENTEMITTER_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_EVENTEMITTER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
