package Mojo::IOLoop;
use Mojo::Base -base;

use Carp 'croak';
use Errno qw/EAGAIN EINTR ECONNRESET EWOULDBLOCK/;
use File::Spec;
use IO::File;
use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use IO::Socket;
use List::Util 'first';
use Mojo::URL;
use Scalar::Util 'weaken';
use Socket qw/IPPROTO_TCP TCP_NODELAY/;
use Time::HiRes qw/time usleep/;

use constant DEBUG      => $ENV{MOJO_IOLOOP_DEBUG} || 0;
use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE}   || 131072;

# "AF_INET6" requires Socket6 or Perl 5.12
use constant IPV6_AF_INET6 => eval { Socket::AF_INET6() }
  || eval { require Socket6 and Socket6::AF_INET6() };

# "inet_pton" requires Socket6 or Perl 5.12
BEGIN {

  # Socket
  if (defined &Socket::inet_pton) { *inet_pton = \&Socket::inet_pton }

  # Socket6
  elsif (eval { require Socket6 and defined &Socket6::inet_pton }) {
    *inet_pton = \&Socket6::inet_pton;
  }
}

# IPv6 DNS support requires "AF_INET6" and "inet_pton"
use constant IPV6_DNS => defined IPV6_AF_INET6 && defined &inet_pton;

# IPv6 support requires "AF_INET6", "inet_pton" and IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6} ? 0 : IPV6_DNS
  && eval 'use IO::Socket::IP 0.06 (); 1';

# Epoll support requires IO::Epoll
use constant EPOLL => $ENV{MOJO_POLL}
  ? 0
  : eval 'use IO::Epoll 0.02 (); 1';
use constant EPOLL_POLLERR => EPOLL ? IO::Epoll::POLLERR() : 0;
use constant EPOLL_POLLHUP => EPOLL ? IO::Epoll::POLLHUP() : 0;
use constant EPOLL_POLLIN  => EPOLL ? IO::Epoll::POLLIN()  : 0;
use constant EPOLL_POLLOUT => EPOLL ? IO::Epoll::POLLOUT() : 0;

# KQueue support requires IO::KQueue
use constant KQUEUE => $ENV{MOJO_POLL}
  ? 0
  : eval 'use IO::KQueue 0.34 (); 1';
use constant KQUEUE_ADD    => KQUEUE ? IO::KQueue::EV_ADD()       : 0;
use constant KQUEUE_DELETE => KQUEUE ? IO::KQueue::EV_DELETE()    : 0;
use constant KQUEUE_EOF    => KQUEUE ? IO::KQueue::EV_EOF()       : 0;
use constant KQUEUE_READ   => KQUEUE ? IO::KQueue::EVFILT_READ()  : 0;
use constant KQUEUE_WRITE  => KQUEUE ? IO::KQueue::EVFILT_WRITE() : 0;

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

# DNS server (default to Google Public DNS)
my $DNS_SERVERS = ['8.8.8.8', '8.8.4.4'];

# Try to detect DNS server
if (-r '/etc/resolv.conf') {
  my $file = IO::File->new;
  $file->open('< /etc/resolv.conf');
  my @servers;
  for my $line (<$file>) {

    # New DNS server
    if ($line =~ /^nameserver\s+(\S+)$/) {
      push @servers, $1;
      warn qq/DETECTED DNS SERVER ($1)\n/ if DEBUG;
    }
  }
  unshift @$DNS_SERVERS, @servers;
}

# User defined DNS server
unshift @$DNS_SERVERS, $ENV{MOJO_DNS_SERVER} if $ENV{MOJO_DNS_SERVER};

# Always start with first DNS server
my $CURRENT_DNS_SERVER = 0;

# DNS record types
my $DNS_TYPES = {
  '*'   => 0x00ff,
  A     => 0x0001,
  AAAA  => 0x001c,
  CNAME => 0x0005,
  MX    => 0x000f,
  NS    => 0x0002,
  PTR   => 0x000c,
  TXT   => 0x0010
};

# "localhost"
our $LOCALHOST = '127.0.0.1';

has [qw/accept_timeout connect_timeout dns_timeout/] => 3;
has max_accepts     => 0;
has max_connections => 1000;
has [qw/on_lock on_unlock/] => sub {
  sub {1}
};
has timeout => '0.025';

# Singleton
our $LOOP;

sub DESTROY {
  my $self = shift;

  # Cleanup connections
  for my $id (keys %{$self->{_cs}}) { $self->_drop_immediately($id) }

  # Cleanup listen sockets
  for my $id (keys %{$self->{_listen}}) { $self->_drop_immediately($id) }

  # Cleanup temporary cert file
  if (my $cert = $self->{_cert}) { unlink $cert if -w $cert }

  # Cleanup temporary key file
  if (my $key = $self->{_key}) { unlink $key if -w $key }
}

