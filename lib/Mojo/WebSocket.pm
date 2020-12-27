package Mojo::WebSocket;
use Mojo::Base -strict;

use Config;
use Exporter qw(import);
use Mojo::Util qw(b64_encode dumper sha1_bytes xor_encode);

use constant DEBUG => $ENV{MOJO_WEBSOCKET_DEBUG} || 0;

# Unique value from RFC 6455
use constant GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

# Perl with support for quads
use constant MODERN => (($Config{use64bitint} // '') eq 'define' || $Config{longsize} >= 8);

# Opcodes
use constant {WS_CONTINUATION => 0x0, WS_TEXT => 0x1, WS_BINARY => 0x2, WS_CLOSE => 0x8, WS_PING => 0x9,
  WS_PONG => 0xa};

our @EXPORT_OK = (
  qw(WS_BINARY WS_CLOSE WS_CONTINUATION WS_PING WS_PONG WS_TEXT build_frame challenge client_handshake parse_frame),
  qw(server_handshake)
);

sub build_frame {
  my ($masked, $fin, $rsv1, $rsv2, $rsv3, $op, $payload) = @_;
  warn "-- Building frame ($fin, $rsv1, $rsv2, $rsv3, $op)\n" if DEBUG;

  # Head
  my $head = $op + ($fin ? 128 : 0);
  $head |= 0b01000000 if $rsv1;
  $head |= 0b00100000 if $rsv2;
  $head |= 0b00010000 if $rsv3;
  my $frame = pack 'C', $head;

  # Small payload
  my $len = length $payload;
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

sub challenge {
  my $tx = shift;

  # "permessage-deflate" extension
  my $headers = $tx->res->headers;
  $tx->compressed(1) if ($headers->sec_websocket_extensions // '') =~ /permessage-deflate/;

  return _challenge($tx->req->headers->sec_websocket_key) eq $headers->sec_websocket_accept;
}

sub client_handshake {
  my $tx = shift;

  my $headers = $tx->req->headers;
  $headers->upgrade('websocket')      unless $headers->upgrade;
  $headers->connection('Upgrade')     unless $headers->connection;
  $headers->sec_websocket_version(13) unless $headers->sec_websocket_version;

  # Generate 16 byte WebSocket challenge
  my $challenge = b64_encode sprintf('%16u', int(rand 9 x 16)), '';
  $headers->sec_websocket_key($challenge) unless $headers->sec_websocket_key;

  return $tx;
}

sub parse_frame {
  my ($buffer, $max) = @_;

  # Head
  return undef unless length $$buffer >= 2;
  my ($first, $second) = unpack 'C2', $$buffer;

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
    $len  = unpack 'x2n', $$buffer;
    warn "-- Extended 16-bit payload ($len)\n" if DEBUG;
  }

  # Extended payload (64-bit with 32-bit fallback)
  elsif ($len == 127) {
    return undef unless length $$buffer > 10;
    $hlen = 10;
    $len  = MODERN ? unpack('x2Q>', $$buffer) : unpack('x2x4N', $$buffer);
    warn "-- Extended 64-bit payload ($len)\n" if DEBUG;
  }

  # Check message size
  return 1 if $len > $max;

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

sub server_handshake {
  my $tx = shift;

  my $headers = $tx->res->headers;
  $headers->upgrade('websocket')->connection('Upgrade');
  $headers->sec_websocket_accept(_challenge($tx->req->headers->sec_websocket_key));

  return $tx;
}

sub _challenge { b64_encode(sha1_bytes(($_[0] || '') . GUID), '') }

1;

=encoding utf8

=head1 NAME

Mojo::WebSocket - The WebSocket protocol

=head1 SYNOPSIS

  use Mojo::WebSocket qw(WS_TEXT build_frame parse_frame);

  my $bytes = build_frame 0, 1, 0, 0, 0, WS_TEXT, 'Hello World!';
  my $frame = parse_frame \$bytes, 262144;

=head1 DESCRIPTION

L<Mojo::WebSocket> implements the WebSocket protocol as described in L<RFC 6455|https://tools.ietf.org/html/rfc6455>.
Note that 64-bit frames require a Perl with support for quads or they are limited to 32-bit.

=head1 FUNCTIONS

L<Mojo::WebSocket> implements the following functions, which can be imported individually.

=head2 build_frame

  my $bytes = build_frame $masked, $fin, $rsv1, $rsv2, $rsv3, $op, $payload;

Build WebSocket frame.

  # Masked binary frame with FIN bit and payload
  say build_frame 1, 1, 0, 0, 0, WS_BINARY, 'Hello World!';

  # Text frame with payload but without FIN bit
  say build_frame 0, 0, 0, 0, 0, WS_TEXT, 'Hello ';

  # Continuation frame with FIN bit and payload
  say build_frame 0, 1, 0, 0, 0, WS_CONTINUATION, 'World!';

  # Close frame with FIN bit and without payload
  say build_frame 0, 1, 0, 0, 0, WS_CLOSE, '';

  # Ping frame with FIN bit and payload
  say build_frame 0, 1, 0, 0, 0, WS_PING, 'Test 123';

  # Pong frame with FIN bit and payload
  say build_frame 0, 1, 0, 0, 0, WS_PONG, 'Test 123';

=head2 challenge

  my $bool = challenge Mojo::Transaction::WebSocket->new;

Check WebSocket handshake challenge.

=head2 client_handshake

  my $tx = client_handshake Mojo::Transaction::HTTP->new;

Perform WebSocket handshake client-side.

=head2 parse_frame

  my $frame = parse_frame \$bytes, $limit;

Parse WebSocket frame.

  # Parse single frame and remove it from buffer
  my $frame = parse_frame \$buffer, 262144;
  say "FIN: $frame->[0]";
  say "RSV1: $frame->[1]";
  say "RSV2: $frame->[2]";
  say "RSV3: $frame->[3]";
  say "Opcode: $frame->[4]";
  say "Payload: $frame->[5]";

=head2 server_handshake

  my $tx = server_handshake Mojo::Transaction::HTTP->new;

Perform WebSocket handshake server-side.

=head1 CONSTANTS

L<Mojo::WebSocket> implements the following constants, which can be imported individually.

=head2 WS_BINARY

Opcode for C<Binary> frames.

=head2 WS_CLOSE

Opcode for C<Close> frames.

=head2 WS_CONTINUATION

Opcode for C<Continuation> frames.

=head2 WS_PING

Opcode for C<Ping> frames.

=head2 WS_PONG

Opcode for C<Pong> frames.

=head2 WS_TEXT

Opcode for C<Text> frames.

=head1 DEBUGGING

You can set the C<MOJO_WEBSOCKET_DEBUG> environment variable to get some advanced diagnostics information printed to
C<STDERR>.

  MOJO_WEBSOCKET_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
