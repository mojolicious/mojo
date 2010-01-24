# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Transaction::WebSocket;

use strict;
use warnings;

# I'm not calling you a liar but...
# I can't think of a way to finish that sentence.
use base 'Mojo::Transaction';

use Mojo::Buffer;
use Mojo::ByteStream 'b';
use Mojo::Message::Request;

__PACKAGE__->attr([qw/read_buffer write_buffer/] => sub { Mojo::Buffer->new }
);
__PACKAGE__->attr(
    receive_message => sub {
        sub { }
    }
);
__PACKAGE__->attr(req => sub { Mojo::Message::Request->new });

__PACKAGE__->attr(_finished => 0);

sub finish {
    my $self = shift;

    # Still writing
    return $self->_finished(1) if $self->write_buffer->size;

    # Finished
    $self->state('done');
}

sub send_message {
    my ($self, $message) = @_;

    # Encode
    $message = b($message)->encode('UTF-8')->to_string;

    # Add to buffer with framing
    $self->write_buffer->add_chunk("\x00$message\xff");

    # Writing
    $self->state('write');
}

sub server_get_chunk {
    my $self = shift;

    # Not writing anymore
    unless ($self->write_buffer->size) {
        $self->_finished ? $self->state('done') : $self->state('read');
    }

    # Empty buffer
    return $self->write_buffer->empty;
}

# Being eaten by crocodile is just like going to sleep... in a giant blender.
sub server_read {
    my ($self, $chunk) = @_;

    # Add chunk
    my $buffer = $self->read_buffer;
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

1;
__END__

=head1 NAME

Mojo::Transaction::WebSocket - WebSocket Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction::WebSocket;

=head1 DESCRIPTION

L<Mojo::Transaction::WebSocket> is a container for WebSocket transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction::WebSocket> inherits all attributes from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<read_buffer>

    my $buffer = $ws->read_buffer;
    $ws        = $ws->read_buffer(Mojo::Buffer->new);

Buffer for incoming data.

=head2 C<receive_message>

    my $cb = $ws->receive_message;
    $ws    = $ws->receive_message(sub {...});

The callback that receives decoded messages one by one.

    $ws->receive_message(sub {
        my ($self, $message) = @_;
    });

=head2 C<req>

    my $req = $ws->req;
    $ws     = $ws->req(Mojo::Message::Request->new);

The original handshake request.

=head2 C<write_buffer>

    my $buffer = $ws->write_buffer;
    $ws        = $ws->write_buffer(Mojo::Buffer->new);

Buffer for outgoing data.

=head1 METHODS

L<Mojo::Transaction::WebSocket> inherits all methods from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<finish>

    $ws->finish;

Finish the WebSocket connection gracefully.

=head2 C<send_message>

    $ws->send_message('Hi there!');

Send a message over the WebSocket, encoding and framing will be handled
transparently.

=head2 C<server_get_chunk>

    my $chunk = $ws->server_get_chunk;

Raw WebSocket data to write, only used by servers.

=head2 C<server_read>

    $ws->server_read($data);

Read raw WebSocket data, only used by servers.

=cut
