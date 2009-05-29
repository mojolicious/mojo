# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Pipeline;

use strict;
use warnings;

use base 'Mojo::Transaction';

use Mojo::Transaction;

__PACKAGE__->attr(txs => (chained => 1, default => sub { [] }));

# No children have ever meddled with the Republican Party and lived to tell
# about it.
sub new {
    my $self = shift->SUPER::new();
    $self->add_tx(@_);
    return $self;
}

sub add_tx {
    my $self = shift;
    push @{$self->txs}, @_;
    return $self;
}

sub client_info { shift->_proxy('client_info', @_) }

sub client_connect {
    my $self = shift;

    # Initialize
    $self->{_writer} = 0;
    $self->{_reader} = 0;

    # Connect all
    $_->client_connect for @{$self->txs};
    $self->state('connect');

    return $self;
}

sub client_connected {
    my $self = shift;

    # All connected
    $_->client_connected for @{$self->txs};
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
    if ($self->_reader->is_finished) {

        # All done
        unless ($self->_next_reader) {

            $self->{_reader} = $#{$self->txs};
            $self->{_writer} = $#{$self->txs};

            $self->done;
            return $self;
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
    return undef unless $previous >= 0;

    # Leftovers
    return $self->txs->[$previous]->client_leftovers;
}

sub client_spin {
    my $self = shift;

    # Spin all
    $_->client_spin for @{$self->txs};

    # Transaction finished
    if (!$self->{_all_written} && $self->_writer->is_state('read_response')) {

        # All written
        $self->{_all_written} = 1 unless $self->_next_writer;
    }

    # Take care of leftovers
    if (my $leftovers = $self->client_leftovers) {
        $self->_reader->client_read($leftovers);
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

sub connection       { shift->_proxy('connection',       @_) }
sub continue_timeout { shift->_proxy('continue_timeout', @_) }
sub continued        { shift->_proxy('continued',        @_) }
sub keep_alive       { shift->_proxy('keep_alive',       @_) }
sub kept_alive       { shift->_proxy('kept_alive',       @_) }
sub local_address    { shift->_proxy('local_address',    @_) }
sub local_port       { shift->_proxy('local_port',       @_) }
sub remote_address   { shift->_proxy('remote_address',   @_) }
sub remote_port      { shift->_proxy('remote_port',      @_) }

sub server_accept {
    my ($self, $tx) = @_;

    # Accept
    $tx->server_accept;
    $self->add_tx($tx);

    # Initialize
    $self->{_writer} ||= 0;
    $self->{_reader} = $#{$self->txs};

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

    # Current reader
    my $reader = $self->server_tx;

    # No leftovers
    return undef unless $reader->req->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $reader->req->leftovers;

    # Done
    $reader->req->done;

    return $leftovers;
}

sub server_read {
    my $self = shift;

    # Request without a transaction
    unless ($self->_reader) { $self->txs->[-1]->server_read(@_) }

    # Normal request
    else { $self->_reader->server_read(@_) }

    # Inherit state
    $self->_server_inherit_state;

    return $self;
}

sub server_spin {
    my $self = shift;

    # Spin all
    $_->server_spin for @{$self->txs};

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

sub server_tx {
    my $self = shift;

    # Current reader
    return $self->{_reader} > $#{$self->txs}
      ? $self->txs->[-1]
      : $self->_reader;
}

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
    return 0 unless $self->txs->[$self->{_reader}];

    # Found
    return 1;
}

sub _next_writer {
    my $self = shift;

    # Next
    $self->{_writer}++;

    # No writer
    return 0 unless $self->txs->[$self->{_writer}];

    # Found
    return 1;
}

sub _proxy {
    my $self   = shift;
    my $method = shift;

    # Set
    if (@_) {

        # Proxy
        $_->$method(@_) for @{$self->txs};

        return $self;
    }

    # Get
    return undef unless $self->txs->[0];
    return wantarray
      ? ($self->txs->[0]->$method)
      : scalar $self->txs->[0]->$method;
}

sub _reader {
    my $self = shift;

    # Current reader
    return $self->txs->[$self->{_reader}];
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
    return $self->txs->[$self->{_writer}];
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

=head2 C<connection>

    my $connection = $p->connection;
    $p             = $p->connection($connection);

=head2 C<continue_timeout>

    my $continue_timeout = $p->continue_timeout;
    $p                   = $p->continue_timeout(3);

=head2 C<continued>

    my $continued = $p->continued;
    $p            = $p->continued(1);

=head2 C<keep_alive>

    my $keep_alive = $p->keep_alive;
    $p             = $p->keep_alive(1);

=head2 C<kept_alive>

    my $kept_alive = $p->kept_alive;
    $p             = $p->kept_alive(1);

=head2 C<local_address>

    my $local_address = $p->local_address;
    $p                = $p->local_address($address);

=head2 C<local_port>

    my $local_port = $p->local_port;
    $p             = $p->local_port($port);

=head2 C<remote_address>

    my $remote_address = $p->remote_address;
    $p                 = $p->remote_address($address);

=head2 C<remote_port>

    my $remote_port = $p->remote_port;
    $p              = $p->remote_port($port);

=head2 C<txs>

    my $txs = $p->txs;
    $p      = $p->txs([Mojo::Transaction->new]);

=head1 METHODS

L<Mojo::Pipeline> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<new>

    my $p = Mojo::Pipeline->new;
    my $p = Mojo::Pipeline->new($tx);

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
