# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Transaction::WebSocket;

use strict;
use warnings;

# I'm not calling you a liar but...
# I can't think of a way to finish that sentence.
use base 'Mojo::Transaction';

use Mojo::ByteStream 'b';
use Mojo::Transaction::HTTP;

__PACKAGE__->attr(
    [qw/finished receive_message/] => sub {
        sub { }
    }
);
__PACKAGE__->attr(handshake => sub { Mojo::Transaction::HTTP->new });

sub client_close { shift->server_close(@_) }
sub client_read  { shift->server_read(@_) }
sub client_write { shift->server_write(@_) }
sub connection   { shift->handshake->connection(@_) }

sub finish {
    my $self = shift;

    # Still writing
    return $self->{_finished} = 1 if $self->{_write} && $self->{_write}->size;

    # Finished
    $self->state('done');
}

sub is_websocket {1}

sub local_address  { shift->handshake->local_address }
sub local_port     { shift->handshake->local_port }
sub remote_address { shift->handshake->remote_address }
sub remote_port    { shift->handshake->remote_port }
sub req            { shift->handshake->req(@_) }
sub res            { shift->handshake->res(@_) }

sub send_message {
    my ($self, $message) = @_;

    # Encode
    $message = b($message)->encode('UTF-8')->to_string;

    # Add to buffer with framing
    my $write = $self->{_write} ||= Mojo::ByteStream->new;
    $write->add_chunk("\x00$message\xff");

    # Writing
    $self->state('write');
}

sub server_close {
    my $self = shift;

    # Connection finished
    $self->finished->($self);
}

# Being eaten by crocodile is just like going to sleep... in a giant blender.
sub server_read {
    my ($self, $chunk) = @_;

    # Add chunk
    my $buffer = $self->{_read} ||= Mojo::ByteStream->new;
    $buffer->add_chunk($chunk);

    # Full frames
    while ((my $i = $buffer->contains("\xff")) >= 0) {

        # Frame
        my $message = $buffer->remove($i + 1);

        # Remove framing
        $message =~ s/^[\x00]//;
        $message =~ s/[\xff]$//;

        # Callback
        $self->receive_message->(
            $self, b($message)->decode('UTF-8')->to_string
        );
    }
}

sub server_write {
    my $self = shift;

    # Not writing anymore
    my $write = $self->{_write} ||= Mojo::ByteStream->new;
    unless ($write->size) {
        $self->{_finished} ? $self->state('done') : $self->state('read');
    }

    # Empty buffer
    return $write->empty;
}

1;
__END__

=head1 NAME

Mojo::Transaction::WebSocket - WebSocket Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction::WebSocket;

=head1 DESCRIPTION

L<Mojo::Transaction::WebSocket> is a container and state machine for
WebSocket transactions as described in C<The Web Socket protocol>.

=head1 ATTRIBUTES

L<Mojo::Transaction::WebSocket> inherits all attributes from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<finished>

    my $cb = $ws->finished;
    $ws    = $ws->finsihed(sub {...});

Callback signaling that peer finished the connection.

    $ws->finsihed(sub {
        my $self = shift;
    });

=head2 C<handshake>

    my $handshake = $ws->handshake;
    $ws           = $ws->handshake(Mojo::Transaction::HTTP->new);

The original handshake transaction.

=head2 C<receive_message>

    my $cb = $ws->receive_message;
    $ws    = $ws->receive_message(sub {...});

The callback that receives decoded messages one by one.

    $ws->receive_message(sub {
        my ($self, $message) = @_;
    });

=head1 METHODS

L<Mojo::Transaction::WebSocket> inherits all methods from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<client_close>

    $ws->client_close;

Connection got closed.

=head2 C<client_read>

    $ws->client_read($data);

Read raw WebSocket data, only used by clients.

=head2 C<client_write>

    my $chunk = $ws->client_write;

Raw WebSocket data to write, only used by clients.

=head2 C<connection>

    my $connection = $ws->connection;

The connection this websocket is using.

=head2 C<finish>

    $ws->finish;

Finish the WebSocket connection gracefully.

=head2 C<is_websocket>

    my $is_websocket = $ws->is_websocket;

True.

=head2 C<local_address>

    my $local_address = $ws->local_address;

The local address of this WebSocket.

=head2 C<local_port>

    my $local_port = $ws->local_port;

The local port of this WebSocket.

=head2 C<remote_address>

    my $remote_address = $ws->remote_address;

The remote address of this WebSocket.

=head2 C<remote_port>

    my $remote_port = $ws->remote_port;

The remote port of this WebSocket.

=head2 C<req>

    my $req = $ws->req;

The original handshake request.

=head2 C<res>

    my $req = $ws->res;

The original handshake response.

=head2 C<send_message>

    $ws->send_message('Hi there!');

Send a message over the WebSocket, encoding and framing will be handled
transparently.

=head2 C<server_close>

    $ws->server_close;

Connection got closed.

=head2 C<server_read>

    $ws->server_read($data);

Read raw WebSocket data, only used by servers.

=head2 C<server_write>

    my $chunk = $ws->server_write;

Raw WebSocket data to write, only used by servers.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
