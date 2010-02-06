# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Transaction;

use strict;
use warnings;

use base 'Mojo::Stateful';

use Carp 'croak';

__PACKAGE__->attr([qw/connection kept_alive/]);
__PACKAGE__->attr([qw/local_address local_port remote_port/]);
__PACKAGE__->attr(continue_timeout => 5);
__PACKAGE__->attr(keep_alive       => 0);

__PACKAGE__->attr('_real_state');

# Please don't eat me! I have a wife and kids. Eat them!
sub client_read  { croak 'Method "client_read" not implemented by subclass' }
sub client_write { croak 'Method "client_write" not implemented by subclass' }

sub is_paused { shift->is_state('paused') }

sub is_websocket {0}

sub is_writing {
    shift->is_state(
        qw/start write write_start_line write_headers write_body/);
}

sub pause {
    my $self = shift;

    # Already paused
    return $self if $self->_real_state;

    # Save state
    $self->_real_state($self->state);

    # Pause
    $self->state('paused');

    return $self;
}

sub remote_address {
    my ($self, $address) = @_;

    # Set
    if ($address) {
        $self->{remote_address} = $address;

        # Activate reverse proxy support for local requests
        $ENV{MOJO_REVERSE_PROXY} ||= 1 if $address eq '127.0.0.1';

        return $self;
    }

    # Get
    return $self->{remote_address};
}

sub resume {
    my $self = shift;

    # Not paused
    return unless my $state = $self->_real_state;

    # Resume
    $self->_real_state(undef);
    $self->state($state);

    return $self;
}

sub server_read { croak 'Method "server_read" not implemented by subclass' }

sub server_write { croak 'Method "server_write" not implemented by subclass' }

1;
__END__

=head1 NAME

Mojo::Transaction - Transaction Base Class

=head1 SYNOPSIS

    use base 'Mojo::Transaction';

=head1 DESCRIPTION

L<Mojo::Transaction> is an abstract base class for transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction> inherits all attributes from L<Mojo::Stateful> and
implements the following new ones.

=head2 C<connection>

    my $connection = $tx->connection;
    $tx            = $tx->connection($connection);

=head2 C<continue_timeout>

    my $continue_timeout = $tx->continue_timeout;
    $tx                  = $tx->continue_timeout(3);

=head2 C<keep_alive>

    my $keep_alive = $tx->keep_alive;
    $tx            = $tx->keep_alive(1);

=head2 C<kept_alive>

    my $kept_alive = $tx->kept_alive;
    $tx            = $tx->kept_alive(1);

=head2 C<local_address>

    my $local_address = $tx->local_address;
    $tx               = $tx->local_address($address);

=head2 C<local_port>

    my $local_port = $tx->local_port;
    $tx            = $tx->local_port($port);

=head2 C<remote_address>

    my $remote_address = $tx->remote_address;
    $tx                = $tx->remote_address($address);

=head2 C<remote_port>

    my $remote_port = $tx->remote_port;
    $tx             = $tx->remote_port($port);

=head1 METHODS

L<Mojo::Transaction> inherits all methods from L<Mojo::Stateful> and
implements the following new ones.

=head2 C<client_read>

    $tx = $tx->client_read($chunk);

=head2 C<client_write>

    my $chunk = $tx->client_write;

=head2 C<is_paused>

    my $paused = $tx->is_paused;

=head2 C<is_websocket>

    my $is_websocket = $tx->is_websocket;

=head2 C<is_writing>

    my $writing = $tx->is_writing;

=head2 C<pause>

    $tx = $tx->pause;

=head2 C<resume>

    $tx = $tx->resume;

=head2 C<server_read>

    $tx = $tx->server_read($chunk);

=head2 C<server_write>

    my $chunk = $tx->server_write;

=cut
