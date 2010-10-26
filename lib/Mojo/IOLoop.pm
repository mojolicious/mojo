package Mojo::IOLoop;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Errno qw/EAGAIN EWOULDBLOCK/;
use File::Spec;
use IO::File;
use IO::Poll qw/POLLERR POLLHUP POLLIN POLLOUT/;
use IO::Socket;
use Mojo::ByteStream 'b';
use Mojo::URL;
use Scalar::Util 'weaken';
use Socket qw/IPPROTO_TCP TCP_NODELAY/;
use Time::HiRes 'time';

# Debug
use constant DEBUG => $ENV{MOJO_IOLOOP_DEBUG} || 0;

# Epoll support requires IO::Epoll
use constant EPOLL => ($ENV{MOJO_POLL} || $ENV{MOJO_KQUEUE})
  ? 0
  : eval 'use IO::Epoll 0.02 (); 1';
use constant EPOLL_POLLERR => EPOLL ? IO::Epoll::POLLERR() : 0;
use constant EPOLL_POLLHUP => EPOLL ? IO::Epoll::POLLHUP() : 0;
use constant EPOLL_POLLIN  => EPOLL ? IO::Epoll::POLLIN()  : 0;
use constant EPOLL_POLLOUT => EPOLL ? IO::Epoll::POLLOUT() : 0;

# IPv6 support requires IO::Socket::IP
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval 'use IO::Socket::IP 0.04 (); 1';

# KQueue support requires IO::KQueue
use constant KQUEUE => ($ENV{MOJO_POLL} || $ENV{MOJO_EPOLL})
  ? 0
  : eval 'use IO::KQueue 0.34 (); 1';
use constant KQUEUE_ADD    => KQUEUE ? IO::KQueue::EV_ADD()       : 0;
use constant KQUEUE_DELETE => KQUEUE ? IO::KQueue::EV_DELETE()    : 0;
use constant KQUEUE_EOF    => KQUEUE ? IO::KQueue::EV_EOF()       : 0;
use constant KQUEUE_READ   => KQUEUE ? IO::KQueue::EVFILT_READ()  : 0;
use constant KQUEUE_WRITE  => KQUEUE ? IO::KQueue::EVFILT_WRITE() : 0;

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS} ? 0
  : IPV6 ? eval 'use IO::Socket::SSL 1.33 (); 1'
  :        eval 'use IO::Socket::SSL 1.33 "inet4"; 1';
use constant TLS_READ  => TLS ? IO::Socket::SSL::SSL_WANT_READ()  : 0;
use constant TLS_WRITE => TLS ? IO::Socket::SSL::SSL_WANT_WRITE() : 0;

# Windows
use constant WINDOWS => $^O eq 'MSWin32' ? 1 : 0;

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
our $DNS_SERVER = '8.8.8.8';

# Try to detect DNS server
if (-r '/etc/resolv.conf') {
    my $file = IO::File->new;
    $file->open('< /etc/resolv.conf');
    for my $line (<$file>) {
        if ($line =~ /^nameserver\s+(\S+)$/) {

            # New DNS server
            $DNS_SERVER = $1;

            # Debug
            warn qq/DETECTED DNS SERVER ($DNS_SERVER)\n/ if DEBUG;
        }
    }
}

# DNS record types
my $DNS_TYPES = {
    A    => 0x0001,
    AAAA => 0x001c,
    TXT  => 0x0010
};

# "localhost"
our $LOCALHOST = '127.0.0.1';

__PACKAGE__->attr([qw/accept_timeout connect_timeout dns_timeout/] => 3);
__PACKAGE__->attr(dns_server => sub { $ENV{MOJO_DNS_SERVER} || $DNS_SERVER });
__PACKAGE__->attr(max_connections => 1000);
__PACKAGE__->attr([qw/on_idle on_tick/]);
__PACKAGE__->attr(
    [qw/on_lock on_unlock/] => sub {
        sub {1}
    }
);
__PACKAGE__->attr(timeout => '0.25');

# Singleton
our $LOOP;

# DEPRECATED in Comet!
*error_cb  = \&on_error;
*hup_cb    = \&on_hup;
*idle_cb   = \&on_idle;
*lock_cb   = \&on_lock;
*read_cb   = \&on_read;
*tick_cb   = \&on_tick;
*unlock_cb = \&on_unlock;

