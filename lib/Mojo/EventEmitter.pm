package Mojo::EventEmitter;
use Mojo::Base -base;

use Scalar::Util qw(blessed weaken);

use constant DEBUG => $ENV{MOJO_EVENTEMITTER_DEBUG} || 0;

sub catch { $_[0]->on(error => $_[1]) and return $_[0] }

sub emit {
  my ($self, $name) = (shift, shift);

  if (my $s = $self->{events}{$name}) {
    warn "-- Emit $name in @{[blessed $self]} (@{[scalar @$s]})\n" if DEBUG;
    for my $cb (@$s) { $self->$cb(@_) }
  }
  else {
    warn "-- Emit $name in @{[blessed $self]} (0)\n" if DEBUG;
    die "@{[blessed $self]}: $_[0]"                  if $name eq 'error';
  }

  return $self;
}

sub has_subscribers { !!shift->{events}{shift()} }

sub on { push @{$_[0]{events}{$_[1]}}, $_[2] and return $_[2] }

sub once {
  my ($self, $name, $cb) = @_;

  weaken $self;
  my $wrapper = sub {
    $self->unsubscribe($name => __SUB__);
    $cb->(@_);
  };
  $self->on($name => $wrapper);

  return $wrapper;
}

sub subscribers { shift->{events}{shift()} //= [] }

sub unsubscribe {
  my ($self, $name, $cb) = @_;

  # One
  if ($cb) {
    $self->{events}{$name} = [grep { $cb ne $_ } @{$self->{events}{$name}}];
    delete $self->{events}{$name} unless @{$self->{events}{$name}};
  }

  # All
  else { delete $self->{events}{$name} }

  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::EventEmitter - Event emitter base class

=head1 SYNOPSIS

  package Cat;
  use Mojo::Base 'Mojo::EventEmitter', -signatures;

  # Emit events
  sub poke ($self) { $self->emit(roar => 3) }

  package main;

  # Subscribe to events
  my $tiger = Cat->new;
  $tiger->on(roar => sub ($tiger, $times) { say 'RAWR!' for 1 .. $times });
  $tiger->poke;

=head1 DESCRIPTION

L<Mojo::EventEmitter> is a simple base class for event emitting objects.

=head1 EVENTS

L<Mojo::EventEmitter> can emit the following events.

=head2 error

  $e->on(error => sub ($e, $err) {...});

This is a special event for errors, it will not be emitted directly by this class, but is fatal if unhandled.
Subclasses may choose to emit it, but are not required to do so.

  $e->on(error => sub ($e, $err) { say "This looks bad: $err" });

=head1 METHODS

L<Mojo::EventEmitter> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 catch

  $e = $e->catch(sub {...});

Subscribe to L</"error"> event.

  # Longer version
  $e->on(error => sub {...});

=head2 emit

  $e = $e->emit('foo');
  $e = $e->emit('foo', 123);

Emit event.

=head2 has_subscribers

  my $bool = $e->has_subscribers('foo');

Check if event has subscribers.

=head2 on

  my $cb = $e->on(foo => sub {...});

Subscribe to event.

  $e->on(foo => sub ($e, @args) {...});

=head2 once

  my $cb = $e->once(foo => sub {...});

Subscribe to event and unsubscribe again after it has been emitted once.

  $e->once(foo => sub ($e, @args) {...});

=head2 subscribers

  my $subscribers = $e->subscribers('foo');

All subscribers for event.

  # Unsubscribe last subscriber
  $e->unsubscribe(foo => $e->subscribers('foo')->[-1]);

  # Change order of subscribers
  @{$e->subscribers('foo')} = reverse @{$e->subscribers('foo')};

=head2 unsubscribe

  $e = $e->unsubscribe('foo');
  $e = $e->unsubscribe(foo => $cb);

Unsubscribe from event.

=head1 DEBUGGING

You can set the C<MOJO_EVENTEMITTER_DEBUG> environment variable to get some advanced diagnostics information printed to
C<STDERR>.

  MOJO_EVENTEMITTER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
