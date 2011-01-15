package Mojo::Transaction::WebSocket;
use Mojo::Base 'Mojo::Transaction';

# I'm not calling you a liar but...
# I can't think of a way to finish that sentence.
use Mojo::Transaction::HTTP;
use Mojo::Util qw/decode encode md5_bytes/;

has handshake => sub { Mojo::Transaction::HTTP->new };
has on_message => sub {
    sub { }
};

sub client_challenge {
    my $self = shift;

    # Request
    my $req = $self->req;

    # Headers
    my $headers = $self->req->headers;

    # WebSocket challenge
    my $solution = $self->_challenge($headers->sec_websocket_key1,
        $headers->sec_websocket_key2, $req->body);
    return unless $solution eq $self->res->body;
    return 1;
}

sub client_close { shift->server_close(@_) }

sub client_handshake {
    my $self = shift;

    # Request
    my $req = $self->req;

    # Headers
    my $headers = $req->headers;

    # Default headers
    $headers->upgrade('WebSocket')  unless $headers->upgrade;
    $headers->connection('Upgrade') unless $headers->connection;
    $headers->sec_websocket_protocol('mojo')
      unless $headers->sec_websocket_protocol;

    # Generate challenge
    $headers->sec_websocket_key1($self->_generate_key)
      unless $headers->sec_websocket_key1;
    $headers->sec_websocket_key2($self->_generate_key)
      unless $headers->sec_websocket_key2;
    $req->body(pack 'N*', int(rand 9999999) + 1, int(rand 9999999) + 1);

    return $self;
}

sub client_read  { shift->server_read(@_) }
sub client_write { shift->server_write(@_) }
sub connection   { shift->handshake->connection(@_) }

sub finish {
    my $self = shift;

    # Send closing handshake
    $self->_send_bytes("\xff");

    # Finish after writing
    return $self->{_finished} = 1;
}

sub is_websocket {1}

sub local_address  { shift->handshake->local_address }
sub local_port     { shift->handshake->local_port }
sub remote_address { shift->handshake->remote_address }
sub remote_port    { shift->handshake->remote_port }
sub req            { shift->handshake->req(@_) }
sub res            { shift->handshake->res(@_) }

sub resume {
    my $self = shift;

    # Resume
    $self->handshake->resume;

    return $self;
}

sub send_message {
    my ($self, $message) = @_;

    # Encode
    $message = '' unless defined $message;
    encode 'UTF-8', $message;

    # Send message with framing
    $self->_send_bytes("\x00$message\xff");
}

sub server_handshake {
    my $self = shift;

    # Request
    my $req = $self->req;

    # Response
    my $res = $self->res;

    # Request headers
    my $rqh = $req->headers;

    # Response headers
    my $rsh = $res->headers;

    # URL
    my $url = $req->url;

    # Handshake
    $res->code(101);
    $rsh->upgrade('WebSocket');
    $rsh->connection('Upgrade');
    my $scheme = $url->to_abs->scheme eq 'https' ? 'wss' : 'ws';
    my $location = $url->to_abs->scheme($scheme)->to_string;
    $rsh->sec_websocket_location($location);
    my $origin = $rqh->origin;
    $rsh->sec_websocket_origin($origin) if $origin;
    my $protocol = $rqh->sec_websocket_protocol;
    $rsh->sec_websocket_protocol($protocol) if $protocol;
    $res->body(
        $self->_challenge(
            $rqh->sec_websocket_key1, $rqh->sec_websocket_key2, $req->body
        )
    );

    return $self;
}

# Being eaten by crocodile is just like going to sleep... in a giant blender.
sub server_read {
    my ($self, $chunk) = @_;

    # Add chunk
    $self->{_read} = '' unless defined $self->{_read};
    $self->{_read} .= $chunk if defined $chunk;

    # Full frames
    while ((my $i = index $self->{_read}, "\xff") >= 0) {

        # Closing handshake
        return $self->finish if $i == 0;

        # Frame
        my $message = substr $self->{_read}, 0, $i + 1, '';

        # Remove framing
        $message =~ s/^[\x00]//;
        $message =~ s/[\xff]$//;

        # Callback
        decode 'UTF-8', $message if $message;
        $self->on_message->($self, $message);
    }

    # Resume
    $self->on_resume->($self);

    return $self;
}

sub server_write {
    my $self = shift;

    # Not writing anymore
    $self->{_write} = '' unless defined $self->{_write};
    unless (length $self->{_write}) {
        $self->{_state} = $self->{_finished} ? 'done' : 'read';
    }

    # Empty buffer
    my $write = $self->{_write};
    $self->{_write} = '';
    return $write;
}

sub _challenge {
    my ($self, $key1, $key2, $key3) = @_;

    # Shortcut
    return unless $key1 && $key2 && $key3;

    # Calculate solution for challenge
    my $c1 = pack 'N', join('', $key1 =~ /(\d)/g) / ($key1 =~ tr/\ //);
    my $c2 = pack 'N', join('', $key2 =~ /(\d)/g) / ($key2 =~ tr/\ //);
    return md5_bytes "$c1$c2$key3";
}

sub _generate_key {
    my $self = shift;

    # Number of spaces
    my $spaces = int(rand 12) + 1;

    # Number
    my $number = int(rand 99999) + 10;

    # Key
    my $key = $number * $spaces;

    # Insert whitespace
    while ($spaces--) {

        # Random position
        my $pos = int(rand(length($key) - 2)) + 1;

        # Insert a space at $pos position
        substr($key, $pos, 0) = ' ';
    }

    return $key;
}

sub _send_bytes {
    my ($self, $bytes) = @_;

    # Add to buffer
    $self->{_write} = '' unless defined $self->{_write};
    $self->{_write} .= $bytes if defined $bytes;

    # Writing
    $self->{_state} = 'write';

    # Resume
    $self->on_resume->($self);
}

1;
__END__

=head1 NAME

Mojo::Transaction::WebSocket - WebSocket Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction::WebSocket;

=head1 DESCRIPTION

L<Mojo::Transaction::WebSocket> is a container for WebSocket transactions as
described in C<The WebSocket protocol>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::Transaction::WebSocket> inherits all attributes from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<handshake>

    my $handshake = $ws->handshake;
    $ws           = $ws->handshake(Mojo::Transaction::HTTP->new);

The original handshake transaction.

=head2 C<on_message>

    my $cb = $ws->on_message;
    $ws    = $ws->on_message(sub {...});

The callback that receives decoded messages one by one.

    $ws->on_message(sub {
        my ($self, $message) = @_;
    });

=head1 METHODS

L<Mojo::Transaction::WebSocket> inherits all methods from
L<Mojo::Transaction> and implements the following new ones.

=head2 C<client_challenge>

    my $success = $ws->client_challenge;

Check WebSocket handshake challenge, only used by client.

=head2 C<client_close>

    $ws = $ws->client_close;

Connection got closed, only used by clients.

=head2 C<client_handshake>

    $ws = $ws->client_handshake;

WebSocket handshake, only used by clients.

=head2 C<client_read>

    $ws = $ws->client_read($data);

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

=head2 C<resume>

    $ws = $ws->resume;

Resume transaction.

=head2 C<send_message>

    $ws->send_message('Hi there!');

Send a message over the WebSocket, encoding and framing will be handled
transparently.

=head2 C<server_handshake>

    $ws = $ws->server_handshake;

WebSocket handshake, only used by servers.

=head2 C<server_read>

    $ws = $ws->server_read($data);

Read raw WebSocket data, only used by servers.

=head2 C<server_write>

    my $chunk = $ws->server_write;

Raw WebSocket data to write, only used by servers.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
