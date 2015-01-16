package Mojo::Transaction::WebSocket;
use Mojo::Base 'Mojo::Transaction';

use Compress::Raw::Zlib 'Z_SYNC_FLUSH';
use Config;
use Mojo::JSON qw(encode_json j);
use Mojo::Transaction::HTTP;
use Mojo::Util qw(b64_encode decode dumper encode sha1_bytes xor_encode);

use constant DEBUG => $ENV{MOJO_WEBSOCKET_DEBUG} || 0;

# Perl with support for quads
use constant MODERN =>
  (($Config{use64bitint} // '') eq 'define' || $Config{longsize} >= 8);

# Unique value from RFC 6455
use constant GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

# Opcodes
use constant {
  CONTINUATION => 0x0,
  TEXT         => 0x1,
  BINARY       => 0x2,
  CLOSE        => 0x8,
  PING         => 0x9,
  PONG         => 0xa
};

has [qw(compressed masked)];
has handshake => sub { Mojo::Transaction::HTTP->new };
has max_websocket_size => sub { $ENV{MOJO_MAX_WEBSOCKET_SIZE} || 262144 };

sub build_frame {
  my ($self, $fin, $rsv1, $rsv2, $rsv3, $op, $payload) = @_;
  warn "-- Building frame ($fin, $rsv1, $rsv2, $rsv3, $op)\n" if DEBUG;

  # Head
  my $head = $op + ($fin ? 128 : 0);
  $head |= 0b01000000 if $rsv1;
  $head |= 0b00100000 if $rsv2;
  $head |= 0b00010000 if $rsv3;
  my $frame = pack 'C', $head;

  # Small payload
  my $len    = length $payload;
  my $masked = $self->masked;
  if ($len < 126) {
    warn "-- Small payload ($len)\n@{[dumper $payload]}" if DEBUG;
    $frame .= pack 'C', $masked ? ($len | 128) : $len;
  }

  # Extended payload (16-bit)
  elsif ($len < 65536) {
    warn "-- Extended 16-bit payload ($len)\n@{[dumper $payload]}" if DEBUG;
    $frame .= pack 'Cn', $masked ? (126 | 128) : 126, $len;
  }

  # Extended payload (64-bit with 32-bit fallback)
  else {
    warn "-- Extended 64-bit payload ($len)\n@{[dumper $payload]}" if DEBUG;
    $frame .= pack 'C', $masked ? (127 | 128) : 127;
    $frame .= MODERN ? pack('Q>', $len) : pack('NN', 0, $len & 0xffffffff);
  }

  # Mask payload
  if ($masked) {
    my $mask = pack 'N', int(rand 9 x 7);
    $payload = $mask . xor_encode($payload, $mask x 128);
  }

  return $frame . $payload;
}

sub build_message {
  my ($self, $frame) = @_;

  # Text
  $frame = {text => encode('UTF-8', $frame)} if ref $frame ne 'HASH';

  # JSON
  $frame->{text} = encode_json($frame->{json}) if exists $frame->{json};

  # Raw text or binary
  if (exists $frame->{text}) { $frame = [1, 0, 0, 0, TEXT, $frame->{text}] }
  else { $frame = [1, 0, 0, 0, BINARY, $frame->{binary}] }

  # "permessage-deflate" extension
  return $self->build_frame(@$frame) unless $self->compressed;
  my $deflate = $self->{deflate} ||= Compress::Raw::Zlib::Deflate->new(
    AppendOutput => 1,
    MemLevel     => 8,
    WindowBits   => -15
  );
  $deflate->deflate($frame->[5], my $out);
  $deflate->flush($out, Z_SYNC_FLUSH);
  @$frame[1, 5] = (1, substr($out, 0, length($out) - 4));
  return $self->build_frame(@$frame);
}

sub client_challenge {
  my $self = shift;

  # "permessage-deflate" extension
  my $headers = $self->res->headers;
  $self->compressed(1)
    if ($headers->sec_websocket_extensions // '') =~ /permessage-deflate/;

  return _challenge($self->req->headers->sec_websocket_key) eq
    $headers->sec_websocket_accept;
}

sub client_handshake {
  my $self = shift;

  my $headers = $self->req->headers;
  $headers->upgrade('websocket')      unless $headers->upgrade;
  $headers->connection('Upgrade')     unless $headers->connection;
  $headers->sec_websocket_version(13) unless $headers->sec_websocket_version;

  # Generate 16 byte WebSocket challenge
  my $challenge = b64_encode sprintf('%16u', int(rand 9 x 16)), '';
  $headers->sec_websocket_key($challenge) unless $headers->sec_websocket_key;
}

sub client_read  { shift->server_read(@_) }
sub client_write { shift->server_write(@_) }

sub connection { shift->handshake->connection }

sub finish {
  my $self = shift;

  my $close = $self->{close} = [@_];
  my $payload = $close->[0] ? pack('n', $close->[0]) : '';
  $payload .= encode 'UTF-8', $close->[1] if defined $close->[1];
  $close->[0] //= 1005;
  $self->send([1, 0, 0, 0, CLOSE, $payload])->{finished} = 1;

  return $self;
}

sub is_websocket {1}

sub kept_alive    { shift->handshake->kept_alive }
sub local_address { shift->handshake->local_address }
sub local_port    { shift->handshake->local_port }

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(frame => sub { shift->_message(@_) });
  return $self;
}

sub parse_frame {
  my ($self, $buffer) = @_;

  # Head
  return undef unless length $$buffer >= 2;
  my ($first, $second) = unpack 'C*', substr($$buffer, 0, 2);

  # FIN
  my $fin = ($first & 0b10000000) == 0b10000000 ? 1 : 0;

  # RSV1-3
  my $rsv1 = ($first & 0b01000000) == 0b01000000 ? 1 : 0;
  my $rsv2 = ($first & 0b00100000) == 0b00100000 ? 1 : 0;
  my $rsv3 = ($first & 0b00010000) == 0b00010000 ? 1 : 0;

  # Opcode
  my $op = $first & 0b00001111;
  warn "-- Parsing frame ($fin, $rsv1, $rsv2, $rsv3, $op)\n" if DEBUG;

  # Small payload
  my ($hlen, $len) = (2, $second & 0b01111111);
  if ($len < 126) { warn "-- Small payload ($len)\n" if DEBUG }

  # Extended payload (16-bit)
  elsif ($len == 126) {
    return undef unless length $$buffer > 4;
    $hlen = 4;
    $len = unpack 'n', substr($$buffer, 2, 2);
    warn "-- Extended 16-bit payload ($len)\n" if DEBUG;
  }

  # Extended payload (64-bit with 32-bit fallback)
  elsif ($len == 127) {
    return undef unless length $$buffer > 10;
    $hlen = 10;
    my $ext = substr $$buffer, 2, 8;
    $len = MODERN ? unpack('Q>', $ext) : unpack('N', substr($ext, 4, 4));
    warn "-- Extended 64-bit payload ($len)\n" if DEBUG;
  }

  # Check message size
  $self->finish(1009) and return undef if $len > $self->max_websocket_size;

  # Check if whole packet has arrived
  $len += 4 if my $masked = $second & 0b10000000;
  return undef if length $$buffer < ($hlen + $len);
  substr $$buffer, 0, $hlen, '';

  # Payload
  my $payload = $len ? substr($$buffer, 0, $len, '') : '';
  $payload = xor_encode($payload, substr($payload, 0, 4, '') x 128) if $masked;
  warn dumper $payload if DEBUG;

  return [$fin, $rsv1, $rsv2, $rsv3, $op, $payload];
}

sub remote_address { shift->handshake->remote_address }
sub remote_port    { shift->handshake->remote_port }
sub req            { shift->handshake->req }
sub res            { shift->handshake->res }

sub resume {
  my $self = shift;
  $self->handshake->resume;
  return $self;
}

sub send {
  my ($self, $msg, $cb) = @_;

  $self->once(drain => $cb) if $cb;
  if   (ref $msg eq 'ARRAY') { $self->{write} .= $self->build_frame(@$msg) }
  else                       { $self->{write} .= $self->build_message($msg) }
  $self->{state} = 'write';

  return $self->emit('resume');
}

sub server_close {
  my $self = shift;
  $self->{state} = 'finished';
  return $self->emit(finish => $self->{close} ? (@{$self->{close}}) : 1006);
}

sub server_handshake {
  my $self = shift;

  my $res_headers = $self->res->headers;
  $res_headers->upgrade('websocket')->connection('Upgrade');
  my $req_headers = $self->req->headers;
  ($req_headers->sec_websocket_protocol // '') =~ /^\s*([^,]+)/
    and $res_headers->sec_websocket_protocol($1);
  $res_headers->sec_websocket_accept(
    _challenge($req_headers->sec_websocket_key));
}

sub server_read {
  my ($self, $chunk) = @_;

  $self->{read} .= $chunk // '';
  while (my $frame = $self->parse_frame(\$self->{read})) {
    $self->emit(frame => $frame);
  }

  $self->emit('resume');
}

sub server_write {
  my $self = shift;

  unless (length($self->{write} // '')) {
    $self->{state} = $self->{finished} ? 'finished' : 'read';
    $self->emit('drain');
  }

  return delete $self->{write} // '';
}

sub with_compression {
  my $self = shift;

  # "permessage-deflate" extension
  $self->compressed(1)
    and $self->res->headers->sec_websocket_extensions('permessage-deflate')
    if ($self->req->headers->sec_websocket_extensions // '')
    =~ /permessage-deflate/;
}

sub _challenge { b64_encode(sha1_bytes(($_[0] || '') . GUID), '') }

sub _message {
  my ($self, $frame) = @_;

  # Assume continuation
  my $op = $frame->[4] || CONTINUATION;

  # Ping/Pong
  return $self->send([1, 0, 0, 0, PONG, $frame->[5]]) if $op == PING;
  return if $op == PONG;

  # Close
  if ($op == CLOSE) {
    return $self->finish unless length $frame->[5] >= 2;
    return $self->finish(unpack('n', substr($frame->[5], 0, 2, '')),
      decode('UTF-8', $frame->[5]));
  }

  # Append chunk and check message size
  $self->{op} = $op unless exists $self->{op};
  $self->{message} .= $frame->[5];
  my $max = $self->max_websocket_size;
  return $self->finish(1009) if length $self->{message} > $max;

  # No FIN bit (Continuation)
  return unless $frame->[0];

  # "permessage-deflate" extension (handshake and RSV1)
  my $msg = delete $self->{message};
  if ($self->compressed && $frame->[1]) {
    my $inflate = $self->{inflate} ||= Compress::Raw::Zlib::Inflate->new(
      Bufsize     => $max,
      LimitOutput => 1,
      WindowBits  => -15
    );
    $inflate->inflate(($msg .= "\x00\x00\xff\xff"), my $out);
    return $self->finish(1009) if length $msg;
    $msg = $out;
  }

  $self->emit(json => j($msg)) if $self->has_subscribers('json');
  $op = delete $self->{op};
  $self->emit($op == TEXT ? 'text' : 'binary' => $msg);
  $self->emit(message => $op == TEXT ? decode('UTF-8', $msg) : $msg)
    if $self->has_subscribers('message');
}

1;

=encoding utf8

=head1 NAME

Mojo::Transaction::WebSocket - WebSocket transaction

=head1 SYNOPSIS

  use Mojo::Transaction::WebSocket;

  # Send and receive WebSocket messages
  my $ws = Mojo::Transaction::WebSocket->new;
  $ws->send('Hello World!');
  $ws->on(message => sub {
    my ($ws, $msg) = @_;
    say "Message: $msg";
  });
  $ws->on(finish => sub {
    my ($ws, $code, $reason) = @_;
    say "WebSocket closed with status $code.";
  });

=head1 DESCRIPTION

L<Mojo::Transaction::WebSocket> is a container for WebSocket transactions
based on L<RFC 6455|http://tools.ietf.org/html/rfc6455>. Note that 64-bit
frames require a Perl with support for quads or they are limited to 32-bit.

=head1 EVENTS

L<Mojo::Transaction::WebSocket> inherits all events from L<Mojo::Transaction>
and can emit the following new ones.

=head2 binary

  $ws->on(binary => sub {
    my ($ws, $bytes) = @_;
    ...
  });

Emitted when a complete WebSocket binary message has been received.

  $ws->on(binary => sub {
    my ($ws, $bytes) = @_;
    say "Binary: $bytes";
  });

=head2 drain

  $ws->on(drain => sub {
    my $ws = shift;
    ...
  });

Emitted once all data has been sent.

  $ws->on(drain => sub {
    my $ws = shift;
    $ws->send(time);
  });

=head2 finish

  $ws->on(finish => sub {
    my ($ws, $code, $reason) = @_;
    ...
  });

Emitted when transaction is finished.

=head2 frame

  $ws->on(frame => sub {
    my ($ws, $frame) = @_;
    ...
  });

Emitted when a WebSocket frame has been received.

  $ws->unsubscribe('frame');
  $ws->on(frame => sub {
    my ($ws, $frame) = @_;
    say "FIN: $frame->[0]";
    say "RSV1: $frame->[1]";
    say "RSV2: $frame->[2]";
    say "RSV3: $frame->[3]";
    say "Opcode: $frame->[4]";
    say "Payload: $frame->[5]";
  });

=head2 json

  $ws->on(json => sub {
    my ($ws, $json) = @_;
    ...
  });

Emitted when a complete WebSocket message has been received, all text and
binary messages will be automatically JSON decoded. Note that this event only
gets emitted when it has at least one subscriber.

  $ws->on(json => sub {
    my ($ws, $hash) = @_;
    say "Message: $hash->{msg}";
  });

=head2 message

  $ws->on(message => sub {
    my ($ws, $msg) = @_;
    ...
  });

Emitted when a complete WebSocket message has been received, text messages
will be automatically decoded. Note that this event only gets emitted when it
has at least one subscriber.

  $ws->on(message => sub {
    my ($ws, $msg) = @_;
    say "Message: $msg";
  });

=head2 text

  $ws->on(text => sub {
    my ($ws, $bytes) = @_;
    ...
  });

Emitted when a complete WebSocket text message has been received.

  $ws->on(text => sub {
    my ($ws, $bytes) = @_;
    say "Text: $bytes";
  });

=head1 ATTRIBUTES

L<Mojo::Transaction::WebSocket> inherits all attributes from
L<Mojo::Transaction> and implements the following new ones.

=head2 compressed

  my $bool = $ws->compressed;
  $ws      = $ws->compressed($bool);

Compress messages with C<permessage-deflate> extension.

=head2 handshake

  my $handshake = $ws->handshake;
  $ws           = $ws->handshake(Mojo::Transaction::HTTP->new);

The original handshake transaction, defaults to a L<Mojo::Transaction::HTTP>
object.

=head2 masked

  my $bool = $ws->masked;
  $ws      = $ws->masked($bool);

Mask outgoing frames with XOR cipher and a random 32-bit key.

=head2 max_websocket_size

  my $size = $ws->max_websocket_size;
  $ws      = $ws->max_websocket_size(1024);

Maximum WebSocket message size in bytes, defaults to the value of the
C<MOJO_MAX_WEBSOCKET_SIZE> environment variable or C<262144> (256KB).

=head1 METHODS

L<Mojo::Transaction::WebSocket> inherits all methods from
L<Mojo::Transaction> and implements the following new ones.

=head2 build_frame

  my $bytes = $ws->build_frame($fin, $rsv1, $rsv2, $rsv3, $op, $payload);

Build WebSocket frame.

  # Binary frame with FIN bit and payload
  say $ws->build_frame(1, 0, 0, 0, 2, 'Hello World!');

  # Text frame with payload but without FIN bit
  say $ws->build_frame(0, 0, 0, 0, 1, 'Hello ');

  # Continuation frame with FIN bit and payload
  say $ws->build_frame(1, 0, 0, 0, 0, 'World!');

  # Close frame with FIN bit and without payload
  say $ws->build_frame(1, 0, 0, 0, 8, '');

  # Ping frame with FIN bit and payload
  say $ws->build_frame(1, 0, 0, 0, 9, 'Test 123');

  # Pong frame with FIN bit and payload
  say $ws->build_frame(1, 0, 0, 0, 10, 'Test 123');

=head2 build_message

  my $bytes = $ws->build_message({binary => $bytes});
  my $bytes = $ws->build_message({text   => $bytes});
  my $bytes = $ws->build_message({json   => {test => [1, 2, 3]}});
  my $bytes = $ws->build_message($chars);

Build WebSocket message.

=head2 client_challenge

  my $bool = $ws->client_challenge;

Check WebSocket handshake challenge client-side, used to implement user
agents.

=head2 client_handshake

  $ws->client_handshake;

Perform WebSocket handshake client-side, used to implement user agents.

=head2 client_read

  $ws->client_read($data);

Read data client-side, used to implement user agents.

=head2 client_write

  my $bytes = $ws->client_write;

Write data client-side, used to implement user agents.

=head2 connection

  my $connection = $ws->connection;

Connection identifier or socket.

=head2 finish

  $ws = $ws->finish;
  $ws = $ws->finish(1000);
  $ws = $ws->finish(1003 => 'Cannot accept data!');

Close WebSocket connection gracefully.

=head2 is_websocket

  my $true = $ws->is_websocket;

True.

=head2 kept_alive

  my $kept_alive = $ws->kept_alive;

Connection has been kept alive.

=head2 local_address

  my $address = $ws->local_address;

Local interface address.

=head2 local_port

  my $port = $ws->local_port;

Local interface port.

=head2 new

  my $ws = Mojo::Transaction::WebSocket->new;

Construct a new L<Mojo::Transaction::WebSocket> object and subscribe to
L</"frame"> event with default message parser, which also handles C<PING> and
C<CLOSE> frames automatically.

=head2 parse_frame

  my $frame = $ws->parse_frame(\$bytes);

Parse WebSocket frame.

  # Parse single frame and remove it from buffer
  my $frame = $ws->parse_frame(\$buffer);
  say "FIN: $frame->[0]";
  say "RSV1: $frame->[1]";
  say "RSV2: $frame->[2]";
  say "RSV3: $frame->[3]";
  say "Opcode: $frame->[4]";
  say "Payload: $frame->[5]";

=head2 remote_address

  my $address = $ws->remote_address;

Remote interface address.

=head2 remote_port

  my $port = $ws->remote_port;

Remote interface port.

=head2 req

  my $req = $ws->req;

Handshake request, usually a L<Mojo::Message::Request> object.

=head2 res

  my $res = $ws->res;

Handshake response, usually a L<Mojo::Message::Response> object.

=head2 resume

  $ws = $ws->resume;

Resume L</"handshake"> transaction.

=head2 send

  $ws = $ws->send({binary => $bytes});
  $ws = $ws->send({text   => $bytes});
  $ws = $ws->send({json   => {test => [1, 2, 3]}});
  $ws = $ws->send([$fin, $rsv1, $rsv2, $rsv3, $op, $payload]);
  $ws = $ws->send($chars);
  $ws = $ws->send($chars => sub {...});

Send message or frame non-blocking via WebSocket, the optional drain callback
will be invoked once all data has been written.

  # Send "Ping" frame
  $ws->send([1, 0, 0, 0, 9, 'Hello World!']);

=head2 server_close

  $ws->server_close;

Transaction closed server-side, used to implement web servers.

=head2 server_handshake

  $ws->server_handshake;

Perform WebSocket handshake server-side, used to implement web servers.

=head2 server_read

  $ws->server_read($data);

Read data server-side, used to implement web servers.

=head2 server_write

  my $bytes = $ws->server_write;

Write data server-side, used to implement web servers.

=head2 with_compression

  $ws->with_compression;

Negotiate C<permessage-deflate> extension for this WebSocket connection.

=head1 DEBUGGING

You can set the C<MOJO_WEBSOCKET_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_WEBSOCKET_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
