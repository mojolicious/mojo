# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Transaction::Pipeline;

use strict;
use warnings;

use base 'Mojo::Transaction';

__PACKAGE__->attr([qw/active finished inactive/] => sub { [] });
__PACKAGE__->attr(safe_post => 0);

__PACKAGE__->attr('_all_written');
__PACKAGE__->attr(_current => 0);
__PACKAGE__->attr(_info => sub { [] });

# No children have ever meddled with the Republican Party and lived to tell
# about it.
sub new {
    my $self = shift->SUPER::new();

    # Transactions
    $self->active([@_]);

    # Cache client info
    $self->_info([$self->active->[0]->client_info]) if @_;

    return $self;
}

sub client_connect {
    my $self = shift;

    # Connect all
    $_->client_connect for @{$self->active};
    $self->state('connect');

    return $self;
}

sub client_connected {
    my $self = shift;

    # All connected
    for my $tx (@{$self->active}) {

        # Connected
        $tx->client_connected;

        # Meta information
        $tx->connection($self->connection);
        $tx->kept_alive($self->kept_alive);
        $tx->local_address($self->local_address);
        $tx->local_port($self->local_port);
        $tx->remote_address($self->remote_address);
        $tx->remote_port($self->remote_port);

    }
    $self->state('write_start_line');

    return $self;
}

sub client_get_chunk {
    my $self = shift;

    # Get chunk from current writer
    return $self->_current_active->client_get_chunk;
}

sub client_info { @{shift->_info} }

sub client_is_writing {
    my $self = shift;
    return $self->_is_writing($self->_first_active, $self->_current_active);
}

sub client_read {
    my ($self, $chunk) = @_;

    # Read with current reader
    $self->_first_active->client_read($chunk);

    # Transaction finished
    while ($self->_first_active->is_finished) {

        # Check for errors
        if ($self->_first_active->has_error) {
            $self->error('Transaction Error: ' . $self->_first_active->error);
            $self->_inactivate_first;
            return $self;
        }

        # All done?
        $self->done and return $self unless $self->_inactivate_first;

        # Check for leftovers
        if (my $leftovers = $self->client_leftovers) {
            $self->_first_active->client_read($leftovers);
        }
    }

    # Inherit state
    $self->_client_inherit_state;

    return $self;
}

sub client_leftovers {
    my $self = shift;

    # Inactive?
    my $leftovers;
    if ($self->inactive->[-1]) {

        # Leftovers
        $leftovers = $self->inactive->[-1]->client_leftovers;

        # Finish
        $self->_finish_inactive;
    }

    return $leftovers;
}

sub client_spin {
    my $self = shift;

    # Spin all
    $_->client_spin for @{$self->active};

    # Writing done?
    unless ($self->_all_written) {
        my $writer = $self->_current_active;
        if ($writer->is_state('read_response')) {

            # All written
            $self->_all_written(1) unless $self->_next_active;
        }
    }

    # Inherit state
    $self->_client_inherit_state;

    return $self;
}

sub client_written {
    my ($self, $length) = @_;

    # Written
    $self->_current_active->client_written($length);

    return $self;
}

