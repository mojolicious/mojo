package Mojo::IOLoop;
use Mojo::Base -base;

use Carp 'croak';
use Errno qw/EAGAIN EINTR ECONNRESET EWOULDBLOCK/;
use File::Spec;
use IO::File;
use IO::Socket::INET;
use IO::Socket::UNIX;
use Mojo::IOWatcher;
use Mojo::Resolver;
use Scalar::Util 'weaken';
use Socket qw/IPPROTO_TCP TCP_NODELAY/;
use Time::HiRes 'time';

use constant DEBUG      => $ENV{MOJO_IOLOOP_DEBUG} || 0;
use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE}   || 131072;

# IPv6 support requires IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval 'use IO::Socket::IP 0.06 (); 1';

# Epoll support requires IO::Epoll
use constant EPOLL => $ENV{MOJO_POLL}
  ? 0
  : eval 'use Mojo::IOWatcher::Epoll; 1';

# KQueue support requires IO::KQueue
use constant KQUEUE => $ENV{MOJO_POLL}
  ? 0
  : eval 'use Mojo::IOWatcher::KQueue; 1';

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval 'use IO::Socket::SSL 1.43 "inet4"; 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# Windows
use constant WINDOWS => $^O eq 'MSWin32' || $^O =~ /cygwin/ ? 1 : 0;

# Default TLS cert (20.03.2010)
# (openssl req -new -x509 -keyout cakey.pem -out cacert.pem -nodes -days 7300)
use constant CERT => <<EOF;
-----BEGIN CERTIFICATE-----
MIIDbzCCAtigAwIBAgIJAM+kFv1MwalmMA0GCSqGSIb3DQEBBQUAMIGCMQswCQYD
VQQGEwJERTEWMBQGA1UECBMNTmllZGVyc2FjaHNlbjESMBAGA1UEBxMJSGFtYmVy
Z2VuMRQwEgYDVQQKEwtNb2pvbGljaW91czESMBAGA1UEAxMJbG9jYWxob3N0MR0w
GwYJKoZIhvcNAQkBFg5rcmFpaEBjcGFuLm9yZzAeFw0xMDAzMjAwMDQ1MDFaFw0z
MDAzMTUwMDQ1MDFaMIGCMQswCQYDVQQGEwJERTEWMBQGA1UECBMNTmllZGVyc2Fj
aHNlbjESMBAGA1UEBxMJSGFtYmVyZ2VuMRQwEgYDVQQKEwtNb2pvbGljaW91czES
MBAGA1UEAxMJbG9jYWxob3N0MR0wGwYJKoZIhvcNAQkBFg5rcmFpaEBjcGFuLm9y
ZzCBnzANBgkqhkiG9w0BAQEFAAOBjQAwgYkCgYEAzu9mOiyUJB2NBuf1lZxViNM2
VISqRAoaXXGOBa6RgUoVfA/n81RQlgvVA0qCSQHC534DdYRk3CdyJR9UGPuxF8k4
CckOaHWgcJJsd8H0/q73PjbA5ItIpGTTJNh8WVpFDjHTJmQ5ihwddap4/offJxZD
dPrMFtw1ZHBRug5tHUECAwEAAaOB6jCB5zAdBgNVHQ4EFgQUo+Re5wuuzVFqH/zV
cxRGXL0j5K4wgbcGA1UdIwSBrzCBrIAUo+Re5wuuzVFqH/zVcxRGXL0j5K6hgYik
gYUwgYIxCzAJBgNVBAYTAkRFMRYwFAYDVQQIEw1OaWVkZXJzYWNoc2VuMRIwEAYD
VQQHEwlIYW1iZXJnZW4xFDASBgNVBAoTC01vam9saWNpb3VzMRIwEAYDVQQDEwls
b2NhbGhvc3QxHTAbBgkqhkiG9w0BCQEWDmtyYWloQGNwYW4ub3JnggkAz6QW/UzB
qWYwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQUFAAOBgQCZZcOeAobctD9wtPtO
40CKHpiGYEM3rh7VvBhjTcVnX6XlLvffIg3uTrVRhzmlEQCZz3O5TsBzfMAVnjYz
llhwgRF6Xn8ict9L8yKDoGSbw0Q7HaCb8/kOe0uKhcSDUd3PjJU0ZWgc20zcGFA9
R65bABoJ2vU1rlQFmjs0RT4UcQ==
-----END CERTIFICATE-----
EOF

