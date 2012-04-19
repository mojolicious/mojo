package Mojo::IOLoop::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use File::Temp;
use IO::Socket::INET;
use Scalar::Util 'weaken';
use Socket qw/IPPROTO_TCP TCP_NODELAY/;

# IPv6 support requires IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval 'use IO::Socket::IP 0.06 (); 1';

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.37 "inet4"; 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# Default TLS cert (18.04.2012)
# (openssl req -new -x509 -keyout cakey.pem -out cacert.pem -nodes -days 7300)
use constant CERT => <<EOF;
-----BEGIN CERTIFICATE-----
MIIDaTCCAtKgAwIBAgIJAI+AzotR68CTMA0GCSqGSIb3DQEBBQUAMIGAMQswCQYD
VQQGEwJERTEWMBQGA1UECBMNTmllZGVyc2FjaHNlbjESMBAGA1UEBxMJSGFtYmVy
Z2VuMRQwEgYDVQQKEwtNb2pvbGljaW91czESMBAGA1UEAxMJbG9jYWxob3N0MRsw
GQYJKoZIhvcNAQkBFgxzcmlAY3Bhbi5vcmcwHhcNMTIwNDE4MTczOTU5WhcNMzIw
NDEzMTczOTU5WjCBgDELMAkGA1UEBhMCREUxFjAUBgNVBAgTDU5pZWRlcnNhY2hz
ZW4xEjAQBgNVBAcTCUhhbWJlcmdlbjEUMBIGA1UEChMLTW9qb2xpY2lvdXMxEjAQ
BgNVBAMTCWxvY2FsaG9zdDEbMBkGCSqGSIb3DQEJARYMc3JpQGNwYW4ub3JnMIGf
MA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCohcU0qG+hHn6JK8XdygAJo7EuRqG2
5GSHaRRMyYgd89tEluInMH86tVcktJ1s/0VVvr5anAp8L7Pgu01Wr13OfgIzBxCz
51ZIFxq4DtimBftXs9Z9M0sui2NuIPDrMEjkYUhUsxMEZcDSp2KJjDosZjSYUiiF
G2ACvVGXSrS16QIDAQABo4HoMIHlMB0GA1UdDgQWBBSrZ+hIlPTgV7xx2O9wzdIO
/d4osDCBtQYDVR0jBIGtMIGqgBSrZ+hIlPTgV7xx2O9wzdIO/d4osKGBhqSBgzCB
gDELMAkGA1UEBhMCREUxFjAUBgNVBAgTDU5pZWRlcnNhY2hzZW4xEjAQBgNVBAcT
CUhhbWJlcmdlbjEUMBIGA1UEChMLTW9qb2xpY2lvdXMxEjAQBgNVBAMTCWxvY2Fs
aG9zdDEbMBkGCSqGSIb3DQEJARYMc3JpQGNwYW4ub3JnggkAj4DOi1HrwJMwDAYD
VR0TBAUwAwEB/zANBgkqhkiG9w0BAQUFAAOBgQAq6MXA7ZeO7B7vAcWxQKeLPKSy
Jzkb1bC/agaISDbOwuZ1AoQSj6OQHKhNIdY5v/oLQJ0B8wB0dIigqn1WVacDtPgu
PKSrxpqieDCh2bJ7+dyQIzQHgtZqPHi5k1PyNNXQxC94kPWdFp6PpF0M/y97aCxC
ZQjKgDfncFWY3FHqUw==
-----END CERTIFICATE-----
EOF

