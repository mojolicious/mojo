package Mojo::EventEmitter;
use Mojo::Base -base;

use Scalar::Util qw(blessed weaken);

use constant DEBUG => $ENV{MOJO_EVENTEMITTER_DEBUG} || 0;

sub emit {
  my ($self, $name) = (shift, shift);

  if (my $s = $self->{events}{$name}) {
    warn "-- Emit $name in @{[blessed($self)]} (@{[scalar(@$s)]})\n" if DEBUG;
    for my $cb (@$s) { $self->$cb(@_) }
  }
  else {
    warn "-- Emit $name in @{[blessed($self)]} (0)\n" if DEBUG;
    warn $_[0] if $name eq 'error';
  }

  return $self;
}

sub emit_safe {
  my ($self, $name) = (shift, shift);

  if (my $s = $self->{events}{$name}) {
    warn "-- Emit $name in @{[blessed($self)]} safely (@{[scalar(@$s)]})\n"
      if DEBUG;
    for my $cb (@$s) {
      unless (eval { $self->$cb(@_); 1 }) {

        # Error event failed
        if ($name eq 'error') { warn qq{Event "error" failed: $@} }

        # Normal event failed
        else { $self->emit_safe('error', qq{Event "$name" failed: $@}) }
      }
    }
  }
  else {
    warn "-- Emit $name in @{[blessed($self)]} safely (0)\n" if DEBUG;
    warn $_[0] if $name eq 'error';
  }

  return $self;
}

sub has_subscribers { !!@{shift->subscribers(shift)} }

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

sub unsubscribe {
  my ($self, $name, $cb) = @_;

  # One
  if ($cb) {
    $self->{events}{$name} = [grep { $cb ne $_ } @{$self->{events}{$name}}];
  }

  # All
  else { delete $self->{events}{$name} }

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

=head1 EVENTS

L<Mojo::EventEmitter> can emit the following events.

=head2 error

  $e->on(error => sub {
    my ($e, $err) = @_;
    ...
  });

Emitted safely for event errors.

  $e->on(error => sub {
    my ($e, $err) = @_;
    say "This looks bad: $err";
  });

=head1 METHODS

L<Mojo::EventEmitter> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 emit

  $e = $e->emit('foo');
  $e = $e->emit('foo', 123);

Emit event.

=head2 emit_safe

  $e = $e->emit_safe('foo');
  $e = $e->emit_safe('foo', 123);

Emit event safely and emit C<error> event on failure.

=head2 has_subscribers

  my $success = $e->has_subscribers('foo');

Check if event has subscribers.

=head2 on

  my $cb = $e->on(foo => sub {...});

Subscribe to event.

  $e->on(foo => sub {
    my ($e, @args) = @_;
    ...
  });

=head2 once

  my $cb = $e->once(foo => sub {...});

Subscribe to event and unsubscribe again after it has been emitted once.

  $e->once(foo => sub {
    my ($e, @args) = @_;
    ...
  });

=head2 subscribers

  my $subscribers = $e->subscribers('foo');

All subscribers for event.

  # Unsubscribe last subscriber
  $e->unsubscribe(foo => $e->subscribers('foo')->[-1]);

=head2 unsubscribe

  $e = $e->unsubscribe('foo');
  $e = $e->unsubscribe(foo => $cb);

Unsubscribe from event.

=head1 DEBUGGING

You can set the MOJO_EVENTEMITTER_DEBUG environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_EVENTEMITTER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