# Default TLS key (20.03.2010)
# (openssl req -new -x509 -keyout cakey.pem -out cacert.pem -nodes -days 7300)
use constant KEY => <<EOF;
-----BEGIN RSA PRIVATE KEY-----
MIICXAIBAAKBgQDO72Y6LJQkHY0G5/WVnFWI0zZUhKpEChpdcY4FrpGBShV8D+fz
VFCWC9UDSoJJAcLnfgN1hGTcJ3IlH1QY+7EXyTgJyQ5odaBwkmx3wfT+rvc+NsDk
i0ikZNMk2HxZWkUOMdMmZDmKHB11qnj+h98nFkN0+swW3DVkcFG6Dm0dQQIDAQAB
AoGAeLmd8C51tqQu1GqbEc+E7zAZsDE9jDhArWdELfhsFvt7kUdOUN1Nrlv0x9i+
LY2Dgb44kmTM2suAgjvGulSMOYBGosZcM0w3ES76nmeAVJ1NBFhbZTCJqo9svoD/
NKdctRflUuvFSWimoui+vj9D5p/4lvAMdBHUWj5FlQsYiOECQQD/FRXtsDetptFu
Vp8Kw+6bZ5+efcjVfciTp7fQKI2xZ2n1QyloaV4zYXgDC2y3fMYuRigCGrX9XeFX
oGHGMyYFAkEAz635I8f4WQa/wvyl/SR5agtDVnkJqMHMgOuykytiF8NFbDSkJv+b
1VfyrWcfK/PVsSGBI67LCMDoP+PZBVOjDQJBAIInoCjH4aEZnYNPb5duojFpjmiw
helpZQ7yZTgxeRssSUR8IITGPuq4sSPckHyPjg/OfFuWhYXigTjU/Q7EyoECQERT
Dykna9wWLVZ/+jgLHOq3Y+L6FSRxBc/QO0LRvgblVlygAPVXmLQaqBtGVuoF4WLS
DANqSR/LH12Nn2NyPa0CQBbzoHgx2i3RncWoq1EeIg2mSMevEcjA6sxgYmsyyzlv
AnqxHi90n/p912ynLg2SjBq+03GaECeGzC/QqKK2gtA=
-----END RSA PRIVATE KEY-----
EOF

has [qw/accept_timeout connect_timeout/] => 3;
has iowatcher => sub {

  # "kqueue"
  if (KQUEUE) {
    warn "KQUEUE MAINLOOP\n" if DEBUG;
    return Mojo::IOWatcher::KQueue->new;
  }

  # "epoll"
  if (EPOLL) {
    warn "EPOLL MAINLOOP\n" if DEBUG;
    return Mojo::IOWatcher::Epoll->new;
  }

  # "poll"
  warn "POLL MAINLOOP\n" if DEBUG;
  Mojo::IOWatcher->new;
};
has max_accepts     => 0;
has max_connections => 1000;
has [qw/on_lock on_unlock/] => sub {
  sub {1}
};
has resolver => sub {
  my $self = shift;
  weaken $self;
  Mojo::Resolver->new(ioloop => $self);
};
has timeout => '0.025';

# Singleton
our $LOOP;

sub DESTROY {
  my $self = shift;
  if (my $cert = $self->{cert}) { unlink $cert if -w $cert }
  if (my $key  = $self->{key})  { unlink $key  if -w $key }
}

sub new {
  my $class = shift;

  # Build new loop from singleton and inherit watcher
  my $loop = $LOOP;
  local $LOOP = undef;
  my $self;
  if ($loop) {
    $self = $loop->new(@_);
    $self->iowatcher($loop->iowatcher->new);
  }

  # Start from scratch
  else { $self = $class->SUPER::new(@_) }

  # Ignore PIPE signal
  $SIG{PIPE} = 'IGNORE';

  return $self;
}

sub connect {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $args = ref $_[0] ? $_[0] : {@_};
  $args->{proto} ||= 'tcp';

  # New connection
  my $c = {
    buffer     => '',
    on_connect => $args->{on_connect},
    connecting => 1,
    tls        => $args->{tls},
    tls_cert   => $args->{tls_cert},
    tls_key    => $args->{tls_key}
  };
  (my $id) = "$c" =~ /0x([\da-f]+)/;
  $self->{cs}->{$id} = $c;

  # Register callbacks
  for my $name (qw/close error read/) {
    my $cb    = $args->{"on_$name"};
    my $event = "on_$name";
    $self->$event($id => $cb) if $cb;
  }

  # Lookup
  if (!$args->{handle} && (my $address = $args->{address})) {
    weaken $self;
    $self->resolver->lookup(
      $address => sub {
        my $resolver = shift;
        $args->{address} = shift || $args->{address};
        $self->_connect($id, $args);
      }
    );
  }

  # Connect
  else { $self->_connect($id, $args) }

  return $id;
}

sub connection_timeout {
  my ($self, $id, $timeout) = @_;
  return unless my $c = $self->{cs}->{$id};
  $c->{timeout} = $timeout and return $self if $timeout;
  $c->{timeout};
}

sub drop {
  my ($self, $id) = @_;
  $self = $self->singleton unless ref $self;

  # Drop connections gracefully
  if (my $c = $self->{cs}->{$id}) { return $c->{finish} = 1 }

  # Drop everything else right away
  $self->_drop($id);
}

sub generate_port {

  # Try random ports
  my $port = 1 . int(rand 10) . int(rand 10) . int(rand 10) . int(rand 10);
  while ($port++ < 30000) {
    return $port
      if IO::Socket::INET->new(
      Listen    => 5,
      LocalAddr => '127.0.0.1',
      LocalPort => $port,
      Proto     => 'tcp'
      );
  }

  return;
}

