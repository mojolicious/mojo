package Mojo::Transaction::WebSocket;
use Mojo::Base 'Mojo::Transaction';

# "I'm not calling you a liar but...
#  I can't think of a way to finish that sentence."
use Mojo::Transaction::HTTP;
use Mojo::Util qw/b64_encode decode encode sha1_bytes/;

use constant DEBUG => $ENV{MOJO_WEBSOCKET_DEBUG} || 0;

# Unique value from the spec
use constant GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

# Opcodes
use constant CONTINUATION => 0;
use constant TEXT         => 1;
use constant BINARY       => 2;
use constant CLOSE        => 8;
use constant PING         => 9;
use constant PONG         => 10;

# Core module since Perl 5.9.3
use constant SHA1 => eval 'use Digest::SHA (); 1';

has handshake => sub { Mojo::Transaction::HTTP->new };
has [qw/masked on_message/];
has max_websocket_size => sub { $ENV{MOJO_MAX_WEBSOCKET_SIZE} || 5242880 };

sub client_challenge {
  my $self = shift;

  # WebSocket challenge
  my $solution = $self->_challenge($self->req->headers->sec_websocket_key);
  return unless $solution eq $self->res->headers->sec_websocket_accept;
  return 1;
}

sub client_close { shift->server_close(@_) }

sub client_handshake {
  my $self = shift;

  # Default headers
  my $headers = $self->req->headers;
  $headers->upgrade('websocket')  unless $headers->upgrade;
  $headers->connection('Upgrade') unless $headers->connection;
  $headers->sec_websocket_protocol('mojo')
    unless $headers->sec_websocket_protocol;

  # Generate challenge
  my $key = pack 'N*', int(rand 9999999);
  b64_encode $key, '';
  $headers->sec_websocket_key($key) unless $headers->sec_websocket_key;

  return $self;
}

sub client_read  { shift->server_read(@_) }
sub client_write { shift->server_write(@_) }
sub connection   { shift->handshake->connection(@_) }

sub finish {
  my $self = shift;

  # Send closing handshake
  $self->_send_frame(CLOSE, '');

  # Finish after writing
  $self->{_finished} = 1;

  return $self;
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
  $self->handshake->resume;
  return $self;
}

sub send_message {
  my ($self, $message, $cb) = @_;

  # Drain callback
  $self->{_drain} = $cb if $cb;

  # Encode
  $message = '' unless defined $message;
  encode 'UTF-8', $message;

  $self->_send_frame(TEXT, $message);
}

sub server_handshake {
  my $self = shift;

  my $req         = $self->req;
  my $res         = $self->res;
  my $req_headers = $req->headers;
  my $res_headers = $res->headers;

  # Handshake
  $res->code(101);
  $res_headers->upgrade('websocket');
  $res_headers->connection('Upgrade');
  my $protocol = $req_headers->sec_websocket_protocol || '';
  $protocol =~ /^\s*([^\,]+)/;
  $res_headers->sec_websocket_protocol($1) if $1;
  $res_headers->sec_websocket_accept(
    $self->_challenge($req_headers->sec_websocket_key));

  return $self;
}

# "Being eaten by crocodile is just like going to sleep...
#  in a giant blender."
sub server_read {
  my ($self, $chunk) = @_;

  # Add chunk
  $self->{_read} = '' unless defined $self->{_read};
  $self->{_read} .= $chunk if defined $chunk;

  # Message buffer
  $self->{_message} = '' unless defined $self->{_message};

  # Full frames
  while (my $frame = $self->_parse_frame) {

    # Op
    my $op = $frame->[1] || CONTINUATION;

    # Ping
    if ($op == PING) {

      # Pong
      $self->_send_frame(PONG, $frame->[2]);
      next;
    }

    # Close
    elsif ($op == CLOSE) {
      $self->finish;
      next;
    }

    # Append
    $self->{_message} .= $frame->[2];

    # Continuation
    next unless $op;

    # Callback
    my $message = $self->{_message};
    $self->{_message} = '';
    decode 'UTF-8', $message if $message;
    return $self->finish unless my $cb = $self->on_message;
    $self->$cb($message);
  }

  # Check message size
  $self->finish if length $self->{_message} > $self->max_websocket_size;

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

    # Drain callback
    my $cb = delete $self->{_drain};
    $self->$cb if $cb;
  }

  # Empty buffer
  my $write = $self->{_write};
  $self->{_write} = '';
  return $write;
}