sub new {
  my $class = shift;

  # Build new loop from singleton if possible
  my $loop = $LOOP;
  local $LOOP = undef;
  my $self = $loop ? $loop->new(@_) : $class->SUPER::new(@_);

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
  $self->{_cs}->{$id} = $c;

  # Register callbacks
  for my $name (qw/close error read/) {
    my $cb    = $args->{"on_$name"};
    my $event = "on_$name";
    $self->$event($id => $cb) if $cb;
  }

  # Lookup
  if (!$args->{handle} && (my $address = $args->{address})) {
    $self->lookup(
      $address => sub {
        my $self = shift;
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
  return unless my $c = $self->{_cs}->{$id};
  $c->{timeout} = $timeout and return $self if $timeout;
  return $c->{timeout};
}

sub dns_servers {
  my $self = shift;
  $self = $self->singleton unless ref $self;

  # New servers
  if (@_) {
    @$DNS_SERVERS       = @_;
    $CURRENT_DNS_SERVER = 0;
    return $self;
  }

  # List all
  return @$DNS_SERVERS if wantarray;

  # Current server
  $CURRENT_DNS_SERVER = 0 unless $DNS_SERVERS->[$CURRENT_DNS_SERVER];
  return $DNS_SERVERS->[$CURRENT_DNS_SERVER];
}

sub drop {
  my ($self, $id) = @_;
  $self = $self->singleton unless ref $self;

  # Drop connection gracefully
  if (my $c = $self->{_cs}->{$id}) { return $c->{finish} = 1 }

  # Drop
  return $self->_drop_immediately($id);
}

sub generate_port {

  # Ports
  my $port = 1 . int(rand 10) . int(rand 10) . int(rand 10) . int(rand 10);
  while ($port++ < 30000) {

    # Try port
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

sub idle {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  $self->_add_loop_event(idle => @_);
}

sub is_running {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  $self->{_running};
}

# "Fat Tony is a cancer on this fair city!
#  He is the cancer and I am the… uh… what cures cancer?"
sub listen {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  my $args = ref $_[0] ? $_[0] : {@_};

  croak "IO::Socket::SSL 1.43 required for TLS support"
    if $args->{tls} && !TLS;

  my %options = (
    Listen => $args->{backlog} || SOMAXCONN,
    Proto  => 'tcp',
    Type   => SOCK_STREAM,
    %{$args->{args} || {}}
  );
  my $file = $args->{file};
  my $port = $args->{port} || 3000;

  # File descriptor reuse
  my $reuse = defined $file ? $file : $port;
  $ENV{MOJO_REUSE} ||= '';
  my $fd;
  if ($ENV{MOJO_REUSE} =~ /(?:^|\,)$reuse\:(\d+)/) { $fd = $1 }

  # Refresh listen sockets
  $self->_not_listening;

  # Allow file descriptor inheritance
  local $^F = 1000;

  # Listen on UNIX domain socket
  my $socket;
  if (defined $file) {
    $options{Local} = $file;
    $socket =
      defined $fd
      ? IO::Socket::UNIX->new
      : IO::Socket::UNIX->new(%options)
      or croak "Can't create listen socket: $!";
  }

  # Listen on port
  else {
    $options{LocalAddr} = $args->{address} || '0.0.0.0';
    $options{LocalPort} = $port;
    $options{Proto}     = 'tcp';
    $options{ReuseAddr} = 1;

    # IPv6
    $options{LocalAddr} =~ s/[\[\]]//g;
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';

    $socket = defined $fd ? $class->new : $class->new(%options)
      or croak "Can't create listen socket: $!";
  }

  # File descriptor
  if (defined $fd) {
    $socket->fdopen($fd, 'r')
      or croak "Can't open file descriptor $fd: $!";
  }
  else {
    $fd = fileno $socket;
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
  $self->{_listen}->{$id}      = $c;
  $self->{_fds}->{$fd}         = $id;
  $c->{handle}                 = $socket;
  $self->{_reverse}->{$socket} = $id;

  # TLS
  if ($args->{tls}) {
    my %options = (
      SSL_startHandshake => 0,
      SSL_cert_file      => $args->{tls_cert} || $self->_prepare_cert,
      SSL_key_file       => $args->{tls_key} || $self->_prepare_key,
    );

    # Client certificate verification
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
  $self->{_accepts} = $self->max_accepts if $self->max_accepts;

  return $id;
}

sub local_info {
  my ($self, $id) = @_;

  return {} unless my $c      = $self->{_cs}->{$id};
  return {} unless my $socket = $c->{handle};

  # UNIX domain socket info
  return {path => $socket->hostpath} if $socket->can('hostpath');

  # Info
  return {address => $socket->sockhost, port => $socket->sockport};
}

sub lookup {
  my ($self, $name, $cb) = @_;
  $self = $self->singleton unless ref $self;

  # "localhost"
  return $self->timer(0 => sub { shift->$cb($LOCALHOST) })
    if $name eq 'localhost';

  # IPv4
  $self->resolve(
    $name, 'A',
    sub {
      my ($self, $records) = @_;

      # Success
      my $result = first { $_->[0] eq 'A' } @$records;
      return $self->$cb($result->[1]) if $result;

      # IPv6
      $self->resolve(
        $name, 'AAAA',
        sub {
          my ($self, $records) = @_;

          # Success
          my $result = first { $_->[0] eq 'AAAA' } @$records;
          return $self->$cb($result->[1]) if $result;

          # Pass through
          $self->$cb();
        }
      );
    }
  );
}

sub on_close { shift->_add_event(close => @_) }
sub on_error { shift->_add_event(error => @_) }
sub on_read  { shift->_add_event(read  => @_) }

sub recurring {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  $self->_add_loop_event(timer => pop, after => pop, recurring => time);
}

sub one_tick {
  my ($self, $timeout) = @_;
  $timeout = $self->timeout unless defined $timeout;

  $self->_prepare_listen;
  $self->_prepare_connections;

  my $loop  = $self->_prepare_loop;
  my $r     = $self->{_reverse};
  my $ready = {};

  # KQueue
  if (KQUEUE) {

    # Catch interrupted system call errors
    my @ret;
    my $success = eval { @ret = $loop->kevent(1000 * $timeout); 1 };
    die "KQueue error: $@" if !$success && $@;

    # Events
    for my $kev (@ret) {
      my ($fd, $filter, $flags, $fflags) = @$kev;
      my $id = $self->{_fds}->{$fd};
      next unless $id;
      $ready->{$id} += 2 if $filter == KQUEUE_READ || $flags == KQUEUE_EOF;
      $ready->{$id}++ if $filter == KQUEUE_WRITE;
    }
  }

  # Epoll
  elsif (EPOLL) {
    $loop->poll($timeout);
    $ready->{$r->{$_}} += 2
      for $loop->handles(EPOLL_POLLIN | EPOLL_POLLHUP | EPOLL_POLLERR);
    $ready->{$r->{$_}}++ for $loop->handles(EPOLL_POLLOUT);
  }

  # Poll
  else {
    $loop->poll($timeout);
    $ready->{$r->{$_}} += 2 for $loop->handles(POLLIN | POLLHUP | POLLERR);
    $ready->{$r->{$_}}++ for $loop->handles(POLLOUT);
  }

  # Handle events
  for my $id (keys %$ready) {

    # Read
    if ($ready->{$id} > 1) { $self->_read($id) }

    # Write
    else { $self->_write($id) }
  }

  # Handle timers
  my $timers = $self->_timer;

  # Handle idle events
  unless (keys %$ready || $timers) {
    for my $idle (keys %{$self->{_idle}}) {
      $self->_run_callback('idle', $self->{_idle}->{$idle}->{cb}, $idle);
    }

    # Only kqueue blocks when idle
    usleep 1000000 * $timeout unless KQUEUE;
  }
}

sub handle {
  my ($self, $id) = @_;
  return unless my $c = $self->{_cs}->{$id};
  return $c->{handle};
}

sub remote_info {
  my ($self, $id) = @_;

  return {} unless my $c      = $self->{_cs}->{$id};
  return {} unless my $socket = $c->{handle};

  # UNIX domain socket info
  return {path => $socket->peerpath} if $socket->can('peerpath');

  # Info
  return {address => $socket->peerhost, port => $socket->peerport};
}

sub resolve {
  my ($self, $name, $type, $cb) = @_;
  $self = $self->singleton unless ref $self;

  my $ipv4;
  $ipv4 = 1 if $name =~ $Mojo::URL::IPV4_RE;
  my $ipv6;
  $ipv6 = 1 if IPV6_DNS && $name =~ $Mojo::URL::IPV6_RE;

  my $t      = $DNS_TYPES->{$type};
  my $server = $self->dns_servers;

  # No lookup required or record type not supported
  if (!$server || !$t || ($t ne $DNS_TYPES->{PTR} && ($ipv4 || $ipv6))) {
    $self->timer(0 => sub { $self->$cb([]) });
    return $self;
  }

  # Request
  warn "RESOLVE $type $name ($server)\n" if DEBUG;
  my $timer;
  my $tx = int rand 0x10000;
  my $id = $self->connect(
    address    => $server,
    port       => 53,
    proto      => 'udp',
    on_connect => sub {
      my ($self, $id) = @_;

      # Header (one question with recursion)
      my $req = pack 'nnnnnn', $tx, 0x0100, 1, 0, 0, 0;

      # Reverse
      my @parts = split /\./, $name;
      if ($t eq $DNS_TYPES->{PTR}) {

        # IPv4
        if ($ipv4) { @parts = reverse 'arpa', 'in-addr', @parts }

        # IPv6
        elsif ($ipv6) {
          @parts = reverse 'arpa', 'ip6', split //, unpack 'H32',
            inet_pton(IPV6_AF_INET6, $name);
        }
      }

      # Query (Internet)
      for my $part (@parts) {
        $req .= pack 'C/a*', $part if defined $part;
      }
      $req .= pack 'Cnn', 0, $t, 0x0001;

      $self->write($id => $req);
    },
    on_error => sub {
      my ($self, $id) = @_;

      warn "FAILED $type $name ($server)\n" if DEBUG;
      $CURRENT_DNS_SERVER++;

      $self->drop($timer) if $timer;
      $self->$cb([]);
    },
    on_read => sub {
      my ($self, $id, $chunk) = @_;

      # Cleanup
      $self->drop($id);
      $self->drop($timer) if $timer;

      my @packet = unpack 'nnnnnna*', $chunk;
      warn "ANSWERS $packet[3] ($server)\n" if DEBUG;

      # Wrong response
      return $self->$cb([]) unless $packet[0] eq $tx;

      my $content = $packet[6];

      # Questions
      for (1 .. $packet[2]) {
        my $n;
        do { ($n, $content) = unpack 'C/aa*', $content } while ($n ne '');
        $content = (unpack 'nna*', $content)[2];
      }

      # Answers
      my @answers;
      for (1 .. $packet[3]) {

        # Parse
        (my ($t, $ttl, $a), $content) =
          (unpack 'nnnNn/aa*', $content)[1, 3, 4, 5];
        my @answer = _parse_answer($t, $a, $chunk, $content);

        # No answer
        next unless @answer;

        # Answer
        push @answers, [@answer, $ttl];
        warn "ANSWER $answer[0] $answer[1]\n" if DEBUG;
      }

      $self->$cb(\@answers);
    }
  );

  # Timer
  $timer = $self->timer(
    $self->dns_timeout => sub {
      my $self = shift;

      warn "RESOLVE TIMEOUT ($server)\n" if DEBUG;
      $CURRENT_DNS_SERVER++;

      # Abort
      $self->drop($id);
      $self->$cb([]);
    }
  );

  return $self;
}

sub singleton { $LOOP ||= shift->new(@_) }

sub start {
  my $self = shift;
  $self = $self->singleton unless ref $self;

  # Check if we are already running
  return if $self->{_running};
  $self->{_running} = 1;

  # Mainloop
  $self->one_tick while $self->{_running};

  return $self;
}

sub start_tls {
  my $self = shift;
  my $id   = shift;

  # No TLS support
  unless (TLS) {
    $self->_error($id, 'IO::Socket::SSL 1.43 required for TLS support.');
    return;
  }

  my $args = ref $_[0] ? $_[0] : {@_};
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

  $self->drop($id) and return unless my $c      = $self->{_cs}->{$id};
  $self->drop($id) and return unless my $socket = $c->{handle};

  # Cleanup
  my $fd = fileno $socket;
  delete $self->{_reverse}->{$socket};
  my $writing = delete $c->{writing};
  my $loop    = $self->_prepare_loop;
  if (KQUEUE) {
    $loop->EV_SET($fd, KQUEUE_READ,  KQUEUE_DELETE) if defined $writing;
    $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_DELETE) if $writing;
  }
  else { $loop->remove($socket) if defined $writing }

  # Start
  $self->drop($id) and return
    unless my $new = IO::Socket::SSL->start_SSL($socket, %options);

  # Upgrade
  $c->{handle}              = $new;
  $self->{_reverse}->{$new} = $id;
  $c->{tls_connect}         = 1;
  $self->_writing($id);

  return $id;
}

sub stop {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  delete $self->{_running};
}

sub test {
  my ($self, $id) = @_;

  return unless my $c      = $self->{_cs}->{$id};
  return unless my $socket = $c->{handle};

  # Test
  my $test = $self->{_test} ||= IO::Poll->new;
  $test->mask($socket, POLLIN);
  $test->poll(0);
  my $result = $test->handles(POLLIN | POLLERR | POLLHUP);
  $test->remove($socket);

  return !$result;
}

sub timer {
  my $self = shift;
  $self = $self->singleton unless ref $self;
  $self->_add_loop_event(timer => pop, after => pop, started => time);
}

sub write {
  my ($self, $id, $chunk, $cb) = @_;

  my $c = $self->{_cs}->{$id};
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
  my $socket = $listen->accept or return;
  my $r      = $self->{_reverse};
  my $l      = $self->{_listen}->{$r->{$listen}};

  # New connection
  my $c = {buffer => ''};
  (my $id) = "$c" =~ /0x([\da-f]+)/;
  $self->{_cs}->{$id} = $c;

  # TLS handshake
  weaken $self;
  if (my $tls = $l->{tls}) {
    $tls->{SSL_error_trap} = sub { $self->_error($id, $_[1]) };
    $socket = IO::Socket::SSL->start_SSL($socket, %$tls);
    $c->{tls_accept} = 1;
  }

  $c->{handle} = $socket;
  $r->{$socket} = $id;
  my $fd = fileno $socket;
  $self->{_fds}->{$fd} = $id;

  # Non-blocking
  $socket->blocking(0);

  # Disable Nagle's algorithm
  setsockopt($socket, IPPROTO_TCP, TCP_NODELAY, 1) unless $l->{file};

  # Register callbacks
  for my $name (qw/on_close on_error on_read/) {
    my $cb = $l->{$name};
    $self->$name($id => $cb) if $cb;
  }

  # Add socket to mainloop
  $self->_not_writing($id);

  # Accept limit
  $self->max_connections(0)
    if defined $self->{_accepts} && --$self->{_accepts} == 0;

  # Accept callback
  warn "ACCEPTED $id\n" if DEBUG;
  my $cb = $c->{on_accept} = $l->{on_accept};
  $self->_run_event('accept', $cb, $id) if $cb && !$l->{tls};

  # Stop listening
  $self->_not_listening;
}

sub _add_event {
  my ($self, $event, $id, $cb) = @_;
  return unless my $c = $self->{_cs}->{$id};
  $c->{$event} = $cb if $cb;
  return $self;
}

sub _add_loop_event {
  my $self  = shift;
  my $event = shift;
  my $cb    = shift;

  my $e = {cb => $cb, @_};
  (my $id) = "$e" =~ /0x([\da-f]+)/;
  $self->{"_$event"}->{$id} = $e;

  return $id;
}

sub _connect {
  my ($self, $id, $args) = @_;

  return unless my $c = $self->{_cs}->{$id};

  my %options = (
    Blocking => 0,
    PeerAddr => $args->{address},
    PeerPort => $args->{port} || ($args->{tls} ? 443 : 80),
    Proto    => $args->{proto},
    Type     => $args->{proto} eq 'udp' ? SOCK_DGRAM : SOCK_STREAM,
    %{$args->{args} || {}}
  );

  # Handle
  my $handle;
  unless ($handle = $args->{handle} || $args->{socket}) {

    # IPv6
    $options{PeerAddr} =~ s/[\[\]]//g if $options{PeerAddr};
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';

    # New socket
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
  $self->{_reverse}->{$handle} = $id;

  # Non-blocking
  $handle->blocking(0);

  return unless defined(my $fd = fileno $handle);
  $self->{_fds}->{$fd} = $id;

  # Sockets start writing right away
  $handle->isa('IO::Socket')
    ? $self->_writing($id)
    : $self->_not_writing($id);

  # Start TLS
  if ($args->{tls}) { $self->start_tls($id => $args) }
}

sub _drop_immediately {
  my ($self, $id) = @_;

  # Drop loop events
  for my $event (qw/idle timer/) {
    if ($self->{"_$event"}->{$id}) {
      delete $self->{"_$event"}->{$id};
      return $self;
    }
  }

  # Delete connection
  my $c = delete $self->{_cs}->{$id};
  delete $self->{_reverse}->{$id};

  # Drop listen socket
  if (!$c && ($c = delete $self->{_listen}->{$id})) {

    # Not listening
    return $self unless $self->{_listening};

    # Not listening anymore
    delete $self->{_listening};
  }

  # Delete associated timers
  if (my $t = $c->{connect_timer} || $c->{accept_timer}) {
    $self->_drop_immediately($t);
  }

  # Drop handle
  if (my $handle = $c->{handle}) {
    warn "DISCONNECTED $id\n" if DEBUG;

    # Handle close
    if (my $event = $c->{close}) { $self->_run_event('close', $event, $id) }

    # Remove file descriptor
    return $self unless my $fd = fileno $handle;
    delete $self->{_fds}->{$fd};

    # Remove handle from kqueue
    if (my $loop = $self->_prepare_loop) {
      if (KQUEUE) {
        my $writing = $c->{writing};
        $loop->EV_SET($fd, KQUEUE_READ, KQUEUE_DELETE)
          if defined $writing;
        $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_DELETE) if $writing;
      }

      # Remove handle from poll or epoll
      else { $loop->remove($handle) }
    }

    close $handle;
  }

  return $self;
}

sub _error {
  my ($self, $id, $error) = @_;
  $error ||= 'Unknown error, probably harmless.';
  warn qq/ERROR $id "$error"\n/ if DEBUG;

  # Handle error
  return unless my $c = $self->{_cs}->{$id};
  my $event = $c->{error};
  warn "Unhandled event error: $error" and return unless $event;
  $self->_run_event('error', $event, $id, $error);
  $self->_drop_immediately($id);
}

sub _not_listening {
  my $self = shift;

  # Check loop and unlock
  return unless my $loop = $self->{_loop};
  $self->on_unlock->($self);

  # Remove listen sockets
  my $listen = $self->{_listen} || {};
  for my $lid (keys %$listen) {
    my $socket = $listen->{$lid}->{handle};

    # Remove listen socket from kqueue
    if (KQUEUE) {
      $loop->EV_SET(fileno $socket, KQUEUE_READ, KQUEUE_DELETE);
    }

    # Remove listen socket from poll or epoll
    else { $loop->remove($socket) }
  }

  delete $self->{_listening};
}

sub _not_writing {
  my ($self, $id) = @_;

  return unless my $c = $self->{_cs}->{$id};
  return $c->{read_only} = 1 if length $c->{buffer} || $c->{drain};
  return unless my $handle = $c->{handle};

  # Already not writing
  my $writing = $c->{writing};
  return if defined $writing && !$writing;

  # KQueue
  my $loop = $self->_prepare_loop;
  if (KQUEUE) {
    my $fd = fileno $handle;
    $loop->EV_SET($fd, KQUEUE_READ, KQUEUE_ADD) unless defined $writing;
    $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_DELETE) if $writing;
  }

  # Poll and epoll
  else {
    if ($writing) {
      $loop->remove($handle);
      $writing = undef;
    }

    my $mask = EPOLL ? EPOLL_POLLIN : POLLIN;
    $loop->mask($handle, $mask) unless defined $writing;
  }

  # Not writing anymore
  $c->{writing} = 0;
}

# Answer helper for "resolve"
sub _parse_answer {
  my ($t, $a, $packet, $rest) = @_;

  # A
  if ($t eq $DNS_TYPES->{A}) { return A => join('.', unpack 'C4', $a) }

  # AAAA
  elsif ($t eq $DNS_TYPES->{AAAA}) {
    return AAAA => sprintf('%x:%x:%x:%x:%x:%x:%x:%x', unpack('n*', $a));
  }

  # TXT
  elsif ($t eq $DNS_TYPES->{TXT}) { return TXT => unpack('(C/a*)*', $a) }

  # Offset
  my $offset = length($packet) - length($rest) - length($a);

  # CNAME
  my $type;
  if ($t eq $DNS_TYPES->{CNAME}) { $type = 'CNAME' }

  # MX
  elsif ($t eq $DNS_TYPES->{MX}) {
    $type = 'MX';
    $offset += 2;
  }

  # NS
  elsif ($t eq $DNS_TYPES->{NS}) { $type = 'NS' }

  # PTR
  elsif ($t eq $DNS_TYPES->{PTR}) { $type = 'PTR' }

  # Domain name
  return $type => _parse_name($packet, $offset) if $type;

  # Not supported
  return;
}

# Domain name helper for "resolve"
sub _parse_name {
  my ($packet, $offset) = @_;

  # Elements
  my @elements;
  for (1 .. 128) {

    # Element length
    my $len = ord substr $packet, $offset++, 1;

    # Offset
    if ($len >= 0xc0) {
      $offset = (unpack 'n', substr $packet, ++$offset - 2, 2) & 0x3fff;
    }

    # Element
    elsif ($len) {
      push @elements, substr $packet, $offset, $len;
      $offset += $len;
    }

    # Zero length element (the end)
    else { return join '.', @elements }
  }

  return;
}

sub _prepare_cert {
  my $self = shift;

  my $cert = $self->{_cert};
  return $cert if $cert && -r $cert;

  # Create temporary TLS cert file
  $cert = File::Spec->catfile($ENV{MOJO_TMPDIR} || File::Spec->tmpdir,
    'mojocert.pem');
  my $file = IO::File->new;
  $file->open("> $cert")
    or croak qq/Can't create temporary TLS cert file "$cert"/;
  print $file CERT;

  return $self->{_cert} = $cert;
}

sub _prepare_connections {
  my $self = shift;

  my $cs = $self->{_cs} ||= {};

  # Prepare
  while (my ($id, $c) = each %$cs) {

    # Connection needs to be finished
    if ($c->{finish} && !length $c->{buffer} && !$c->{drain}) {

      # Buffer empty
      $self->_drop_immediately($id);
      next;
    }

    # Read only
    $self->_not_writing($id) if delete $c->{read_only};

    # Last active
    my $time = $c->{active} ||= time;

    # Connection timeout
    $self->_drop_immediately($id) if (time - $time) >= ($c->{timeout} || 15);
  }

  # Graceful shutdown
  $self->stop if $self->max_connections == 0 && keys %$cs == 0;
}

sub _prepare_key {
  my $self = shift;

  my $key = $self->{_key};
  return $key if $key && -r $key;

  # Create temporary TLS key file
  $key = File::Spec->catfile($ENV{MOJO_TMPDIR} || File::Spec->tmpdir,
    'mojokey.pem');
  my $file = IO::File->new;
  $file->open("> $key")
    or croak qq/Can't create temporary TLS key file "$key"/;
  print $file KEY;

  return $self->{_key} = $key;
}

sub _prepare_listen {
  my $self = shift;

  # Already listening or no listen sockets
  return if $self->{_listening};
  my $listen = $self->{_listen} ||= {};
  return unless keys %$listen;

  # Check if we are allowed to listen
  my $i = keys %{$self->{_cs}};
  return unless $i < $self->max_connections;
  return unless $self->on_lock->($self, !$i);

  # Add listen sockets
  my $loop = $self->_prepare_loop;
  for my $lid (keys %$listen) {
    my $socket = $listen->{$lid}->{handle};

    # KQueue
    if (KQUEUE) { $loop->EV_SET(fileno $socket, KQUEUE_READ, KQUEUE_ADD) }

    # Epoll
    elsif (EPOLL) { $loop->mask($socket, EPOLL_POLLIN) }

    # Poll
    else { $loop->mask($socket, POLLIN) }
  }

  $self->{_listening} = 1;
}

sub _prepare_loop {
  my $self = shift;

  # Already initialized
  return $self->{_loop} if $self->{_loop};

  # "kqueue"
  if (KQUEUE) {
    warn "KQUEUE MAINLOOP\n" if DEBUG;
    return $self->{_loop} = IO::KQueue->new;
  }

  # "epoll"
  elsif (EPOLL) {
    warn "EPOLL MAINLOOP\n" if DEBUG;
    $self->{_loop} = IO::Epoll->new;
  }

  # "poll"
  else {
    warn "POLL MAINLOOP\n" if DEBUG;
    $self->{_loop} = IO::Poll->new;
  }

  return $self->{_loop};
}

sub _read {
  my ($self, $id) = @_;

  # Listen socket (new connection)
  if (my $l = $self->{_listen}->{$id}) { $self->_accept($l->{handle}) }

  # Check if everything is ready to read
  my $c = $self->{_cs}->{$id};
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
    return $self->_drop_immediately($id) if $! == ECONNRESET;

    # Read error
    return $self->_error($id, $!);
  }

  # EOF
  return $self->_drop_immediately($id) if $read == 0;

  # Handle read
  if (my $event = $c->{read}) {
    $self->_run_event('read', $event, $id, $buffer);
  }

  # Active
  $c->{active} = time;
}

# Failed callbacks should not kill everything
sub _run_callback {
  my $self  = shift;
  my $event = shift;
  my $cb    = shift;

  my $value = eval { $self->$cb(@_) };
  warn qq/Callback "$event" failed: $@/ if $@;

  return $value;
}

# Failed events should not kill everything
sub _run_event {
  my $self  = shift;
  my $event = shift;
  my $cb    = shift;
  my $id    = shift;

  my $value = eval { $self->$cb($id, @_) };
  if ($@) {
    my $message = qq/Event "$event" failed for connection "$id": $@/;
    $event eq 'error'
      ? ($self->_drop_immediately($id) and warn $message)
      : $self->_error($id, $message);
  }

  return $value;
}

sub _timer {
  my $self = shift;

  # Nothing to do
  return unless my $ts = $self->{_timer};

  # Check timers
  my $count = 0;
  for my $id (keys %$ts) {
    my $t = $ts->{$id};
    my $after = $t->{after} || 0;
    if ($after <= time - ($t->{started} || $t->{recurring})) {
      warn "TIMER $id\n" if DEBUG;

      # Normal timer
      if ($t->{started}) { $self->_drop_immediately($id) }

      # Recurring timer
      elsif ($after && $t->{recurring}) { $t->{recurring} += $after }

      # Handle timer
      if (my $cb = $t->{cb}) {
        $self->_run_callback('timer', $cb);
        $count++ if $t->{started};
      }
    }
  }

  return $count;
}

sub _tls_accept {
  my ($self, $id) = @_;

  # Accepted
  my $c = $self->{_cs}->{$id};
  if ($c->{handle}->accept_SSL) {

    # Handle TLS accept
    delete $c->{tls_accept};
    my $cb = $c->{on_accept};
    $self->_run_event('accept', $cb, $id) if $cb;
    return;
  }

  # Handle error
  $self->_tls_error($id);
}

sub _tls_connect {
  my ($self, $id) = @_;

  # Connected
  my $c = $self->{_cs}->{$id};
  if ($c->{handle}->connect_SSL) {

    # Handle TLS connect
    delete $c->{tls_connect};
    my $cb = $c->{on_connect};
    $self->_run_event('connect', $cb, $id) if $cb;
    return;
  }

  # Handle error
  $self->_tls_error($id);
}

sub _tls_error {
  my ($self, $id) = @_;
  my $error = $IO::Socket::SSL::SSL_ERROR;

  # Reading
  if ($error == TLS_READ) { $self->_not_writing($id) }

  # Writing
  elsif ($error == TLS_WRITE) { $self->_writing($id) }
}

sub _write {
  my ($self, $id) = @_;

  # Check if we are ready for writing
  my $c = $self->{_cs}->{$id};
  return $self->_tls_accept($id)  if $c->{tls_accept};
  return $self->_tls_connect($id) if $c->{tls_connect};
  return unless my $handle = $c->{handle};

  # Connecting
  if ($c->{connecting}) {

    # Cleanup
    delete $c->{connecting};
    my $timer = delete $c->{connect_timer};
    $self->_drop_immediately($timer) if $timer;

    # Disable Nagle's algorithm
    setsockopt $handle, IPPROTO_TCP, TCP_NODELAY, 1;

    # Handle connect
    warn "CONNECTED $id\n" if DEBUG;
    my $cb = $c->{on_connect};
    $self->_run_event('connect', $cb, $id) if $cb && !$c->{tls};
  }

  # Handle drain
  $self->_run_event('drain', delete $c->{drain}, $id)
    if !length $c->{buffer} && $c->{drain};

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

    # Active
    else { $c->{active} = time }

    # Remove written chunk from buffer
    substr $c->{buffer}, 0, $written, '';
  }

  # Not writing
  $self->_not_writing($id) unless exists $c->{drain} || length $c->{buffer};
}

sub _writing {
  my ($self, $id) = @_;

  # Writing again
  my $c = $self->{_cs}->{$id};
  delete $c->{read_only};

  # Already writing or nothing to write to
  return if my $writing = $c->{writing};
  return unless my $handle = $c->{handle};

  # KQueue
  my $loop = $self->_prepare_loop;
  if (KQUEUE) {
    my $fd = fileno $handle;
    $loop->EV_SET($fd, KQUEUE_READ,  KQUEUE_ADD) unless defined $writing;
    $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_ADD) unless $writing;
  }

  # Poll and epoll
  else {
    $loop->remove($handle);
    my $mask = EPOLL ? EPOLL_POLLIN | EPOLL_POLLOUT : POLLIN | POLLOUT;
    $loop->mask($handle, $mask);
  }

  # Connection is writing
  $c->{writing} = 1;
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

=head2 C<dns_timeout>

  my $timeout = $loop->dns_timeout;
  $loop       = $loop->dns_timeout(5);

Maximum time in seconds a C<DNS> lookup can take, defaults to C<3>.
Note that this attribute is EXPERIMENTAL and might change without warning!

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

These options are currently available.

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

=head2 C<dns_servers>

  my @all     = Mojo::IOLoop->dns_servers;
  my @all     = $loop->dns_servers;
  my $current = $loop->dns_servers;
  $loop       = $loop->dns_servers('8.8.8.8', '8.8.4.4');

IP addresses of C<DNS> servers used for non-blocking lookups, defaults to the
value of C<MOJO_DNS_SERVER>, auto detection, C<8.8.8.8> or C<8.8.4.4>.
Note that this method is EXPERIMENTAL and might change without warning!

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

=head2 C<idle>

  my $id = Mojo::IOLoop->idle(sub {...});
  my $id = $loop->idle(sub {...});

Callback to be invoked on every reactor tick if no other events occurred.
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

These options are currently available.

=over 2

=item C<address>

Local address to listen on, defaults to all.

=item C<backlog>

Maximum backlog size, defaults to C<SOMAXCONN>.

=item C<file>

A unix domain socket to listen on.

=item C<on_accept>

Callback to invoke for each accepted connection.

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

Path to the TLS cert file, defaulting to a built in test certificate.

=item C<tls_key>

Path to the TLS key file, defaulting to a built in test key.

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

=head2 C<lookup>

  $loop = Mojo::IOLoop->lookup('mojolicio.us' => sub {...});
  $loop = $loop->lookup('mojolicio.us' => sub {...});

Lookup C<IPv4> or C<IPv6> address for domain.
Note that this method is EXPERIMENTAL and might change without warning!

  $loop->lookup('mojolicio.us' => sub {
    my ($loop, $address) = @_;
    print "Address: $address\n";
  });

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

Callback to be invoked on every reactor tick, this for example allows you to
run multiple reactors next to each other.

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

=head2 C<resolve>

  $loop = Mojo::IOLoop->resolve('mojolicio.us', 'A', sub {...});
  $loop = $loop->resolve('mojolicio.us', 'A', sub {...});

Resolve domain into C<A>, C<AAAA>, C<CNAME>, C<MX>, C<NS>, C<PTR> or C<TXT>
records, C<*> will query for all at once.
Since this is a "stub resolver" it depends on a recursive name server for DNS
resolution.
Note that this method is EXPERIMENTAL and might change without warning!

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