# Default TLS key (18.04.2012)
# (openssl req -new -x509 -keyout cakey.pem -out cacert.pem -nodes -days 7300)
use constant KEY => <<EOF;
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQCohcU0qG+hHn6JK8XdygAJo7EuRqG25GSHaRRMyYgd89tEluIn
MH86tVcktJ1s/0VVvr5anAp8L7Pgu01Wr13OfgIzBxCz51ZIFxq4DtimBftXs9Z9
M0sui2NuIPDrMEjkYUhUsxMEZcDSp2KJjDosZjSYUiiFG2ACvVGXSrS16QIDAQAB
AoGALSdqp6lZ/7nD/c0Uv1CYofySROv3+KFJrl6hadG1/xCP99jVz9pWvMxKBTO/
2qyrT0ZEitK0nIHLmLOXDVr/rxzbxP/kHmkOLKj45jW31BSap89tUpFjFQXFfjwT
YnOgOB4+eqQuGwigCqabcQPtFC4fU7Qzk7pdz/kO4FjR0GECQQDdXthCKgS7E5Zy
qqzjepxYvKgkWPD3G9H6I8LOtiVBdcehflF8Y61OGsEST3pbOhrijhY281VnD1AG
pNL1rOhDAkEAwuKKTN+2GF3m1mPtGW9jpkP8gU2zcO945U0jxpn2srjQ9oIoB45Y
gqtE6yybRY4BBd+hMdgeH5dXSwsZW+FMYwJASrFy5LhKylisndoq5cJ8OJDHZyQ/
ghF4Ax/H3nmlDnZQOpRlqEP1uPHcDXKVxWxQn/rzUe0+9rw681Lv/4ctAwJAfyLO
2muvHaJUr1QtH0S9m4AKwEfyYiC3m8+BIVTbzagoGki62IMSVtxob4uAGBYVsME9
JYk5zZ4rgndRKdGGxQJBAIpbdLBKArvnpbYIqNJGG83mUZ/VZaQl0G+S3zGkgre9
KjIuz10nNMNAKmGRrTbClLtvAQ9MVa3Xjnp+XmxPFho=
-----END RSA PRIVATE KEY-----
EOF

has accepts => 10;
has reactor => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->reactor;
};

