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
    my $self = shift;

    # Get
    unless (@_) {

        # No error
        return unless $self->has_error;

        # Default
        my $error = $self->{error} || ['Unknown error.', 500];

        # Context
        return wantarray ? @$error : $error->[0];
    }

    # Set
    $self->{error} = [@_];
    $self->state('error');

    return $self;
}

sub has_error { shift->state eq 'error' }

sub is_done { shift->state eq 'done' }

sub is_finished { shift->is_state(qw/done done_with_leftovers error/) }

sub is_state {
    my $self = shift;
    my $state = $self->{state} || 'start';
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

L<Mojo::Stateful> is an abstract base class for state keeping objects.

=head1 ATTRIBUTES

L<Mojo::Stateful> implements the following attributes.

=head2 C<state_cb>

   my $cb    = $stateful->state_cb;
   $stateful = $stateful->state_cb(sub {...});

Callback that will be invoked whenever the state of this object changes.

=head1 METHODS

L<Mojo::Stateful> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<done>

    $stateful = $stateful->done;

Shortcut for setting the current state to C<done>.

=head2 C<error>

    my $message          = $stateful->error;
    my ($message, $code) = $stateful->error;
    $stateful            = $stateful->error('Parser error.');
    $stateful            = $stateful->error('Parser error.', 500);

Shortcut for setting the current state to C<error> with C<code> and
C<message>.

=head2 C<has_error>

    my $has_error = $stateful->has_error;

Check if an error occured.

=head2 C<is_done>

    my $done = $stateful->is_done;

Check if the state machine is C<done>.

=head2 C<is_finished>

    my $finished = $stateful->is_finished;

Check if the state machine is finished, this includes the states C<done>,
C<done_with_leftovers> and C<error>.

=head2 C<is_state>

    my $is_state = $stateful->is_state('writing');
    my $is_state = $stateful->is_state(qw/error reading writing/);

Check if the state machine is currently in a specific state.

=head2 C<state>

    my $state = $stateful->state;
    $stateful = $stateful->state('writing');

The current state.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
