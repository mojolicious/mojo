package Mojo::Transaction::WebSocket;
use Mojo::Base 'Mojo::Transaction';

use Compress::Raw::Zlib 'Z_SYNC_FLUSH';
use List::Util 'first';
use Mojo::JSON qw(encode_json j);
use Mojo::Util qw(decode encode trim);
use Mojo::WebSocket
  qw(WS_BINARY WS_CLOSE WS_CONTINUATION WS_PING WS_PONG WS_TEXT);

has [qw(compressed established handshake masked)];
has max_websocket_size => sub { $ENV{MOJO_MAX_WEBSOCKET_SIZE} || 262144 };

sub build_message {
  my ($self, $frame) = @_;

  # Text
  $frame = {text => encode('UTF-8', $frame)} if ref $frame ne 'HASH';

  # JSON
  $frame->{text} = encode_json($frame->{json}) if exists $frame->{json};

  # Raw text or binary
  if (exists $frame->{text}) { $frame = [1, 0, 0, 0, WS_TEXT, $frame->{text}] }
  else { $frame = [1, 0, 0, 0, WS_BINARY, $frame->{binary}] }

  # "permessage-deflate" extension
  return $frame unless $self->compressed;
  my $deflate = $self->{deflate} ||= Compress::Raw::Zlib::Deflate->new(
    AppendOutput => 1,
    MemLevel     => 8,
    WindowBits   => -15
  );
  $deflate->deflate($frame->[5], my $out);
  $deflate->flush($out, Z_SYNC_FLUSH);
  @$frame[1, 5] = (1, substr($out, 0, length($out) - 4));

  return $frame;
}

sub client_read  { shift->server_read(@_) }
sub client_write { shift->server_write(@_) }

sub closed {
  my $self = shift->completed;
  return $self->emit(finish => $self->{close} ? (@{$self->{close}}) : 1006);
}

sub connection { shift->handshake->connection }

sub finish {
  my $self = shift;

  my $close = $self->{close} = [@_];
  my $payload = $close->[0] ? pack('n', $close->[0]) : '';
  $payload .= encode 'UTF-8', $close->[1] if defined $close->[1];
  $close->[0] //= 1005;
  $self->send([1, 0, 0, 0, WS_CLOSE, $payload])->{closing} = 1;

  return $self;
}

sub is_websocket {1}

sub kept_alive    { shift->handshake->kept_alive }
sub local_address { shift->handshake->local_address }
sub local_port    { shift->handshake->local_port }

