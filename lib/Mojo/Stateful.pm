# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Stateful;

use strict;
use warnings;

use base 'Mojo::Base';

# Don't kid yourself, Jimmy. If a cow ever got the chance,
# he'd eat you and everyone you care about!
__PACKAGE__->attr('state_cb');

sub done { shift->state('done') }

sub error {
    my ($self, $message) = @_;

    # Get
    if (!$message) {
        return ($self->{error} || 'Unknown state machine error.')
          if $self->has_error;
        return;
    }

    # Set
    $self->state('error');
    $self->{error} = $message;
    return $self;
}

sub has_error { shift->state eq 'error' }

sub is_done { shift->state eq 'done' }

sub is_finished { shift->is_state(qw/done done_with_leftovers error/) }

sub is_state {
    my $self  = shift;
    my $state = $self->state;
    $_ eq $state and return 1 for @_;
    return;
}

sub state {
    my ($self, $state) = @_;

    # Default
    $self->{state} ||= 'start';

    # Get
    return $self->{state} unless $state;

    # Old state
    my $old = $self->{state};

    # New state
    $self->{state} = $state;

    # Callback
    my $cb = $self->state_cb;
    $self->$cb($old, $state) if $cb;

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Stateful - Stateful Base Class

=head1 SYNOPSIS

    use base 'Mojo::Stateful';

=head1 DESCRIPTION

L<Mojo::Stateful> is a base class for state keeping instances.

=head1 ATTRIBUTES

L<Mojo::Stateful> implements the following attributes.

=head2 C<state_cb>

   my $cb    = $stateful->state_cb;
   $stateful = $stateful->state_cb(sub {...});

=head1 METHODS

L<Mojo::Stateful> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<done>

    $stateful = $stateful->done;

=head2 C<error>

    my $error = $stateful->error;
    $stateful = $stateful->error('Parser error: test 123');

=head2 C<has_error>

    my $has_error = $stateful->has_error;

=head2 C<is_done>

    my $done = $stateful->is_done;

=head2 C<is_finished>

    my $finished = $stateful->is_finished;

=head2 C<is_state>

    my $is_state = $stateful->is_state('writing');
    my $is_state = $stateful->is_state(qw/error reading writing/);

=head2 C<state>

    my $state = $stateful->state;
    $stateful = $stateful->state('writing');

=cut