sub _build_frame {
  my ($self, $op, $payload) = @_;

  warn "BUILDING FRAME\n" if DEBUG;

  # Head
  my $frame = 0;
  vec($frame, 0, 8) = $op | 0b10000000;

  # Mask payload
  warn "PAYLOAD: $payload\n" if DEBUG;
  my $masked = $self->masked;
  if ($masked) {
    warn "MASKING PAYLOAD\n" if DEBUG;
    my $mask = pack 'N', int(rand 9999999);
    $payload = $mask . _xor_mask($payload, $mask);
  }

  # Length
  my $len = length $payload;

  # Empty prefix
  my $prefix = 0;

  # Small payload
  if ($len < 126) {
    vec($prefix, 0, 8) = $masked ? ($len | 0b10000000) : $len;
    $frame .= $prefix;
  }

  # Extended payload (16bit)
  elsif ($len < 65536) {
    vec($prefix, 0, 8) = $masked ? (126 | 0b10000000) : 126;
    $frame .= $prefix;
    $frame .= pack 'n', $len;
  }

  # Extended payload (64bit)
  else {
    vec($prefix, 0, 8) = $masked ? (127 | 0b10000000) : 127;
    $frame .= $prefix;
    $frame .= pack 'NN', $len >> 32, $len & 0xFFFFFFFF;
  }

  if (DEBUG) {
    warn 'HEAD: ' . unpack('B*', $frame) . "\n";
    warn "OPCODE: $op\n";
  }

  # Payload
  $frame .= $payload;

  return $frame;
}

sub _challenge {
  my ($self, $key) = @_;

  # No key or SHA1 support
  return '' unless $key && SHA1;

  # Checksum
  my $challenge = sha1_bytes($key . GUID);

  # Accept
  b64_encode $challenge, '';

  return $challenge;
}

sub _parse_frame {
  my $self = shift;

  warn "PARSING FRAME\n" if DEBUG;

  # Head
  my $buffer = $self->{_read};
  return unless length $buffer > 2;
  my $head = substr $buffer, 0, 2, '';
  warn 'HEAD: ' . unpack('B*', $head) . "\n" if DEBUG;

  # FIN
  my $fin = (vec($head, 0, 8) & 0b10000000) == 0b10000000 ? 1 : 0;
  warn "FIN: $fin\n" if DEBUG;

  # Opcode
  my $op = vec($head, 0, 8) & 0b00001111;
  warn "OPCODE: $op\n" if DEBUG;

  # Length
  my $len = vec($head, 1, 8) & 0b01111111;
  warn "LENGTH: $len\n" if DEBUG;

  # No payload
  if ($len == 0) { warn "NOTHING\n" if DEBUG }

  # Small payload
  elsif ($len < 126) { warn "SMALL\n" if DEBUG }

  # Extended payload (16bit)
  elsif ($len == 126) {
    return unless length $buffer > 2;
    my $ext = substr $buffer, 0, 2, '';
    $len = unpack 'n', $ext;
    warn "EXTENDED (16bit): $len\n" if DEBUG;
  }

  # Extended payload (64bit)
  elsif ($len == 127) {
    return unless length $buffer > 8;
    my $ext = substr $buffer, 0, 8, '';
    $len = unpack 'N', substr($ext, 4, 4);
    warn "EXTENDED (64bit): $len\n" if DEBUG;
  }

  # Payload
  return unless length $buffer >= $len;
  my $payload = $len ? substr($buffer, 0, $len, '') : '';

  # Unmask payload
  if (vec($head, 1, 8) & 0b10000000) {
    warn "UNMASKING PAYLOAD\n" if DEBUG;
    $payload = _xor_mask($payload, substr($payload, 0, 4, ''));
  }

  warn "PAYLOAD: $payload\n" if DEBUG;
  $self->{_read} = $buffer;

  return [$fin, $op, $payload];
}

sub _send_frame {
  my ($self, $op, $payload) = @_;

  # Build frame
  $self->{_write} = '' unless defined $self->{_write};
  $self->{_write} .= $self->_build_frame($op, $payload);

  # Writing
  $self->{_state} = 'write';

  # Resume
  $self->on_resume->($self);
}

sub _xor_mask {
  my ($input, $mask) = @_;

  # 512 byte mask
  $mask = $mask x 128;

  # Mask
  my $output = '';
  $output .= $_ ^ $mask while length($_ = substr($input, 0, 512, '')) == 512;
  $output .= $_ ^ substr($mask, 0, length, '');

  return $output;
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

=head2 C<masked>

  my $masked = $ws->masked;
  $ws        = $ws->masked(1);

Mask outgoing frames with XOR cipher and a random 32bit key.

=head2 C<max_websocket_size>

  my $size = $ws->max_websocket_size;
  $ws      = $ws->max_websocket_size(1024);

Maximum WebSocket message size in bytes, defaults to C<5242880>.

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

  $ws = $ws->finish;

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
  $ws->send_message('Hi there!', sub {...});

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