sub is_running {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  return $self->{running};
}

# "Fat Tony is a cancer on this fair city!
#  He is the cancer and I am the… uh… what cures cancer?"
sub listen {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $args = ref $_[0] ? $_[0] : {@_};

  # No TLS support
  croak "IO::Socket::SSL 1.43 required for TLS support"
    if $args->{tls} && !TLS;

  # Look for reusable file descriptor
  my $file  = $args->{file};
  my $port  = $args->{port} || 3000;
  my $reuse = defined $file ? $file : $port;
  $ENV{MOJO_REUSE} ||= '';
  my $fd;
  if ($ENV{MOJO_REUSE} =~ /(?:^|\,)$reuse\:(\d+)/) { $fd = $1 }

  # Stop listening so the new socket has a chance to join
  $self->_not_listening;

  # Allow file descriptor inheritance
  local $^F = 1000;

  # Listen on UNIX domain socket
  my $handle;
  my %options = (
    Listen => $args->{backlog} || SOMAXCONN,
    Proto  => 'tcp',
    Type   => SOCK_STREAM,
    %{$args->{args} || {}}
  );
  if (defined $file) {
    $options{Local} = $file;
    $handle =
      defined $fd
      ? IO::Socket::UNIX->new
      : IO::Socket::UNIX->new(%options)
      or croak "Can't create listen socket: $!";
  }

  # Listen on TCP port
  else {
    $options{LocalAddr} = $args->{address} || '0.0.0.0';
    $options{LocalPort} = $port;
    $options{Proto}     = 'tcp';
    $options{ReuseAddr} = 1;
    $options{LocalAddr} =~ s/[\[\]]//g;
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
    $handle = defined $fd ? $class->new : $class->new(%options)
      or croak "Can't create listen socket: $!";
  }

  # Reuse file descriptor
  if (defined $fd) {
    $handle->fdopen($fd, 'r')
      or croak "Can't open file descriptor $fd: $!";
  }
  else {
    $fd = fileno $handle;
    $reuse = ",$reuse" if length $ENV{MOJO_REUSE};
    $ENV{MOJO_REUSE} .= "$reuse:$fd";
  }

  # New connection
  my $c = {
    file => $args->{file} ? 1 : 0,
    on_accept => $args->{on_accept},
    on_close  => $args->{on_close},
    on_error  => $args->{on_error},
    on_read   => $args->{on_read},
  };
  (my $id) = "$c" =~ /0x([\da-f]+)/;
  $self->{listen}->{$id}      = $c;
  $c->{handle}                = $handle;
  $self->{reverse}->{$handle} = $id;

  # TLS
  if ($args->{tls}) {
    my %options = (
      SSL_startHandshake => 0,
      SSL_cert_file      => $args->{tls_cert} || $self->_cert_file,
      SSL_key_file       => $args->{tls_key} || $self->_key_file,
    );
    %options = (
      SSL_verify_callback => $args->{tls_verify},
      SSL_ca_file         => -T $args->{tls_ca} ? $args->{tls_ca} : undef,
      SSL_ca_path         => -d $args->{tls_ca} ? $args->{tls_ca} : undef,
      SSL_verify_mode     => $args->{tls_ca} ? 0x03 : undef,
      %options
    ) if $args->{tls_ca};
    $c->{tls} = {%options, %{$args->{tls_args} || {}}};
  }

  # Accept limit
  $self->{accepts} = $self->max_accepts if $self->max_accepts;

  return $id;
}

sub local_info {
  my ($self, $id) = @_;

  # UNIX domain socket info
  return {} unless my $c      = $self->{cs}->{$id};
  return {} unless my $handle = $c->{handle};
  return {path => $handle->hostpath} if $handle->can('hostpath');

  # TCP socket info
  return {address => $handle->sockhost, port => $handle->sockport};
}

sub on_close { shift->_event(close => @_) }
sub on_error { shift->_event(error => @_) }
sub on_read  { shift->_event(read  => @_) }

sub recurring {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->iowatcher->recurring($after => sub { $self->$cb(pop) });
}

sub one_tick {
  my ($self, $timeout) = @_;
  $timeout = $self->timeout unless defined $timeout;

  # Housekeeping
  $self->_listening;
  my $connections = $self->{cs} ||= {};
  while (my ($id, $c) = each %$connections) {

    # Connection needs to be finished
    if ($c->{finish} && !length $c->{buffer} && !$c->{drain}) {
      $self->_drop($id);
      next;
    }

    # Read only
    $self->_not_writing($id) if delete $c->{read_only};

    # Connection timeout
    my $time = $c->{active} ||= time;
    $self->_drop($id) if (time - $time) >= ($c->{timeout} || 15);
  }

  # Graceful shutdown
  $self->stop if $self->max_connections == 0 && keys %$connections == 0;

  # Watcher
  $self->iowatcher->one_tick($timeout);
}

