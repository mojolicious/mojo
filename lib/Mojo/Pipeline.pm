# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Pipeline;

use strict;
use warnings;

use base 'Mojo::Transaction';

__PACKAGE__->attr(safe_post => 0);

# No children have ever meddled with the Republican Party and lived to tell
# about it.
sub new {
    my $self = shift->SUPER::new();

    # Transactions
    $self->{_txs} = [@_];

    return $self;
}

sub client_info {
    my $self = shift;
    return $self->{_txs}->[0] ? $self->{_txs}->[0]->client_info(@_) : undef;
}

sub client_connect {
    my $self = shift;

    # Initialize
    $self->{_writer} = 0;
    $self->{_reader} = 0;

    # Connect all
    $_->client_connect for @{$self->{_txs}};
    $self->state('connect');

    return $self;
}

sub client_connected {
    my $self = shift;

    # All connected
    for my $tx (@{$self->{_txs}}) {

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
    return $self->_writer->client_get_chunk;
}

sub client_read {
    my ($self, $chunk) = @_;

    # Read with current reader
    $self->_reader->client_read($chunk);

    # Transaction finished
    while ($self->_reader->is_finished) {

        # All done
        unless ($self->_next_reader) {

            $self->{_reader} = $#{$self->{_txs}};
            $self->{_writer} = $#{$self->{_txs}};

            $self->done;
            return $self;
        }

        # Check for leftovers
        if (my $leftovers = $self->client_leftovers) {
            $self->_reader->client_read($leftovers);
        }
    }

    # Inherit state
    $self->_client_inherit_state;

    return $self;
}

sub client_leftovers {
    my $self = shift;

    # Previous reader
    my $previous = $self->{_reader} - 1;

    # No previous reader
    return unless $previous >= 0;

    # Leftovers
    return $self->{_txs}->[$previous]->client_leftovers;
}

sub client_spin {
    my $self = shift;

    # Spin all
    $_->client_spin for @{$self->{_txs}};

    # Transaction finished
    if (!$self->{_all_written} && $self->_writer->is_state('read_response')) {

        # All written
        $self->{_all_written} = 1 unless $self->_next_writer;
    }

    # Inherit state
    $self->_client_inherit_state;

    return $self;
}

sub client_written {
    my ($self, $length) = @_;

    # Written
    $self->_writer->client_written($length);

    return $self;
}

sub continued { shift->{_txs}->[-1]->continued }

sub is_writing {
    my $self = shift;

    my $writing = $self->SUPER::is_writing;
    return $writing unless $self->safe_post;

    # If safe_post is on, don't write out a POST request until response from
    # previous request has been received
    # (This is even safer than rfc2616 (section 8.1.2.2), which suggests
    # waiting until the response status from the previous request has been
    # received)
    return
      if $writing
          && $self->_reader != $self->_writer
          && $self->_writer->req->method eq 'POST';

    return $writing;
}

sub keep_alive {
    my $self = shift;
    return $self->{_txs}->[$self->{_writer}]
      ? $self->{_txs}->[$self->{_writer}]->keep_alive(@_)
      : $self->{_txs}->[-1]->keep_alive(@_);
}

sub req {
    my @req;
    push @req, $_->req for @{shift->{_txs}};
    return \@req;
}

sub res {
    my @res;
    push @res, $_->res for @{shift->{_txs}};
    return \@res;
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
    push @{$self->{_txs}}, $tx;

    # Initialize
    $self->{_writer} ||= 0;
    $self->{_reader} = $#{$self->{_txs}};

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_get_chunk {
    my $self = shift;

    # Get chunk from current writer
    return $self->_writer->server_get_chunk;
}

sub server_handled {
    my $self = shift;

    # Handled current reader
    $self->server_tx->server_handled;

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_leftovers {
    my $self = shift;

    # Last Transaction
    my $last = $self->{_txs}->[-1];

    # No leftovers
    return unless $last->req->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $last->req->leftovers;

    # Done
    $last->req->done;

    return $leftovers;
}

sub server_read {
    my $self = shift;

    # Request without a transaction
    unless ($self->_reader) {
        $self->error('Request without a transaction!');
        return $self;
    }

    # Normal request
    $self->_reader->server_read(@_);

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_spin {
    my $self = shift;

    # Spin all
    $_->server_spin for @{$self->{_txs}};

    # Next reader?
    if ($self->_reader && $self->_reader->req->is_finished) {
        $self->_next_reader
          unless $self->_reader->is_state(qw/handle_request handle_continue/);
    }

    # Next writer
    $self->_next_writer if $self->_writer && $self->_writer->is_finished;

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

# Current reader
sub server_tx { shift->_reader }

sub server_written {
    my $self = shift;

    # Written
    $self->_writer->server_written(@_);

    return $self;
}

# We are always in reading mode according to RFC, so writing has priority
sub _client_inherit_state {
    my $self = shift;

    # Inherit
    unless ($self->is_finished) {

        # State
        $self->state(
              $self->{_all_written}
            ? $self->_reader->state
            : $self->_writer->state
        );
        $self->state('read_response')
          if $self->is_state('done_with_leftovers');

        # Error
        $self->error('Transaction error.') if $self->_reader->has_error;
    }

    return $self;
}

sub _next_reader {
    my $self = shift;

    # Next
    $self->{_reader}++;

    # No reader
    return unless $self->{_txs}->[$self->{_reader}];

    # Found
    return 1;
}

sub _next_writer {
    my $self = shift;

    # Next
    $self->{_writer}++;

    # No writer
    return unless $self->{_txs}->[$self->{_writer}];

    # Found
    return 1;
}

sub _reader {
    my $self = shift;

    # Current reader
    return $self->{_txs}->[$self->{_reader}];
}

# We are always in reading mode according to RFC, so writing has priority
sub _server_inherit_state {
    my $self = shift;

    # Handler first
    if ($self->_reader && $self->_reader->state =~ /^handle_/) {
        $self->state($self->_reader->state);
        return $self;
    }

    # Inherit state
    $self->_writer
      ? $self->state($self->_writer->state)
      : $self->state('done');

    return $self;
}

sub _writer {
    my $self = shift;

    # Current writer
    return $self->{_txs}->[$self->{_writer}];
}

1;
__END__

=head1 NAME

Mojo::Pipeline - Pipelined HTTP Transaction Container

=head1 SYNOPSIS

    use Mojo::Pipeline;
    my $p = Mojo::Pipeline->new;

=head1 DESCRIPTION

L<Mojo::Pipeline> is a container for pipelined HTTP transactions.

=head1 ATTRIBUTES

L<Mojo::Pipeline> inherits all attributes from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<continued>

    my $continued = $p->continued;

=head2 C<keep_alive>

    my $keep_alive = $p->keep_alive;
    $p             = $p->keep_alive(1);

=head2 C<req>

    my $requests = $p->req;

=head2 C<res>

    my $responses = $p->res;

=head2 C<safe_post>

    my $safe_post = $p->safe_post;
    $p            = $p->safe_post(1);

=head1 METHODS

L<Mojo::Pipeline> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<new>

    my $p = Mojo::Pipeline->new;
    my $p = Mojo::Pipeline->new($tx1);
    my $p = Mojo::Pipeline->new($tx1, $tx2, $tx3);

=head2 C<client_connect>

    $p = $p->client_connect;

=head2 C<client_connected>

    $p = $p->client_connected;

=head2 C<client_get_chunk>

    my $chunk = $p->client_get_chunk;

=head2 C<client_info>

    my ($host, $port) = $p->client_info;

=head2 C<client_leftovers>

    my $leftovers = $p->client_leftovers;

=head2 C<client_read>

    $p = $p->client_read($chunk);

=head2 C<client_spin>

    $p = $p->client_spin;

=head2 C<client_written>

    $p = $p->client_written($length);

=head2 C<is_writing>

    my $writing = $p->is_writing;

=head2 C<server_accept>

    $p = $p->server_accept($tx);

=head2 C<server_get_chunk>

    my $chunk = $p->server_get_chunk;

=head2 C<server_handled>

    $p = $p->server_handled;

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