# "Your guilty consciences may make you vote Democratic, but secretly you all
#  yearn for a Republican president to lower taxes, brutalize criminals, and
#  rule you like a king!"
sub DESTROY {
  my $self = shift;
  if (my $port = $self->{port}) { $ENV{MOJO_REUSE} =~ s/(?:^|\,)$port\:\d+// }
  defined $_ and -w $_ and unlink $_ for $self->{cert}, $self->{key};
  return unless my $reactor = $self->{reactor};
  $self->stop if $self->{handle};
  $reactor->remove($_) for values %{$self->{handles}};
}

# "And I gave that man directions, even though I didn't know the way,
#  because that's the kind of guy I am this week."
sub listen {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # Look for reusable file descriptor
  my $reuse = my $port = $self->{port} = $args->{port} || 3000;
  $ENV{MOJO_REUSE} ||= '';
  my $fd;
  if ($ENV{MOJO_REUSE} =~ /(?:^|\,)$reuse\:(\d+)/) { $fd = $1 }

  # Allow file descriptor inheritance
  local $^F = 1000;

  # Reuse file descriptor
  my $handle;
  my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
  if (defined $fd) {
    $handle = $class->new;
    $handle->fdopen($fd, 'r') or croak "Can't open file descriptor $fd: $!";
  }

  # New socket
  else {
    my %options = (
      Listen => $args->{backlog} // SOMAXCONN,
      LocalAddr => $args->{address} || '0.0.0.0',
      LocalPort => $port,
      Proto     => 'tcp',
      ReuseAddr => 1,
      Type      => SOCK_STREAM
    );
    $options{LocalAddr} =~ s/[\[\]]//g;
    $handle = $class->new(%options) or croak "Can't create listen socket: $!";
    $fd     = fileno $handle;
    $reuse  = ",$reuse" if length $ENV{MOJO_REUSE};
    $ENV{MOJO_REUSE} .= "$reuse:$fd";
  }
  $handle->blocking(0);
  $self->{handle} = $handle;

  # TLS
  return unless $args->{tls};
  croak "IO::Socket::SSL 1.37 required for TLS support" unless TLS;

  # Options
  my $options = $self->{tls} = {
    SSL_cert_file => $args->{tls_cert} || $self->_cert_file,
    SSL_key_file  => $args->{tls_key}  || $self->_key_file,
    SSL_startHandshake => 0
  };
  %$options = (
    %$options,
    SSL_ca_file => -T $args->{tls_ca} ? $args->{tls_ca} : undef,
    SSL_verify_mode => 0x03
  ) if $args->{tls_ca};
}

sub generate_port {
  IO::Socket::INET->new(
    Listen    => 5,
    LocalAddr => '127.0.0.1',
    Proto     => 'tcp'
  )->sockport;
}

sub start {
  my $self = shift;
  weaken $self;
  $self->reactor->io(
    $self->{handle} => sub { $self->_accept for 1 .. $self->accepts });
}

sub stop {
  my $self = shift;
  $self->reactor->remove($self->{handle});
}

sub _accept {
  my $self = shift;

  # Accept
  return unless my $handle = $self->{handle}->accept;
  $handle->blocking(0);

  # Disable Nagle's algorithm
  setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

  # Start TLS handshake
  return $self->emit_safe(accept => $handle) unless my $tls = $self->{tls};
  weaken $self;
  $tls->{SSL_error_trap} = sub {
    return unless my $handle = delete $self->{handles}{shift()};
    $self->reactor->remove($handle);
    close $handle;
  };
  return unless $handle = IO::Socket::SSL->start_SSL($handle, %$tls);
  $self->reactor->io($handle => sub { $self->_tls($handle) });
  $self->{handles}{$handle} = $handle;
}

sub _cert_file {
  my $self = shift;
  return $self->{cert} if $self->{cert};
  my $cert = File::Temp->new(UNLINK => 0, SUFFIX => ".$$.pem");
  print $cert CERT;
  return $self->{cert} = $cert->filename;
}

sub _key_file {
  my $self = shift;
  return $self->{key} if $self->{key};
  my $key = File::Temp->new(UNLINK => 0, SUFFIX => ".$$.pem");
  print $key KEY;
  return $self->{key} = $key->filename;
}

# "Where on my badge does it say anything about protecting people?
#  Uh, second word, chief."
sub _tls {
  my ($self, $handle) = @_;

  # Accepted
  if ($handle->accept_SSL) {
    $self->reactor->remove($handle);
    delete $self->{handles}{$handle};
    return $self->emit_safe(accept => $handle);
  }

  # Switch between reading and writing
  my $err = $IO::Socket::SSL::SSL_ERROR;
  if    ($err == TLS_READ)  { $self->reactor->watch($handle, 1, 0) }
  elsif ($err == TLS_WRITE) { $self->reactor->watch($handle, 1, 1) }
}

1;
__END__

=head1 NAME

Mojo::IOLoop::Server - Non-blocking TCP server

=head1 SYNOPSIS

  use Mojo::IOLoop::Server;

  # Create listen socket
  my $server = Mojo::IOLoop::Server->new;
  $server->on(accept => sub {
    my ($server, $handle) = @_;
    ...
  });
  $server->listen(port => 3000);

  # Start and stop accepting connections
  $server->start;
  $server->stop;

=head1 DESCRIPTION

L<Mojo::IOLoop::Server> accepts TCP connections for L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Server> can emit the following events.

=head2 C<accept>

  $server->on(accept => sub {
    my ($server, $handle) = @_;
    ...
  });

Emitted safely for each accepted connection.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Server> implements the following attributes.

=head2 C<accepts>

  my $accepts = $server->accepts;
  $server     = $server->accepts(10);

Number of connections to accept at once, defaults to C<10>.

=head2 C<reactor>

  my $reactor = $server->reactor;
  $server     = $server->reactor(Mojo::Reactor::Poll->new);

Low level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Server> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<listen>

  $server->listen(port => 3000);

Create a new listen socket. Note that TLS support depends on
L<IO::Socket::SSL> and IPv6 support on L<IO::Socket::IP>.

These options are currently available:

=over 2

=item C<address>

Local address to listen on, defaults to all.

=item C<backlog>

Maximum backlog size, defaults to C<SOMAXCONN>.

=item C<port>

Port to listen on.

=item C<tls>

Enable TLS.

=item C<tls_ca>

Path to TLS certificate authority file.

=item C<tls_cert>

Path to the TLS cert file, defaults to a built-in test certificate.

=item C<tls_key>

Path to the TLS key file, defaults to a built-in test key.

=back

=head2 C<generate_port>

  my $port = $server->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 C<start>

  $server->start;

Start accepting connections.

=head2 C<stop>

  $server->stop;

Stop accepting connections.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