sub parse_message {
  my ($self, $frame) = @_;

  $self->emit(frame => $frame);

  # Ping/Pong
  my $op = $frame->[4];
  return $self->send([1, 0, 0, 0, WS_PONG, $frame->[5]]) if $op == WS_PING;
  return if $op == WS_PONG;

  # Close
  if ($op == WS_CLOSE) {
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
  $self->emit($op == WS_TEXT ? 'text' : 'binary' => $msg);
  $self->emit(message => $op == WS_TEXT ? decode 'UTF-8', $msg : $msg)
    if $self->has_subscribers('message');
}

sub protocol { shift->res->headers->sec_websocket_protocol }

sub remote_address { shift->handshake->remote_address }
sub remote_port    { shift->handshake->remote_port }
sub req            { shift->handshake->req }
sub res            { shift->handshake->res }

sub resume { $_[0]->handshake->resume and return $_[0] }

sub send {
  my ($self, $msg, $cb) = @_;
  $self->once(drain => $cb) if $cb;
  $msg = $self->build_message($msg) unless ref $msg eq 'ARRAY';
  $self->{write} .= Mojo::WebSocket::build_frame($self->masked, @$msg);
  return $self->emit('resume');
}

sub server_read {
  my ($self, $chunk) = @_;

  $self->{read} .= $chunk;
  my $max = $self->max_websocket_size;
  while (my $frame = Mojo::WebSocket::parse_frame(\$self->{read}, $max)) {
    $self->finish(1009) and last unless ref $frame;
    $self->parse_message($frame);
  }

  $self->emit('resume');
}

sub server_write {
  my $self = shift;
  $self->emit('drain') unless length($self->{write} //= '');
  $self->completed if !length $self->{write} && $self->{closing};
  return delete $self->{write};
}

sub with_compression {
  my $self = shift;

  # "permessage-deflate" extension
  $self->compressed(1)
    and $self->res->headers->sec_websocket_extensions('permessage-deflate')
    if ($self->req->headers->sec_websocket_extensions // '')
    =~ /permessage-deflate/;
}

sub with_protocols {
  my $self = shift;

  my %protos = map { trim($_) => 1 } split ',',
    $self->req->headers->sec_websocket_protocol // '';
  return undef unless defined(my $proto = first { $protos{$_} } @_);

  $self->res->headers->sec_websocket_protocol($proto);
  return $proto;
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

L<Mojo::Transaction::WebSocket> is a container for WebSocket transactions, based
on L<RFC 6455|http://tools.ietf.org/html/rfc6455> and
L<RFC 7692|http://tools.ietf.org/html/rfc7692>.

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

Emitted when the WebSocket connection has been closed.

=head2 frame

  $ws->on(frame => sub {
    my ($ws, $frame) = @_;
    ...
  });

Emitted when a WebSocket frame has been received.

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

Emitted when a complete WebSocket message has been received, text messages will
be automatically decoded. Note that this event only gets emitted when it has at
least one subscriber.

  $ws->on(message => sub {
    my ($ws, $msg) = @_;
    say "Message: $msg";
  });

=head2 resume

  $tx->on(resume => sub {
    my $tx = shift;
    ...
  });

Emitted when transaction is resumed.

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

=head2 established

  my $bool = $ws->established;
  $ws      = $ws->established($bool);

WebSocket connection established.

=head2 handshake

  my $handshake = $ws->handshake;
  $ws           = $ws->handshake(Mojo::Transaction::HTTP->new);

The original handshake transaction, usually a L<Mojo::Transaction::HTTP> object.

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

L<Mojo::Transaction::WebSocket> inherits all methods from L<Mojo::Transaction>
and implements the following new ones.

=head2 build_message

  my $frame = $ws->build_message({binary => $bytes});
  my $frame = $ws->build_message({text   => $bytes});
  my $frame = $ws->build_message({json   => {test => [1, 2, 3]}});
  my $frame = $ws->build_message($chars);

Build WebSocket message.

=head2 client_read

  $ws->client_read($data);

Read data client-side, used to implement user agents such as L<Mojo::UserAgent>.

=head2 client_write

  my $bytes = $ws->client_write;

Write data client-side, used to implement user agents such as
L<Mojo::UserAgent>.

=head2 closed

  $tx = $tx->closed;

Same as L<Mojo::Transaction/"completed">, but also indicates that all
transaction data has been sent.

=head2 connection

  my $id = $ws->connection;

Connection identifier.

=head2 finish

  $ws = $ws->finish;
  $ws = $ws->finish(1000);
  $ws = $ws->finish(1003 => 'Cannot accept data!');

Close WebSocket connection gracefully.

=head2 is_websocket

  my $bool = $ws->is_websocket;

True, this is a L<Mojo::Transaction::WebSocket> object.

=head2 kept_alive

  my $bool = $ws->kept_alive;

Connection has been kept alive.

=head2 local_address

  my $address = $ws->local_address;

Local interface address.

=head2 local_port

  my $port = $ws->local_port;

Local interface port.

=head2 parse_message

  $ws->parse_message([$fin, $rsv1, $rsv2, $rsv3, $op, $payload]);

Parse WebSocket message.

=head2 protocol

  my $proto = $ws->protocol;

Return negotiated subprotocol or C<undef>.

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
will be executed once all data has been written.

  # Send "Ping" frame
  use Mojo::WebSocket 'WS_PING';
  $ws->send([1, 0, 0, 0, WS_PING, 'Hello World!']);

=head2 server_read

  $ws->server_read($data);

Read data server-side, used to implement web servers such as
L<Mojo::Server::Daemon>.

=head2 server_write

  my $bytes = $ws->server_write;

Write data server-side, used to implement web servers such as
L<Mojo::Server::Daemon>.

=head2 with_compression

  $ws->with_compression;

Negotiate C<permessage-deflate> extension for this WebSocket connection.

=head2 with_protocols

  my $proto = $ws->with_protocols('v2.proto', 'v1.proto');

Negotiate subprotocol for this WebSocket connection.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
