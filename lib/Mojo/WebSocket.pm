package Mojo::WebSocket;
use Mojo::Base -strict;

use Exporter 'import';
use Mojo::Util qw(b64_encode sha1_bytes);

our @EXPORT_OK = qw(challenge client_handshake server_handshake);

# Unique value from RFC 6455
use constant GUID => '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

sub challenge {
  my $tx = shift;

  # "permessage-deflate" extension
  my $headers = $tx->res->headers;
  $tx->compressed(1)
    if ($headers->sec_websocket_extensions // '') =~ /permessage-deflate/;

  return _challenge($tx->req->headers->sec_websocket_key) eq
    $headers->sec_websocket_accept;
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

sub server_handshake {
  my $tx = shift;

  my $res_headers = $tx->res->headers;
  $res_headers->upgrade('websocket')->connection('Upgrade');
  $res_headers->sec_websocket_accept(
    _challenge($tx->req->headers->sec_websocket_key));

  return $tx;
}

sub _challenge { b64_encode(sha1_bytes(($_[0] || '') . GUID), '') }

1;