sub handle {
  my ($self, $id) = @_;
  return unless my $c = $self->{cs}->{$id};
  return $c->{handle};
}

sub remote_info {
  my ($self, $id) = @_;

  # UNIX domain socket info
  return {} unless my $c      = $self->{cs}->{$id};
  return {} unless my $handle = $c->{handle};
  return {path => $handle->peerpath} if $handle->can('peerpath');

  # TCP socket info
  return {address => $handle->peerhost, port => $handle->peerport};
}

sub singleton { $LOOP ||= shift->new(@_) }

sub start {
  my $self = shift;
  $self = $self->singleton unless ref $self;

  # Check if we are already running
  return if $self->{running};
  $self->{running} = 1;

  # Mainloop
  $self->one_tick while $self->{running};

  return $self;
}

sub start_tls {
  my $self = shift;
  my $id   = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # No TLS support
  unless (TLS) {
    $self->_error($id, 'IO::Socket::SSL 1.43 required for TLS support.');
    return;
  }

  # Cleanup
  $self->drop($id) and return unless my $c      = $self->{cs}->{$id};
  $self->drop($id) and return unless my $handle = $c->{handle};
  delete $self->{reverse}->{$handle};
  my $watcher = $self->iowatcher->remove($handle);

  # TLS upgrade
  weaken $self;
  my %options = (
    SSL_startHandshake => 0,
    SSL_error_trap     => sub { $self->_error($id, $_[1]) },
    SSL_cert_file      => $args->{tls_cert},
    SSL_key_file       => $args->{tls_key},
    SSL_verify_mode    => 0x00,
    SSL_create_ctx_callback =>
      sub { Net::SSLeay::CTX_sess_set_cache_size(shift, 128) },
    Timeout => $self->connect_timeout,
    %{$args->{tls_args} || {}}
  );
  $self->drop($id) and return
    unless my $new = IO::Socket::SSL->start_SSL($handle, %options);
  $c->{handle} = $new;
  $self->{reverse}->{$new} = $id;
  $c->{tls_connect} = 1;
  $watcher->add(
    $new,
    on_readable => sub { $self->_read($id) },
    on_writable => sub { $self->_write($id) }
  )->writing($new);

  return $id;
}

sub stop {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  delete $self->{running};
}

sub test {
  my ($self, $id) = @_;
  return unless my $c      = $self->{cs}->{$id};
  return unless my $handle = $c->{handle};
  return $self->iowatcher->is_readable($handle);
}

sub timer {
  my ($self, $after, $cb) = @_;
  $self = $self->singleton unless ref $self;
  weaken $self;
  return $self->iowatcher->timer($after => sub { $self->$cb(pop) });
}

sub write {
  my ($self, $id, $chunk, $cb) = @_;

  # Prepare chunk for writing
  my $c = $self->{cs}->{$id};
  $c->{buffer} .= $chunk;

  # UNIX only quick write
  unless (WINDOWS) {
    $c->{drain} = 0 if $cb;
    $self->_write($id);
  }

  # Write with roundtrip
  $c->{drain} = $cb if $cb;
  $self->_writing($id) if $cb || length $c->{buffer};
}

sub _accept {
  my ($self, $listen) = @_;

  # Accept
  my $handle = $listen->accept or return;
  my $r      = $self->{reverse};
  my $l      = $self->{listen}->{$r->{$listen}};

  # New connection
  my $c = {buffer => ''};
  (my $id) = "$c" =~ /0x([\da-f]+)/;
  $self->{cs}->{$id} = $c;

  # TLS handshake
  weaken $self;
  if (my $tls = $l->{tls}) {
    $tls->{SSL_error_trap} = sub { $self->_error($id, $_[1]) };
    $handle = IO::Socket::SSL->start_SSL($handle, %$tls);
    $c->{tls_accept} = 1;
  }

  # Start watching for events
  $self->iowatcher->add(
    $handle,
    on_readable => sub { $self->_read($id) },
    on_writable => sub { $self->_write($id) }
  );
  $c->{handle} = $handle;
  $r->{$handle} = $id;

  # Non-blocking
  $handle->blocking(0);

  # Disable Nagle's algorithm
  setsockopt($handle, IPPROTO_TCP, TCP_NODELAY, 1) unless $l->{file};

  # Register callbacks
  for my $name (qw/on_close on_error on_read/) {
    my $cb = $l->{$name};
    $self->$name($id => $cb) if $cb;
  }

  # Accept limit
  $self->max_connections(0)
    if defined $self->{accepts} && --$self->{accepts} == 0;

  # Accept callback
  warn "ACCEPTED $id\n" if DEBUG;
  if ((my $cb = $c->{on_accept} = $l->{on_accept}) && !$l->{tls}) {
    $self->_sandbox('accept', $cb, $id);
  }

  # Stop listening
  $self->_not_listening;
}