sub server_accept {
    my ($self, $tx) = @_;

    # Meta information
    $tx->connection($self->connection);
    $tx->kept_alive($self->kept_alive);
    $tx->local_address($self->local_address);
    $tx->local_port($self->local_port);
    $tx->remote_address($self->remote_address);
    $tx->remote_port($self->remote_port);

    # Accept
    $tx->server_accept;

    # Active
    push @{$self->active}, $tx;

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_get_chunk {
    my $self = shift;

    # Get chunk from current writer
    return $self->_first_active->server_get_chunk;
}

sub server_handled {
    my $self = shift;

    # Handled current reader
    $self->server_tx->server_handled;

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_is_writing {
    my $self = shift;
    return $self->_is_writing($self->_current_active, $self->_first_active);
}

sub server_leftovers {
    my $self = shift;

    # Last active transaction
    my $active = $self->active->[-1];
    return unless $active;

    # No leftovers
    return unless $active->req->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $active->req->leftovers;

    # Done
    $active->req->done;

    return $leftovers;
}

sub server_read {
    my $self = shift;

    # Request without a transaction
    unless ($self->_current_active) {
        $self->error('Request without a transaction!');
        return $self;
    }

    # Normal request
    $self->_current_active->server_read(@_);

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_spin {
    my $self = shift;

    # Spin all
    $_->server_spin for @{$self->active};

    # Next reader?
    my $reader = $self->_current_active;
    if ($reader && $reader->req->is_finished) {
        $self->_next_active
          unless $reader->is_state(qw/handle_request handle_continue/);
    }

    # Next writer
    $self->_inactivate_first
      if $self->_first_active && $self->_first_active->is_finished;

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

# Current reader
sub server_tx { shift->_current_active }

sub server_written {
    my $self = shift;

    # Written
    $self->_first_active->server_written(@_);

    return $self;
}

# We are always in reading mode according to RFC, so writing has priority
sub _client_inherit_state {
    my $self = shift;

    # Inherit
    unless ($self->is_finished) {

        # State
        $self->state(
              $self->_all_written
            ? $self->_first_active->state
            : $self->_current_active->state
        );
        $self->state('read_response')
          if $self->is_state('done_with_leftovers');

        # Error
        $self->error('Transaction error: ' . $self->_first_active->error)
          if $self->_first_active->has_error;
    }

    return $self;
}

sub _current_active {
    my $self = shift;
    $self->active->[$self->_current];
}

sub _finish_inactive {
    my $self = shift;

    # Finish if possible
    my $inactive = $self->inactive->[-1];
    push @{$self->finished}, pop @{$self->inactive}
      if $inactive->is_done
          or $inactive->has_error;
}

sub _first_active { shift->active->[0] }

sub _inactivate_first {
    my $self = shift;

    # Keep alive?
    $self->keep_alive($self->_first_active->keep_alive);

    # Inactivate
    push @{$self->inactive}, shift @{$self->active};
    my $previous = $self->_current - 1;
    $previous = 0 if $previous < 0;
    $self->_current($previous);

    # Finish
    $self->_finish_inactive;

    # Found
    return 1 if @{$self->active};

    # Last
    return;
}

sub _is_writing {
    my ($self, $reader, $writer) = @_;

    my $writing = $self->SUPER::_is_writing;
    return $writing unless $self->safe_post;

    # If safe_post is on, don't write out a POST request until response from
    # previous request has been received
    # (This is even safer than rfc2616 (section 8.1.2.2), which suggests
    # waiting until the response status from the previous request has been
    # received)
    return
      if $writing && $reader != $writer && $writer->req->method eq 'POST';

    return $writing;
}

sub _next_active {
    my $self = shift;

    # Next
    $self->_current($self->_current + 1);

    # Found
    return 1 if $self->active->[$self->_current];

    # Last
    return;
}

# We are always in reading mode according to RFC, so writing has priority
sub _server_inherit_state {
    my $self = shift;

    # Keep alive?
    $self->keep_alive($self->_first_active->keep_alive)
      if $self->_first_active;

    # Handler first
    my $reader = $self->_current_active;
    if ($reader && $reader->state =~ /^handle_/) {
        $self->state($reader->state);
        return $self;
    }

    # Inherit state
    if ($self->_first_active) {
        $self->state($self->_first_active->state);
        $self->error('Transaction error: ' . $self->_first_active->error)
          if $self->_first_active->has_error;
    }
    else {
        $self->state('done');
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Transaction::Pipeline - Pipelined HTTP Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction::Pipeline;
    my $p = Mojo::Transaction::Pipeline->new;

=head1 DESCRIPTION

L<Mojo::Transaction::Pipeline> is a container for pipelined HTTP
transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction::Pipeline> inherits all attributes from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<active>

    my $active = $p->active;
    $p         = $p->active([Mojo::Transaction::Single->new]);

=head2 C<inactive>

    my $inactive = $p->inactive;
    $p           = $p->inactive([Mojo::Transaction::Single->new]);

=head2 C<finished>

    my $finished = $p->finished;
    $p           = $p->finished([Mojo::Transaction::Single->new]);

=head2 C<safe_post>

    my $safe_post = $p->safe_post;
    $p            = $p->safe_post(1);

=head1 METHODS

L<Mojo::Transaction::Pipeline> inherits all methods from L<Mojo::Transaction>
and implements the following new ones.

=head2 C<new>

    my $p = Mojo::Transaction::Pipeline->new;
    my $p = Mojo::Transaction::Pipeline->new($tx1);
    my $p = Mojo::Transaction::Pipeline->new($tx1, $tx2, $tx3);

=head2 C<client_connect>

    $p = $p->client_connect;

=head2 C<client_connected>

    $p = $p->client_connected;

=head2 C<client_get_chunk>

    my $chunk = $p->client_get_chunk;

=head2 C<client_info>

    my @info = $p->client_info;

=head2 C<client_is_writing>

    my $writing = $p->client_is_writing;

=head2 C<client_leftovers>

    my $leftovers = $p->client_leftovers;

=head2 C<client_read>

    $p = $p->client_read($chunk);

=head2 C<client_spin>

    $p = $p->client_spin;

=head2 C<client_written>

    $p = $p->client_written($length);

=head2 C<server_accept>

    $p = $p->server_accept($tx);

=head2 C<server_get_chunk>

    my $chunk = $p->server_get_chunk;

=head2 C<server_handled>

    $p = $p->server_handled;

=head2 C<server_is_writing>

    my $writing = $p->server_is_writing;

=head2 C<server_leftovers>

    my $leftovers = $p->server_leftovers;

=head2 C<server_read>

    $p = $p->server_read($chunk);

=head2 C<server_spin>

    $p = $p->server_spin;

=head2 C<server_tx>

    my $tx = $p->server_tx;

=head2 C<server_written>

    $p = $p->server_written($bytes);

=cut
