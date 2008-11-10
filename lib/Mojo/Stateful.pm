# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Stateful;

use strict;
use warnings;

use base 'Mojo::Base';

# Don't kid yourself, Jimmy. If a cow ever got the chance,
# he'd eat you and everyone you care about!
__PACKAGE__->attr('state', chained => 1, default => 'start');

sub done { shift->state('done') }

sub error {
    my ($self, $message) = @_;
    return $self->{error} unless $message;
    $self->state('error');
    return $self->{error} = $message;
}

sub has_error { return defined shift->{error} }

sub is_done { return shift->state eq 'done' }

sub is_state {
    my ($self, @states) = @_;
    for my $state (@states) { return 1 if $self->state eq $state }
    return 0;
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

=head2 C<error>

    my $error = $stateful->error;
    $stateful = $stateful->error('Parser error: test 123');

=head2 C<state>

   my $state = $stateful->state;
   $stateful = $stateful->state('writing');

=head1 METHODS

L<Mojo::Stateful> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<done>

    $stateful = $stateful->done;

=head2 C<has_error>

    my $has_error = $stateful->has_error;

=head2 C<is_done>

    my $done = $stateful->is_done;

=head2 C<is_state>

    my $is_state = $stateful->is_state('writing');
    my $is_state = $stateful->is_state(qw/error reading writing/);

=cut