sub _cert_file {
  my $self = shift;

  # Check if temporary TLS cert file already exists
  my $cert = $self->{cert};
  return $cert if $cert && -r $cert;

  # Create temporary TLS cert file
  $cert = File::Spec->catfile($ENV{MOJO_TMPDIR} || File::Spec->tmpdir,
    'mojocert.pem');
  croak qq/Can't create temporary TLS cert file "$cert"/
    unless my $file = IO::File->new("> $cert");
  print $file CERT;

  $self->{cert} = $cert;
}

sub _connect {
  my ($self, $id, $args) = @_;

  # New handle
  my $handle;
  return unless my $c = $self->{cs}->{$id};
  unless ($handle = $args->{handle}) {

    # New socket
    my %options = (
      Blocking => 0,
      PeerAddr => $args->{address},
      PeerPort => $args->{port} || ($args->{tls} ? 443 : 80),
      Proto    => $args->{proto},
      Type     => $args->{proto} eq 'udp' ? SOCK_DGRAM : SOCK_STREAM,
      %{$args->{args} || {}}
    );
    $options{PeerAddr} =~ s/[\[\]]//g if $options{PeerAddr};
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
    return $self->_error($id, "Couldn't connect.")
      unless $handle = $class->new(%options);

    # Timer
    $c->{connect_timer} =
      $self->timer($self->connect_timeout,
      sub { shift->_error($id, 'Connect timeout.') });

    # IPv6 needs an early start
    $handle->connect if IPV6;
  }
  $c->{handle} = $handle;
  $self->{reverse}->{$handle} = $id;

  # Non-blocking
  $handle->blocking(0);

  # Start writing right away
  $self->iowatcher->add(
    $handle,
    on_readable => sub { $self->_read($id) },
    on_writable => sub { $self->_write($id) }
  )->writing($handle);

  # Start TLS
  if ($args->{tls}) { $self->start_tls($id => $args) }
}

sub _drop {
  my ($self, $id) = @_;

  # Cancel timer
  return $self unless my $watcher = $self->iowatcher;
  return $self if $watcher->cancel($id);

  # Drop listen socket
  my $c = $self->{cs}->{$id};
  if ($c) { return if $c->{drop}++ }
  elsif ($c = delete $self->{listen}->{$id}) {
    return $self unless $self->{listening};
    delete $self->{listening};
  }

  # Delete associated timers
  if (my $t = $c->{connect_timer} || $c->{accept_timer}) { $self->_drop($t) }

  # Drop handle
  if (my $handle = $c->{handle}) {
    warn "DISCONNECTED $id\n" if DEBUG;

    # Handle close
    if (my $cb = $c->{close}) { $self->_sandbox('close', $cb, $id) }

    # Cleanup
    delete $self->{cs}->{$id};
    delete $self->{reverse}->{$handle};
    $watcher->remove($handle);
    close $handle;
  }

  return $self;
}

sub _error {
  my ($self, $id, $error) = @_;
  $error ||= 'Unknown error, probably harmless.';
  warn qq/ERROR $id "$error"\n/ if DEBUG;

  # Handle error
  return unless my $c = $self->{cs}->{$id};
  if (my $cb = $c->{error}) { $self->_sandbox('error', $cb, $id, $error) }
  else { warn "Unhandled event error: $error" and return }
  $self->_drop($id);
}

sub _event {
  my ($self, $event, $id, $cb) = @_;
  return unless my $c = $self->{cs}->{$id};
  $c->{$event} = $cb if $cb;
  return $self;
}

sub _key_file {
  my $self = shift;

  # Check if temporary TLS key file already exists
  my $key = $self->{key};
  return $key if $key && -r $key;

  # Create temporary TLS key file
  $key = File::Spec->catfile($ENV{MOJO_TMPDIR} || File::Spec->tmpdir,
    'mojokey.pem');
  croak qq/Can't create temporary TLS key file "$key"/
    unless my $file = IO::File->new("> $key");
  print $file KEY;

  $self->{key} = $key;
}

sub _listening {
  my $self = shift;

  # Already listening or no listen sockets
  return if $self->{listening};
  my $listen = $self->{listen} ||= {};
  return unless keys %$listen;

  # Check if we are allowed to listen and lock
  my $i = keys %{$self->{cs}};
  return unless $i < $self->max_connections;
  return unless $self->on_lock->($self, !$i);

  # Listen
  weaken $self;
  my $watcher = $self->iowatcher;
  for my $lid (keys %$listen) {
    $watcher->add($listen->{$lid}->{handle},
      on_readable => sub { $self->_accept(pop) });
  }
  $self->{listening} = 1;
}

sub _not_listening {
  my $self = shift;

  # Check if we are listening and unlock
  return unless delete $self->{listening};
  $self->on_unlock->($self);

  # Stop listening
  my $listen = $self->{listen} || {};
  $self->iowatcher->remove($listen->{$_}->{handle}) for keys %$listen;
  delete $self->{listening};
}