sub DESTROY {
    my $self = shift;

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

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # TLS check
    return if $args->{tls} && !TLS;

    # Protocol
    $args->{proto} ||= 'tcp';

    # Connection
    my $c = {
        buffer     => b(),
        on_connect => $args->{on_connect}
          || $args->{connect_cb}
          || $args->{cb},
        connecting => 1
    };
    (my $id) = "$c" =~ /0x([\da-f]+)/;
    $self->{_cs}->{$id} = $c;

    # Register callbacks
    for my $name (qw/error hup read/) {
        my $cb = $args->{"on_$name"} || $args->{"${name}_cb"};
        my $event = "on_$name";
        $self->$event($id => $cb) if $cb;
    }

    # Lookup
    if (my $address = $args->{address}) {
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

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Timeout
    $c->{timeout} = $timeout and return $self if $timeout;

    return $c->{timeout};
}

sub drop {
    my ($self, $id) = @_;

    # Connection
    if (my $c = $self->{_cs}->{$id}) { return $c->{finish} = 1 }

    # Drop
    return $self->_drop_immediately($id);
}

sub generate_port {
    my $self = shift;

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

    # Nothing
    return;
}

sub is_running { shift->{_running} }

# Fat Tony is a cancer on this fair city!
# He is the cancer and I am the… uh… what cures cancer?
sub listen {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # TLS check
    croak "IO::Socket::SSL 1.33 required for TLS support"
      if $args->{tls} && !TLS;

    # Options
    my %options = (
        Listen => $args->{queue_size} || SOMAXCONN,
        Proto  => 'tcp',
        Type   => SOCK_STREAM,
        %{$args->{args} || {}}
    );

    # File
    my $file = $args->{file};

    # Port
    my $port = $args->{port} || 3000;

    # File descriptor reuse
    my $reuse = defined $file ? $file : $port;
    $ENV{MOJO_REUSE} ||= '';
    my $fd;
    if ($ENV{MOJO_REUSE} =~ /(?:^|\,)$reuse\:(\d+)/) { $fd = $1 }

    # Connection
    my $c = {
        file => $args->{file} ? 1 : 0,
        on_accept => $args->{on_accept} || $args->{accept_cb} || $args->{cb},
        on_error  => $args->{on_error}  || $args->{error_cb},
        on_hup    => $args->{on_hup}    || $args->{hup_cb},
        on_read   => $args->{on_read}   || $args->{read_cb},
    };
    (my $id) = "$c" =~ /0x([\da-f]+)/;
    $self->{_listen}->{$id} = $c;

    # Listen on UNIX domain socket
    my $socket;
    if (defined $file) {

        # Path
        $options{Local} = $file;

        # Create socket
        $socket =
          defined $fd
          ? IO::Socket::UNIX->new
          : IO::Socket::UNIX->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # Listen on port
    else {

        # Socket options
        $options{LocalAddr} = $args->{address} || (IPV6 ? '::' : '0.0.0.0');
        $options{LocalPort} = $port;
        $options{Proto}     = 'tcp';
        $options{ReuseAddr} = 1;

        # Create socket
        my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
        $socket = defined $fd ? $class->new : $class->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # File descriptor
    if (defined $fd) { $socket->fdopen($fd, 'r') }
    else {
        $fd = fileno $socket;
        $reuse = ",$reuse" if length $ENV{MOJO_REUSE};
        $ENV{MOJO_REUSE} .= "$reuse:$fd";
    }
    $self->{_fds}->{$fd} = $id;

    # Socket
    $c->{socket} = $socket;
    $self->{_reverse}->{$socket} = $id;

    # TLS options
    $c->{tls} = {
        SSL_startHandshake => 0,
        SSL_cert_file      => $args->{tls_cert} || $self->_prepare_cert,
        SSL_key_file       => $args->{tls_key} || $self->_prepare_key
      }
      if $args->{tls};

    return $id;
}

sub local_info {
    my ($self, $id) = @_;

    # Connection
    return {} unless my $c = $self->{_cs}->{$id};

    # Socket
    return {} unless my $socket = $c->{socket};

    # UNIX domain socket info
    return {path => $socket->hostpath} if $socket->can('hostpath');

    # Info
    return {address => $socket->sockhost, port => $socket->sockport};
}

sub lookup {
    my ($self, $name, $cb) = @_;

    # "localhost"
    return $self->$cb($LOCALHOST) if $name eq 'localhost';

    # IPv4
    $self->resolve(
        $name, 'A',
        sub {
            my ($self, $results) = @_;

            # Success
            return $self->$cb($results->[0]) if $results->[0];

            # IPv6
            $self->resolve(
                $name, 'AAAA',
                sub {
                    my ($self, $results) = @_;

                    # Success
                    return $self->$cb($results->[0]) if $results->[0];

                    # Pass through
                    $self->$cb();
                }
            );
        }
    );
}

sub on_error { shift->_add_event('error', @_) }
sub on_hup   { shift->_add_event('hup',   @_) }
sub on_read  { shift->_add_event('read',  @_) }

sub one_tick {
    my ($self, $timeout) = @_;

    # Timeout
    $timeout = $self->timeout unless defined $timeout;

    # Prepare listen sockets
    $self->_prepare_listen;

    # Prepare connections
    $self->_prepare_connections;

    # Loop
    my $loop = $self->_prepare_loop;

    # Reverse map
    my $r = $self->{_reverse};

    # Events
    my (@error, @hup, @read, @write);

    # KQueue
    if (KQUEUE) {

        # Catch interrupted system call errors
        my @ret;
        my $success = eval { @ret = $loop->kevent(1000 * $timeout); 1 };
        die "KQueue error: $@" if !$success && $@;

        # Events
        for my $kev (@ret) {
            my ($fd, $filter, $flags, $fflags) = @$kev;

            # Id
            my $id = $self->{_fds}->{$fd};
            next unless $id;

            # Error
            if ($flags == KQUEUE_EOF) {
                if   ($fflags) { push @error, $id }
                else           { push @hup,   $id }
            }

            # Read
            push @read, $id if $filter == KQUEUE_READ;

            # Write
            push @write, $id if $filter == KQUEUE_WRITE;
        }
    }

    # Epoll
    elsif (EPOLL) {
        $loop->poll($timeout);

        # Read
        push @read, $r->{$_} for $loop->handles(EPOLL_POLLIN);

        # Write
        push @write, $r->{$_} for $loop->handles(EPOLL_POLLOUT);

        # Error
        push @error, $r->{$_} for $loop->handles(EPOLL_POLLERR);

        # HUP
        push @hup, $r->{$_} for $loop->handles(EPOLL_POLLHUP);
    }

    # Poll
    else {
        $loop->poll($timeout);

        # Read
        push @read, $r->{$_} for $loop->handles(POLLIN);

        # Write
        push @write, $r->{$_} for $loop->handles(POLLOUT);

        # Error
        push @error, $r->{$_} for $loop->handles(POLLERR);

        # HUP
        push @hup, $r->{$_} for $loop->handles(POLLHUP);
    }

    # Read
    $self->_read($_) for @read;

    # Write
    $self->_write($_) for @write;

    # Error
    $self->_error($_) for @error;

    # HUP
    $self->_hup($_) for @hup;

    # Timers
    my $timers = $self->_timer;

    # Tick callback
    if (my $cb = $self->on_tick) {
        $self->_run_callback('tick', $cb);
    }

    # Idle callback
    if (my $cb = $self->on_idle) {
        $self->_run_callback('idle', $cb)
          unless @read || @write || @error || @hup || $timers;
    }
}

sub remote_info {
    my ($self, $id) = @_;

    # Connection
    return {} unless my $c = $self->{_cs}->{$id};

    # Socket
    return {} unless my $socket = $c->{socket};

    # UNIX domain socket info
    return {path => $socket->peerpath} if $socket->can('peerpath');

    # Info
    return {address => $socket->peerhost, port => $socket->peerport};
}

sub resolve {
    my ($self, $name, $type, $cb) = @_;

    # Regex
    my $ipv4 = $Mojo::URL::IPV4_RE;
    my $ipv6 = $Mojo::URL::IPV6_RE;

    # Type
    my $t = $DNS_TYPES->{$type};

    # Server
    my $server = $self->dns_server;

    # No lookup required or record type not supported
    unless ($server && $t && $name !~ $ipv4 && $name !~ $ipv6) {
        $self->$cb([]);
        return $self;
    }

    # Debug
    warn "RESOLVE $type $name ($server)\n" if DEBUG;

    # Timer
    my $timer;

    # Transaction
    my $tx = int rand 0x10000;

    # Request
    my $id = $self->connect(
        address    => $server,
        port       => 53,
        proto      => 'udp',
        on_connect => sub {
            my ($self, $id) = @_;

            # Header (one question with recursion)
            my $req = pack 'nnnnnn', $tx, 0x0100, 1, 0, 0, 0;

            # Query (Internet)
            for my $part (split /\./, $name) {
                $req .= pack 'C/a', $part if defined $part;
            }
            $req .= pack 'Cnn', 0, $t, 0x0001;

            # Write
            $self->write($id => $req);
        },
        on_error => sub {
            my ($self, $id) = @_;

            # Debug
            warn "FAILED $type $name ($server)\n" if DEBUG;

            $self->drop($timer) if $timer;
            $self->$cb([]);
        },
        on_read => sub {
            my ($self, $id, $chunk) = @_;

            # Cleanup
            $self->drop($id);
            $self->drop($timer) if $timer;

            # Packet
            my @packet = unpack 'nnnnnnA*', $chunk;

            # Wrong response
            return $self->$cb([]) unless $packet[0] eq $tx;

            # Content
            my $content = $packet[6];

            # Questions
            for (1 .. $packet[2]) {
                my $n;
                do { ($n, $content) = unpack 'C/aA*', $content } while ($n);
                $content = (unpack 'nnA*', $content)[2];
            }

            # Answers
            my @answers;
            for (1 .. $packet[3]) {
                my ($t, $a, $answer);
                ($t, $a, $content) = (unpack 'nnnNn/AA*', $content)[1, 4, 5];

                # A
                if ($t eq $DNS_TYPES->{A}) {
                    $answer = join('.', unpack 'C*', $a);
                }

                # AAAA
                elsif ($t eq $DNS_TYPES->{AAAA}) {
                    $answer = sprintf '%x:%x:%x:%x:%x:%x:%x:%x',
                      unpack('n*', $a);
                }

                # TXT
                elsif ($t eq $DNS_TYPES->{TXT}) {
                    $answer = unpack '(C/a*)*', $a;
                }

                next unless defined $answer;
                push @answers, $answer;

                # Debug
                warn "ANSWER $answer\n" if DEBUG;
            }

            # Done
            $self->$cb(\@answers);
        }
    );

    # Timer
    $timer = $self->timer(
        $self->dns_timeout => sub {
            my $self = shift;

            # Debug
            warn "RESOLVE TIMEOUT ($server)\n" if DEBUG;

            # Disable
            $self->dns_server(undef);

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

    # Already running
    return if $self->{_running};

    # Running
    $self->{_running} = 1;

    # Mainloop
    $self->one_tick while $self->{_running};

    return $self;
}

sub start_tls {
    my $self = shift;
    my $id   = shift;

    # Shortcut
    $self->drop($id) and return unless TLS;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Options
    my %options = (
        SSL_startHandshake => 0,
        Timeout            => $self->connect_timeout,
        %{$args->{tls_args} || {}}
    );

    # Connection
    $self->drop($id) and return unless my $c = $self->{_cs}->{$id};

    # Socket
    $self->drop($id) and return unless my $socket = $c->{socket};
    my $fd = fileno $socket;

    # Cleanup
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
    $c->{socket}              = $new;
    $self->{_reverse}->{$new} = $id;
    $c->{tls_connect}         = 1;
    $self->_writing($id);

    return $id;
}

sub stop { delete shift->{_running} }

sub test {
    my ($self, $id) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Socket
    return unless my $socket = $c->{socket};

    # Test
    my $test = $self->{_test} ||= IO::Poll->new;
    $test->mask($socket, POLLIN);
    $test->poll(0);
    my $result = $test->handles(POLLIN | POLLERR | POLLHUP);
    $test->remove($socket);

    return !$result;
}

sub timer {
    my ($self, $after, $cb) = @_;

    # Timer
    my $timer = {after => $after, cb => $cb, started => time};

    # Add timer
    (my $id) = "$timer" =~ /0x([\da-f]+)/;
    $self->{_ts}->{$id} = $timer;

    return $id;
}

sub write {
    my ($self, $id, $chunk, $cb) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Buffer
    $c->{buffer} = b() unless exists $c->{buffer};
    $c->{buffer}->add_chunk($chunk);

    # UNIX only
    unless (WINDOWS) {

        # Callback
        $c->{drain} = 0 if $cb;

        # Fast write
        $self->_write($id);
    }

    # Callback
    $c->{drain} = $cb if $cb;

    # Writing
    $self->_writing($id) if $cb || $c->{buffer}->size;
}

sub _accept {
    my ($self, $listen) = @_;

    # Accept
    my $socket = $listen->accept or return;

    # Unlock
    $self->on_unlock->($self);

    # Reverse map
    my $r = $self->{_reverse};

    # Listen
    my $l = $self->{_listen}->{$r->{$listen}};

    # Weaken
    weaken $self;

    # Connection
    my $c = {
        accepting => 1,
        buffer    => b(),
    };
    (my $id) = "$c" =~ /0x([\da-f]+)/;
    $self->{_cs}->{$id} = $c;

    # TLS handshake
    my $tls = $l->{tls};
    if ($tls) {
        $tls->{SSL_error_trap} = sub { $self->_drop_immediately(shift) };
        $socket = IO::Socket::SSL->start_SSL($socket, %$tls);
    }
    $c->{tls_accept} = 1 if $tls;
    $c->{socket}     = $socket;
    $r->{$socket}    = $id;

    # Timeout
    $c->{accept_timer} =
      $self->timer($self->accept_timeout, =>
          sub { shift->_error($id, 'Accept timeout.') });

    # Disable Nagle's algorithm
    setsockopt($socket, IPPROTO_TCP, TCP_NODELAY, 1) unless $l->{file};

    # File descriptor
    my $fd = fileno $socket;
    $self->{_fds}->{$fd} = $id;

    # Register callbacks
    for my $name (qw/on_error on_hup on_read/) {
        my $cb = $l->{$name};
        $self->$name($id => $cb) if $cb;
    }

    # Accept callback
    my $cb = $l->{on_accept};
    $self->_run_event('accept', $cb, $id) if $cb;

    # Remove listen sockets
    $listen = $self->{_listen} || {};
    my $loop = $self->{_loop};
    for my $lid (keys %$listen) {
        my $socket = $listen->{$lid}->{socket};

        # Remove listen socket from kqueue
        if (KQUEUE) {
            $loop->EV_SET(fileno $socket, KQUEUE_READ, KQUEUE_DELETE);
        }

        # Remove listen socket from poll or epoll
        else { $loop->remove($socket) }
    }

    # Not listening anymore
    delete $self->{_listening};
}

sub _add_event {
    my ($self, $event, $id, $cb) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Add event callback
    $c->{$event} = $cb if $cb;

    return $self;
}

sub _connect {
    my ($self, $id, $args) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Options
    my %options = (
        PeerAddr => $args->{address},
        PeerPort => $args->{port} || ($args->{tls} ? 443 : 80),
        Proto    => $args->{proto},
        Type     => $args->{proto} eq 'udp' ? SOCK_DGRAM : SOCK_STREAM,
        %{$args->{args} || {}}
    );

    # Socket
    my $class = IPV6 ? 'IO::Socket::IP' : 'IO::Socket::INET';
    return unless my $socket = $args->{socket} || $class->new(%options);
    $c->{socket} = $socket;
    $self->{_reverse}->{$socket} = $id;

    # File descriptor
    return unless defined(my $fd = fileno $socket);
    $self->{_fds}->{$fd} = $id;

    # Non-blocking
    $socket->blocking(0);

    # Disable Nagle's algorithm
    setsockopt $socket, IPPROTO_TCP, TCP_NODELAY, 1;

    # Timer
    $c->{connect_timer} =
      $self->timer($self->connect_timeout =>
          sub { shift->_error($id, 'Connect timeout.') });

    # Add socket to poll
    $self->_not_writing($id);

    # Start TLS
    if ($args->{tls}) { $self->start_tls($id => $args) }
}

sub _drop_immediately {
    my ($self, $id) = @_;

    # Drop timer
    if ($self->{_ts}->{$id}) {

        # Drop
        delete $self->{_ts}->{$id};
        return $self;
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

    # Drop socket
    if (my $socket = $c->{socket}) {

        # Remove file descriptor
        return unless my $fd = fileno $socket;
        delete $self->{_fds}->{$fd};

        # Remove socket from kqueue
        if (my $loop = $self->_prepare_loop) {
            if (KQUEUE) {

                # Writing
                my $writing = $c->{writing};
                $loop->EV_SET($fd, KQUEUE_READ, KQUEUE_DELETE)
                  if defined $writing;
                $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_DELETE) if $writing;
            }

            # Remove socket from poll or epoll
            else { $loop->remove($socket) }
        }

        # Close socket
        close $socket;
    }

    return $self;
}

sub _error {
    my ($self, $id, $error) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Get error callback
    my $event = $c->{error};

    # Cleanup
    $self->_drop_immediately($id);

    # Error
    $error ||= 'Unknown error, probably harmless.';

    # No event
    warn "Unhandled event error: $error" and return unless $event;

    # Error callback
    $self->_run_event('error', $event, $id, $error);
}

sub _hup {
    my ($self, $id) = @_;

    # Get hup callback
    my $event = $self->{_cs}->{$id}->{hup};

    # Cleanup
    $self->_drop_immediately($id);

    # No event
    return unless $event;

    # HUP callback
    $self->_run_event('hup', $event, $id);
}

sub _not_writing {
    my ($self, $id) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Chunk still in buffer
    if (my $buffer = $c->{buffer}) {
        return $c->{read_only} = 1 if $buffer->size;
    }

    # Socket
    return unless my $socket = $c->{socket};

    # Writing
    my $writing = $c->{writing};
    return if defined $writing && !$writing;

    # KQueue
    my $loop = $self->_prepare_loop;
    if (KQUEUE) {
        my $fd = fileno $socket;

        # Writing
        $loop->EV_SET($fd, KQUEUE_READ, KQUEUE_ADD) unless defined $writing;
        $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_DELETE) if $writing;
    }

    # Poll and epoll
    else {

        # Not writing anymore
        if ($writing) {
            $loop->remove($socket);
            $writing = undef;
        }

        # Reading
        my $mask = EPOLL ? EPOLL_POLLIN : POLLIN;
        $loop->mask($socket, $mask) unless defined $writing;
    }

    # Not writing anymore
    $c->{writing} = 0;
}

sub _prepare_accept {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Connected
    return unless $c->{socket}->connected;

    # Accepted
    delete $c->{accepting};

    # Remove timeout
    $self->_drop_immediately(delete $c->{accept_timer});

    # Non-blocking
    $c->{socket}->blocking(0);

    # Add socket to poll
    $self->_not_writing($id);
}

sub _prepare_cert {
    my $self = shift;

    # Shortcut
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

sub _prepare_connect {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Not yet connected
    return unless my $socket = $c->{socket};
    if ($socket->can('connected')) { return unless $socket->connected }

    # Connected
    delete $c->{connecting};

    # Remove timeout
    $self->_drop_immediately(delete $c->{connect_timer});

    # Connect callback
    my $cb = $c->{on_connect};
    $self->_run_event('connect', $cb, $id) if $cb;
}

sub _prepare_connections {
    my $self = shift;

    # Connections
    my $cs = $self->{_cs} ||= {};

    # Prepare
    while (my ($id, $c) = each %$cs) {

        # Accepting
        $self->_prepare_accept($id) if $c->{accepting};

        # Connecting
        $self->_prepare_connect($id) if $c->{connecting};

        # Connection needs to be finished
        if ($c->{finish}) {

            # Buffer empty
            unless (defined $c->{buffer} && $c->{buffer}->size) {
                $self->_drop_immediately($id);
                next;
            }
        }

        # Read only
        $self->_not_writing($id) if delete $c->{read_only};

        # Last active
        my $time = $c->{active} ||= time;

        # HUP
        $self->_hup($id) if (time - $time) >= ($c->{timeout} || 15);
    }

    # Graceful shutdown
    $self->stop if $self->max_connections == 0 && keys %$cs == 0;
}

sub _prepare_key {
    my $self = shift;

    # Shortcut
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

    # Loop
    my $loop = $self->_prepare_loop;

    # Already listening
    return if $self->{_listening};

    # Listen sockets
    my $listen = $self->{_listen} ||= {};
    return unless keys %$listen;

    # Connections
    my $i = keys %{$self->{_cs}};
    return unless $i < $self->max_connections;

    # Lock
    return unless $self->on_lock->($self, !$i);

    # Add listen sockets
    for my $lid (keys %$listen) {
        my $socket = $listen->{$lid}->{socket};

        # KQueue
        if (KQUEUE) { $loop->EV_SET(fileno $socket, KQUEUE_READ, KQUEUE_ADD) }

        # Epoll
        elsif (EPOLL) { $loop->mask($socket, EPOLL_POLLIN) }

        # Poll
        else { $loop->mask($socket, POLLIN) }
    }

    # Listening
    $self->{_listening} = 1;
}

sub _prepare_loop {
    my $self = shift;

    # Already initialized
    return $self->{_loop} if $self->{_loop};

    # "kqueue"
    if (KQUEUE) { $self->{_loop} = IO::KQueue->new }

    # "epoll"
    elsif (EPOLL) { $self->{_loop} = IO::Epoll->new }

    # "poll"
    else { $self->{_loop} = IO::Poll->new }

    return $self->{_loop};
}

sub _read {
    my ($self, $id) = @_;

    # Listen socket (new connection)
    if (my $l = $self->{_listen}->{$id}) { $self->_accept($l->{socket}) }

    # Connection
    my $c = $self->{_cs}->{$id};

    # TLS accept
    return $self->_tls_accept($id) if $c->{tls_accept};

    # TLS connect
    return $self->_tls_connect($id) if $c->{tls_connect};

    # Socket
    return unless defined(my $socket = $c->{socket});

    # Read as much as possible
    my $read = $socket->sysread(my $buffer, 4194304, 0);

    # Error
    unless (defined $read) {

        # Retry
        return if $! == EAGAIN || $! == EWOULDBLOCK;

        # Read error
        return $self->_error($id, $!);
    }

    # EOF
    return $self->_hup($id) if $read == 0;

    # Callback
    my $event = $c->{read};
    $self->_run_event('read', $event, $id, $buffer) if $event;

    # Active
    $c->{active} = time;
}

# Failed callbacks should not kill everything
sub _run_callback {
    my $self  = shift;
    my $event = shift;
    my $cb    = shift;

    # Invoke callback
    my $value = eval { $self->$cb(@_) };

    # Callback error
    warn qq/Callback "$event" failed: $@/ if $@;

    return $value;
}

# Failed events should not kill everything
sub _run_event {
    my $self  = shift;
    my $event = shift;
    my $cb    = shift;
    my $id    = shift;

    # Invoke callback
    my $value = eval { $self->$cb($id, @_) };

    # Event error
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

    # Timers
    return unless my $ts = $self->{_ts};

    # Check
    my $count = 0;
    for my $id (keys %$ts) {
        my $t = $ts->{$id};

        # Timer
        my $after = $t->{after} || 0;
        if ($after <= time - $t->{started}) {

            # Drop
            $self->_drop_immediately($id);

            # Callback
            if (my $cb = $t->{cb}) {
                $self->_run_callback('timer', $cb);
                $count++;
            }
        }
    }

    return $count;
}

sub _tls_accept {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Connected
    if ($c->{socket}->accept_SSL) {
        delete $c->{tls_accept};
        return;
    }

    # Error
    my $error = $IO::Socket::SSL::SSL_ERROR;

    # Reading
    if ($error == TLS_READ) { $self->_not_writing($id) }

    # Writing
    elsif ($error == TLS_WRITE) { $self->_writing($id) }

    # Real error
    else { $self->_error($id, $error) }
}

sub _tls_connect {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Connected
    if ($c->{socket}->connect_SSL) {
        delete $c->{tls_connect};
        return;
    }

    # Error
    my $error = $IO::Socket::SSL::SSL_ERROR;

    # Reading
    if ($error == TLS_READ) { $self->_not_writing($id) }

    # Writing
    elsif ($error == TLS_WRITE) { $self->_writing($id) }

    # Real error
    else { $self->_error($id, $error) }
}

sub _write {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # TLS accept
    return $self->_tls_accept($id) if $c->{tls_accept};

    # TLS connect
    return $self->_tls_connect($id) if $c->{tls_connect};

    # Connect has just completed
    return if $c->{connecting};

    # Buffer
    my $buffer = $c->{buffer};

    # Socket
    return unless my $socket = $c->{socket};
    return unless $socket->connected;

    # Callback
    if ($c->{drain} && (my $event = delete $c->{drain})) {
        $self->_run_event('drain', $event, $id);
    }

    # Nothing to write
    return unless $buffer->size;

    # Write
    my $written = $socket->syswrite($buffer->to_string);

    # Error
    unless (defined $written) {

        # Retry
        return if $! == EAGAIN || $! == EWOULDBLOCK;

        # Write error
        return $self->_error($id, $!);
    }

    # Remove written chunk from buffer
    $buffer->remove($written);

    # Not writing
    $self->_not_writing($id) unless exists $c->{drain} || $buffer->size;

    # Active
    $c->{active} = time if $written;
}

sub _writing {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Writing again
    delete $c->{read_only};

    # Writing
    return if my $writing = $c->{writing};

    # Socket
    return unless my $socket = $c->{socket};

    # KQueue
    my $loop = $self->_prepare_loop;
    if (KQUEUE) {
        my $fd = fileno $socket;

        # Writing
        $loop->EV_SET($fd, KQUEUE_READ,  KQUEUE_ADD) unless defined $writing;
        $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_ADD) unless $writing;
    }

    # Poll and epoll
    else {

        # Cleanup
        $loop->remove($socket);

        # Writing
        my $mask = EPOLL ? EPOLL_POLLIN | EPOLL_POLLOUT : POLLIN | POLLOUT;
        $loop->mask($socket, $mask);
    }

    # Writing
    $c->{writing} = 1;
}

1;
__END__

=head1 NAME

Mojo::IOLoop - Minimalistic Reactor For Non-Blocking TCP Clients And Servers

=head1 SYNOPSIS

    use Mojo::IOLoop;

    # Create loop
    my $loop = Mojo::IOLoop->new;

    # Listen on port 3000
    $loop->listen(
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
    my $id = $loop->connect(
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
    $loop->timer(5 => sub {
        my $self = shift;
        $self->drop($id);
    });

    # Start and stop loop
    $loop->start;
    $loop->stop;

=head1 DESCRIPTION

L<Mojo::IOLoop> is a very minimalistic reactor that has been reduced to the
absolute minimal feature set required to build solid and scalable
non-blocking TCP clients and servers.

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

=head2 C<dns_server>

    my $server = $loop->dns_server;
    $loop      = $loop->dns_server('8.8.8.8');

C<DNS> server to use for non-blocking lookups, defaults to the value of
C<MOJO_DNS_SERVER>, auto detection or C<8.8.8.8>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<dns_timeout>

    my $timeout = $loop->dns_timeout;
    $loop       = $loop->dns_timeout(5);

Maximum time in seconds a C<DNS> lookup can take, defaults to C<3>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<max_connections>

    my $max = $loop->max_connections;
    $loop   = $loop->max_connections(1000);

The maximum number of connections this loop is allowed to handle before
stopping to accept new incoming connections, defaults to C<1000>.
Setting the value to C<0> will make this loop stop accepting new connections
and allow it to shutdown gracefully without interrupting existing
connections.

=head2 C<on_idle>

    my $cb = $loop->on_idle;
    $loop  = $loop->on_idle(sub {...});

Callback to be invoked on every reactor tick if no events occurred.
Note that this attribute is EXPERIMENTAL and might change without warning!

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

=head2 C<on_tick>

    my $cb = $loop->on_tick;
    $loop  = $loop->on_tick(sub {...});

Callback to be invoked on every reactor tick, this for example allows you to
run multiple reactors next to each other.

    my $loop2 = Mojo::IOLoop->new(timeout => 0);
    Mojo::IOLoop->singleton->on_tick(sub { $loop2->one_tick });

Note that the loop timeout can be changed dynamically at any time to adjust
responsiveness.

=head2 C<on_unlock>

    my $cb = $loop->on_unlock;
    $loop  = $loop->on_unlock(sub {...});

A callback to free the accept lock, used to sync multiple server processes.
Note that exceptions in this callback are not captured.

=head2 C<timeout>

    my $timeout = $loop->timeout;
    $loop       = $loop->timeout(5);

Maximum time in seconds our loop waits for new events to happen, defaults to
C<0.25>.
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

    my $id = $loop->connect(
        address => '127.0.0.1',
        port    => 3000
    );
    my $id = $loop->connect({
        address => '[::1]',
        port    => 443,
        tls     => 1
    });

Open a TCP connection to a remote host, IPv6 will be used automatically if
available.
Note that IPv6 support depends on L<IO::Socket::IP> and TLS support on
L<IO::Socket::SSL>.

These options are currently available.

=over 4

=item C<address>

Address or host name of the peer to connect to.

=item C<on_connect>

Callback to be invoked once the connection is established.

=item C<on_error>

Callback to be invoked if an error event happens on the connection.

=item C<on_hup>

Callback to be invoked if the connection gets closed.

=item C<on_read>

Callback to be invoked if new data arrives on the connection.

=item C<port>

Port to connect to.

=item C<proto>

Protocol to use, defaults to C<tcp>.

=item C<socket>

Use an already prepared socket handle.

=item C<tls>

Enable TLS.

=back

=head2 C<connection_timeout>

    my $timeout = $loop->connection_timeout($id);
    $loop       = $loop->connection_timeout($id => 45);

Maximum amount of time in seconds a connection can be inactive before being
dropped.

=head2 C<drop>

    $loop = $loop->drop($id);

Drop a connection, listen socket or timer.
Connections will be dropped gracefully by allowing them to finish writing all
data in it's write buffer.

=head2 C<generate_port>

    my $port = $loop->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 C<is_running>

    my $running = $loop->is_running;

Check if loop is running.

    exit unless Mojo::IOLoop->singleton->is_running;

=head2 C<listen>

    my $id = $loop->listen(port => 3000);
    my $id = $loop->listen({port => 3000});
    my $id = $loop->listen(file => '/foo/myapp.sock');
    my $id = $loop->listen(
        port     => 443,
        tls      => 1,
        tls_cert => '/foo/server.cert',
        tls_key  => '/foo/server.key'
    );

Create a new listen socket, IPv6 will be used automatically if available.
Note that IPv6 support depends on L<IO::Socket::IP> and TLS support on
L<IO::Socket::SSL>.

These options are currently available.

=over 4

=item C<address>

Local address to listen on, defaults to all.

=item C<file>

A unix domain socket to listen on.

=item C<on_accept>

Callback to invoke for each accepted connection.

=item C<on_error>

Callback to be invoked if an error event happens on the connection.

=item C<on_hup>

Callback to be invoked if the connection gets closed.

=item C<on_read>

Callback to be invoked if new data arrives on the connection.

=item C<port>

Port to listen on.

=item C<queue_size>

Maximum queue size, defaults to C<SOMAXCONN>.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS cert file, defaulting to a built in test certificate.

=item C<tls_key>

Path to the TLS key file, defaulting to a built in test key.

=back

=head2 C<local_info>

    my $info = $loop->local_info($id);

Get local information about a connection.

    my $address = $info->{address};

These values are to be expected in the returned hash reference.

=over 4

=item C<address>

The local address.

=item C<port>

The local port.

=back

=head2 C<lookup>

    $loop = $loop->lookup('mojolicio.us' => sub {...});

Lookup C<IPv4> or C<IPv6> address for domain.
Note that this method is EXPERIMENTAL and might change without warning!

    $loop->lookup('mojolicio.us' => sub {
        my ($loop, $address) = @_;
        print "Address: $address\n";
    });

=head2 C<on_error>

    $loop = $loop->on_error($id => sub {...});

Callback to be invoked if an error event happens on the connection.

=head2 C<on_hup>

    $loop = $loop->on_hup($id => sub {...});

Callback to be invoked if the connection gets closed.

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

=head2 C<remote_info>

    my $info = $loop->remote_info($id);

Get remote information about a connection.

    my $address = $info->{address};

These values are to be expected in the returned hash reference.

=over 4

=item C<address>

The remote address.

=item C<port>

The remote port.

=back

=head2 C<resolve>

    $loop = $loop->resolve('mojolicio.us', 'A', sub {...});

Resolve domain into C<A>, C<AAAA> or C<TXT> records.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<singleton>

    my $loop = Mojo::IOLoop->singleton;

The global loop object, used to access a single shared loop instance from
everywhere inside the process.

=head2 C<start>

    $loop->start;

Start the loop, this will block until C<stop> is called or return immediately
if the loop is already running.

=head2 C<start_tls>

    my $id = $loop->start_tls($id);

Start new TLS connection inside old connection.
Note that TLS support depends on L<IO::Socket::SSL>.

=head2 C<stop>

    $loop->stop;

Stop the loop immediately, this will not interrupt any existing connections
and the loop can be restarted by running C<start> again.

=head2 C<test>

    my $success = $loop->test($id);

Test for errors and garbage bytes on the connection.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<timer>

    my $id = $loop->timer(5 => sub {...});
    my $id = $loop->timer(0.25 => sub {...});

Create a new timer, invoking the callback afer a given amount of seconds.

=head2 C<write>

    $loop->write($id => 'Hello!');
    $loop->write($id => 'Hello!', sub {...});

Write data to connection, the optional drain callback will be invoked once
all data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