sub _not_writing {
  my ($self, $id) = @_;
  return unless my $c = $self->{cs}->{$id};
  return $c->{read_only} = 1 if length $c->{buffer} || $c->{drain};
  return unless my $handle = $c->{handle};
  $self->iowatcher->not_writing($handle);
}

sub _read {
  my ($self, $id) = @_;

  # Check if everything is ready to read
  my $c = $self->{cs}->{$id};
  return $self->_tls_accept($id)  if $c->{tls_accept};
  return $self->_tls_connect($id) if $c->{tls_connect};
  return unless defined(my $handle = $c->{handle});

  # Read
  my $read = $handle->sysread(my $buffer, CHUNK_SIZE, 0);

  # Error
  unless (defined $read) {

    # Retry
    return if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

    # Connection reset
    return $self->_drop($id) if $! == ECONNRESET;

    # Read error
    return $self->_error($id, $!);
  }

  # EOF
  return $self->_drop($id) if $read == 0;

  # Handle read
  if (my $cb = $c->{read}) { $self->_sandbox('read', $cb, $id, $buffer) }

  # Active
  $c->{active} = time;
}

sub _sandbox {
  my $self  = shift;
  my $event = shift;
  my $cb    = shift;
  my $id    = shift;

  # Sandbox event
  unless (eval { $self->$cb($id, @_); 1 }) {
    my $message = qq/Event "$event" failed for connection "$id": $@/;
    $event eq 'error'
      ? ($self->_drop($id) and warn $message)
      : $self->_error($id, $message);
  }
}

sub _tls_accept {
  my ($self, $id) = @_;

  # Accepted
  my $c = $self->{cs}->{$id};
  if ($c->{handle}->accept_SSL) {

    # Handle TLS accept
    delete $c->{tls_accept};
    if (my $cb = $c->{on_accept}) { $self->_sandbox('accept', $cb, $id) }
    return;
  }

  # Switch between reading and writing
  $self->_tls_error($id);
}

sub _tls_connect {
  my ($self, $id) = @_;

  # Connected
  my $c = $self->{cs}->{$id};
  if ($c->{handle}->connect_SSL) {

    # Handle TLS connect
    delete $c->{tls_connect};
    if (my $cb = $c->{on_connect}) { $self->_sandbox('connect', $cb, $id) }
    return;
  }

  # Switch between reading and writing
  $self->_tls_error($id);
}

sub _tls_error {
  my ($self, $id) = @_;
  my $error = $IO::Socket::SSL::SSL_ERROR;
  if    ($error == TLS_READ)  { $self->_not_writing($id) }
  elsif ($error == TLS_WRITE) { $self->_writing($id) }
}

sub _write {
  my ($self, $id) = @_;

  # Check if we are ready for writing
  my $c = $self->{cs}->{$id};
  return $self->_tls_accept($id)  if $c->{tls_accept};
  return $self->_tls_connect($id) if $c->{tls_connect};
  return unless my $handle = $c->{handle};

  # Connected
  if ($c->{connecting}) {
    delete $c->{connecting};
    my $timer = delete $c->{connect_timer};
    $self->_drop($timer) if $timer;

    # Disable Nagle's algorithm
    setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

    # Handle connect
    warn "CONNECTED $id\n" if DEBUG;
    if (!$c->{tls} && (my $cb = $c->{on_connect})) {
      $self->_sandbox('connect', $cb, $id);
    }
  }

  # Handle drain
  if (!length $c->{buffer} && (my $cb = delete $c->{drain})) {
    $self->_sandbox('drain', $cb, $id);
  }

  # Write as much as possible
  if (length $c->{buffer}) {
    my $written = $handle->syswrite($c->{buffer});

    # Error
    unless (defined $written) {

      # Retry
      return if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

      # Write error
      return $self->_error($id, $!);
    }

    # Remove written chunk from buffer
    substr $c->{buffer}, 0, $written, '';

    # Active
    $c->{active} = time;
  }

  # Not writing
  $self->_not_writing($id) unless exists $c->{drain} || length $c->{buffer};
}

sub _writing {
  my ($self, $id) = @_;
  my $c = $self->{cs}->{$id};
  delete $c->{read_only};
  return unless my $handle = $c->{handle};
  $self->iowatcher->writing($handle);
}

1;
__END__

=head1 NAME

Mojo::IOLoop - Minimalistic Reactor For Async TCP Clients And Servers

=head1 SYNOPSIS

  use Mojo::IOLoop;

  # Listen on port 3000
  Mojo::IOLoop->listen(
    port => 3000,
    on_read => sub {
      my ($self, $id, $chunk) = @_;

      # Process input
      print $chunk;

      # Got some data, time to write
      $self->write($id, 'HTTP/1.1 200 OK');
    }
  );

  # Connect to port 3000 with TLS activated
  my $id = Mojo::IOLoop->connect(
    address => 'localhost',
    port => 3000,
    tls => 1,
    on_connect => sub {
      my ($self, $id) = @_;

      # Write request
      $self->write($id, "GET / HTTP/1.1\r\n\r\n");
    },
    on_read => sub {
      my ($self, $id, $chunk) = @_;

      # Process input
      print $chunk;
    }
  );

  # Add a timer
  Mojo::IOLoop->timer(5 => sub {
    my $self = shift;
    $self->drop($id);
  });

  # Start and stop loop
  Mojo::IOLoop->start;
  Mojo::IOLoop->stop;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a very minimalistic reactor that has been reduced to the
absolute minimal feature set required to build solid and scalable async TCP
clients and servers.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::IP> and
L<IO::Socket::SSL> are supported transparently and used if installed.

A TLS certificate and key are also built right in to make writing test
servers as easy as possible.

=head1 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 C<accept_timeout>

  my $timeout = $loop->accept_timeout;
  $loop       = $loop->accept_timeout(5);

Maximum time in seconds a connection can take to be accepted before being
dropped, defaults to C<3>.

=head2 C<connect_timeout>

  my $timeout = $loop->connect_timeout;
  $loop       = $loop->connect_timeout(5);

Maximum time in seconds a conenction can take to be connected before being
dropped, defaults to C<3>.

=head2 C<iowatcher>

  my $watcher = $loop->iowatcher;
  $loop       = $loop->iowatcher(Mojo::IOWatcher->new);

Low level event watcher, usually a L<Mojo::IOWatcher>,
L<Mojo::IOWatcher::KQueue> or L<Mojo::IOLoop::Epoll> object.
Replacing the event watcher of the singleton loop makes all new loops use the
same type of event watcher.
Note that this attribute is EXPERIMENTAL and might change without warning!

  Mojo::IOLoop->singleton->iowatcher(MyWatcher->new);

=head2 C<max_accepts>

  my $max = $loop->max_accepts;
  $loop   = $loop->max_accepts(1000);

The maximum number of connections this loop is allowed to accept before
shutting down gracefully without interrupting existing connections, defaults
to C<0>.
Setting the value to C<0> will allow this loop to accept new connections
infinitely.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<max_connections>

  my $max = $loop->max_connections;
  $loop   = $loop->max_connections(1000);

The maximum number of parallel connections this loop is allowed to handle
before stopping to accept new incoming connections, defaults to C<1000>.
Setting the value to C<0> will make this loop stop accepting new connections
and allow it to shutdown gracefully without interrupting existing
connections.

=head2 C<on_lock>

  my $cb = $loop->on_lock;
  $loop  = $loop->on_lock(sub {...});

A locking callback that decides if this loop is allowed to accept new
incoming connections, used to sync multiple server processes.
The callback should return true or false.
Note that exceptions in this callback are not captured.

  $loop->on_lock(sub {
    my ($loop, $blocking) = @_;

    # Got the lock, listen for new connections
    return 1;
  });

=head2 C<on_unlock>

  my $cb = $loop->on_unlock;
  $loop  = $loop->on_unlock(sub {...});

A callback to free the accept lock, used to sync multiple server processes.
Note that exceptions in this callback are not captured.

=head2 C<resolver>

  my $resolver = $loop->resolver;
  $loop        = $loop->resolver(Mojo::Resolver->new);

DNS stub resolver, usually a L<Mojo::Resolver> object.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<timeout>

  my $timeout = $loop->timeout;
  $loop       = $loop->timeout(5);

Maximum time in seconds our loop waits for new events to happen, defaults to
C<0.025>.
Note that a value of C<0> would make the loop non-blocking.

=head1 METHODS

L<Mojo::IOLoop> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $loop = Mojo::IOLoop->new;

Construct a new L<Mojo::IOLoop> object.
Multiple of these will block each other, so use C<singleton> instead if
possible.

=head2 C<connect>

  my $id = Mojo::IOLoop->connect(
    address => '127.0.0.1',
    port    => 3000
  );
  my $id = $loop->connect(
    address => '127.0.0.1',
    port    => 3000
  );

Open a TCP connection to a remote host.
Note that TLS support depends on L<IO::Socket::SSL> and IPv6 support on
L<IO::Socket::IP>.

These options are currently available:

=over 2

=item C<address>

Address or host name of the peer to connect to.

=item C<handle>

Use an already prepared handle.

=item C<on_connect>

Callback to be invoked once the connection is established.

=item C<on_close>

Callback to be invoked if the connection gets closed.

=item C<on_error>

Callback to be invoked if an error event happens on the connection.

=item C<on_read>

Callback to be invoked if new data arrives on the connection.

=item C<port>

Port to connect to.

=item C<proto>

Protocol to use, defaults to C<tcp>.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS certificate file.

=item C<tls_key>

Path to the TLS key file.

=back

=head2 C<connection_timeout>

  my $timeout = $loop->connection_timeout($id);
  $loop       = $loop->connection_timeout($id => 45);

Maximum amount of time in seconds a connection can be inactive before being
dropped, defaults to C<15>.

=head2 C<drop>

  $loop = Mojo::IOLoop->drop($id)
  $loop = $loop->drop($id);

Drop anything with an id.
Connections will be dropped gracefully by allowing them to finish writing all
data in its write buffer.

=head2 C<generate_port>

  my $port = Mojo::IOLoop->generate_port;
  my $port = $loop->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 C<handle>

  my $handle = $loop->handle($id);

Get handle for id.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<is_running>

  my $running = Mojo::IOLoop->is_running;
  my $running = $loop->is_running;

Check if loop is running.

  exit unless Mojo::IOLoop->is_running;

=head2 C<listen>

  my $id = Mojo::IOLoop->listen(port => 3000);
  my $id = $loop->listen(port => 3000);
  my $id = $loop->listen({port => 3000});
  my $id = $loop->listen(file => '/foo/myapp.sock');
  my $id = $loop->listen(
    port     => 443,
    tls      => 1,
    tls_cert => '/foo/server.cert',
    tls_key  => '/foo/server.key'
  );

Create a new listen socket.
Note that TLS support depends on L<IO::Socket::SSL> and IPv6 support on
L<IO::Socket::IP>.

These options are currently available:

=over 2

=item C<address>

Local address to listen on, defaults to all.

=item C<backlog>

Maximum backlog size, defaults to C<SOMAXCONN>.

=item C<file>

A unix domain socket to listen on.

=item C<on_accept>

Callback to be invoked for each accepted connection.

=item C<on_close>

Callback to be invoked if the connection gets closed.

=item C<on_error>

Callback to be invoked if an error event happens on the connection.

=item C<on_read>

Callback to be invoked if new data arrives on the connection.

=item C<port>

Port to listen on.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS cert file, defaulting to a built-in test certificate.

=item C<tls_key>

Path to the TLS key file, defaulting to a built-in test key.

=item C<tls_ca>

Path to TLS certificate authority file or directory.

=back

=head2 C<local_info>

  my $info = $loop->local_info($id);

Get local information about a connection.

  my $address = $info->{address};

These values are to be expected in the returned hash reference.

=over 2

=item C<address>

The local address.

=item C<port>

The local port.

=back

=head2 C<on_close>

  $loop = $loop->on_close($id => sub {...});

Callback to be invoked if the connection gets closed.

=head2 C<on_error>

  $loop = $loop->on_error($id => sub {...});

Callback to be invoked if an error event happens on the connection.

=head2 C<on_read>

  $loop = $loop->on_read($id => sub {...});

Callback to be invoked if new data arrives on the connection.

  $loop->on_read($id => sub {
    my ($loop, $id, $chunk) = @_;

    # Process chunk
  });

=head2 C<one_tick>

  $loop->one_tick;
  $loop->one_tick('0.25');
  $loop->one_tick(0);

Run reactor for exactly one tick.

=head2 C<recurring>

  my $id = Mojo::IOLoop->recurring(0 => sub {...});
  my $id = $loop->recurring(3 => sub {...});

Create a new recurring timer, invoking the callback repeatedly after a given
amount of seconds.
This for example allows you to run multiple reactors next to each other.

  my $loop2 = Mojo::IOLoop->new(timeout => 0);
  Mojo::IOLoop->recurring(0 => sub { $loop2->one_tick });

Note that the loop timeout can be changed dynamically at any time to adjust
responsiveness.

=head2 C<remote_info>

  my $info = $loop->remote_info($id);

Get remote information about a connection.

  my $address = $info->{address};

These values are to be expected in the returned hash reference.

=over 2

=item C<address>

The remote address.

=item C<port>

The remote port.

=back

=head2 C<singleton>

  my $loop = Mojo::IOLoop->singleton;

The global loop object, used to access a single shared loop instance from
everywhere inside the process.
Many methods also allow you to take shortcuts when using the L<Mojo::IOLoop>
singleton.

  Mojo::IOLoop->timer(2 => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;

=head2 C<start>

  Mojo::IOLoop->start;
  $loop->start;

Start the loop, this will block until C<stop> is called or return immediately
if the loop is already running.

=head2 C<start_tls>

  my $id = $loop->start_tls($id);

Start new TLS connection inside old connection.
Note that TLS support depends on L<IO::Socket::SSL>.

=head2 C<stop>

  Mojo::IOLoop->stop;
  $loop->stop;

Stop the loop immediately, this will not interrupt any existing connections
and the loop can be restarted by running C<start> again.

=head2 C<test>

  my $success = $loop->test($id);

Test for errors and garbage bytes on the connection.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<timer>

  my $id = Mojo::IOLoop->timer(5 => sub {...});
  my $id = $loop->timer(5 => sub {...});
  my $id = $loop->timer(0.25 => sub {...});

Create a new timer, invoking the callback after a given amount of seconds.

=head2 C<write>

  $loop->write($id => 'Hello!');
  $loop->write($id => 'Hello!', sub {...});

Write data to connection, the optional drain callback will be invoked once
all data has been written.

=head1 DEBUGGING

You can set the C<MOJO_IOLOOP_DEBUG> environment variable to get some
advanced diagnostics information printed to C<STDERR>.

  MOJO_IOLOOP_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
