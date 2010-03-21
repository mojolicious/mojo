# Copyright (C) 2008-2010, Sebastian Riedel.

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
use Mojo::ByteStream;
use Socket qw/IPPROTO_TCP TCP_NODELAY/;

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 8192;

# Epoll support requires IO::Epoll
use constant EPOLL => ($ENV{MOJO_POLL} || $ENV{MOJO_KQUEUE})
  ? 0
  : eval { require IO::Epoll; 1 };
use constant EPOLL_POLLERR => EPOLL ? IO::Epoll::POLLERR() : 0;
use constant EPOLL_POLLHUP => EPOLL ? IO::Epoll::POLLHUP() : 0;
use constant EPOLL_POLLIN  => EPOLL ? IO::Epoll::POLLIN()  : 0;
use constant EPOLL_POLLOUT => EPOLL ? IO::Epoll::POLLOUT() : 0;

# IPv6 support requires IO::Socket::INET6
use constant IPV6 => $ENV{MOJO_NO_IPV6}
  ? 0
  : eval { require IO::Socket::INET6; 1 };

# KQueue support requires IO::KQueue
use constant KQUEUE => ($ENV{MOJO_POLL} || $ENV{MOJO_EPOLL})
  ? 0
  : eval { require IO::KQueue; 1 };
use constant KQUEUE_ADD    => KQUEUE ? IO::KQueue::EV_ADD()       : 0;
use constant KQUEUE_DELETE => KQUEUE ? IO::KQueue::EV_DELETE()    : 0;
use constant KQUEUE_EOF    => KQUEUE ? IO::KQueue::EV_EOF()       : 0;
use constant KQUEUE_READ   => KQUEUE ? IO::KQueue::EVFILT_READ()  : 0;
use constant KQUEUE_WRITE  => KQUEUE ? IO::KQueue::EVFILT_WRITE() : 0;

# TLS support requires IO::Socket::SSL
use constant TLS => $ENV{MOJO_NO_TLS}
  ? 0
  : eval { require IO::Socket::SSL; 1 };

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

__PACKAGE__->attr(
    [qw/lock_cb tick_cb unlock_cb/] => sub {
        sub {1}
    }
);
__PACKAGE__->attr([qw/accept_timeout connect_timeout/] => 5);
__PACKAGE__->attr(max_connections                      => 1000);
__PACKAGE__->attr(timeout                              => '0.25');

# Singleton
our $LOOP;

sub DESTROY {
    my $self = shift;

    # Cleanup temporary cert file
    if (my $cert = $self->{_cert}) { unlink $cert if -w $cert }

    # Cleanup temporary key file
    if (my $key = $self->{_key}) { unlink $key if -w $key }
}

sub new {
    my $self = shift->SUPER::new(@_);

    # Ignore PIPE signal
    $SIG{PIPE} = 'IGNORE';

    return $self;
}

sub connect {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Options (TLS handshake only works blocking)
    my %options = (
        Blocking => $args->{tls} ? 1 : 0,
        PeerAddr => $args->{address},
        PeerPort => $args->{port} || ($args->{tls} ? 443 : 80),
        Proto    => 'tcp',
        Type     => SOCK_STREAM
    );

    # New connection
    my $class = IPV6 ? 'IO::Socket::INET6' : 'IO::Socket::INET';
    my $socket = $class->new(%options) or return;
    my $id = "$socket";

    # Add connection
    my $c = $self->{_cs}->{$id} = {
        buffer     => Mojo::ByteStream->new,
        connect_cb => $args->{cb},
        connecting => 1,
        socket     => $socket
    };

    # Start TLS
    if ($args->{tls}) {
        my $old = $id;
        $id = $self->start_tls($id => $args);
        $self->drop($old) && return unless $id;
    }

    # Non blocking
    $socket->blocking(0);

    # Disable Nagle's algorithm
    setsockopt $socket, IPPROTO_TCP, TCP_NODELAY, 1;

    # Timeout
    $c->{connect_timer} =
      $self->timer($self->connect_timeout =>
          sub { shift->_error($id, 'Connect timeout.') });

    # File descriptor
    my $fd = fileno $socket;
    $self->{_fds}->{$fd} = $id;

    # Add socket to poll
    $self->writing($id);

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
    if (my $c = $self->{_cs}->{$id}) {

        # Protected connection
        my $protected = $c->{protected} || 0;

        # Finish connection once buffer is empty
        if (my $buffer = $c->{buffer}) { $protected = 1 if $buffer->size }

        # Delay connection drop
        if ($protected) {
            $c->{finish} = 1;
            return $self;
        }
    }

    # Drop
    return $self->_drop_immediately($id);
}

sub error_cb { shift->_add_event('error', @_) }

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

sub hup_cb { shift->_add_event('hup', @_) }

sub is_running { shift->{_running} }

# Fat Tony is a cancer on this fair city!
# He is the cancer and I am the… uh… what cures cancer?
sub listen {
    my $self = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Options (TLS handshake only works blocking)
    my %options = (
        Blocking => $args->{tls} ? 1 : 0,
        Listen => $args->{queue_size} || SOMAXCONN,
        Type => SOCK_STREAM
    );

    # Listen on UNIX domain socket
    my $socket;
    if (my $file = $args->{file}) {

        # Path
        $options{Local} = $file;

        # Create socket
        $socket = IO::Socket::UNIX->new(%options)
          or croak "Can't create listen socket: $!";
    }

    # Listen on port
    else {

        # Socket options
        my $address = $args->{address};
        $options{LocalAddr} = $address if $address;
        $options{LocalPort} = $args->{port} || 3000;
        $options{Proto}     = 'tcp';
        $options{ReuseAddr} = 1;

        # TLS options
        if ($args->{tls}) {
            $options{SSL_cert_file} = $args->{tls_cert}
              || $self->_prepare_cert;
            $options{SSL_key_file} = $args->{tls_key} || $self->_prepare_key;
        }

        # Create socket
        my $class = IPV6 ? 'IO::Socket::INET6' : 'IO::Socket::INET';
        $class = 'IO::Socket::SSL' if TLS && $args->{tls};
        $socket = $class->new(%options)
          or croak "Can't create listen socket: $!";
    }
    my $id = "$socket";

    # Add listen socket
    $self->{_listen}->{$id} =
      {cb => $args->{cb}, file => $args->{file} ? 1 : 0, socket => $socket};

    # File descriptor
    my $fd = fileno $socket;
    $self->{_fds}->{$fd} = $id;

    return $id;
}

sub local_info {
    my ($self, $id) = @_;

    # Connection
    return {} unless my $c = $self->{_cs}->{$id};

    # Socket
    return {} unless my $socket = $c->{socket};

    # Info
    return {address => $socket->sockhost, port => $socket->sockport};
}

sub not_writing {
    my ($self, $id) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Activity
    $self->_activity($id);

    # Chunk still in buffer or protected
    my $protected = $c->{protected} || 0;
    if (my $buffer = $c->{buffer}) { $protected = 1 if $buffer->size }
    return $c->{read_only} = 1 if $protected;

    # Socket
    return unless my $socket = $c->{socket};

    # KQueue
    my $loop = $self->{_loop} ||= $self->_build_loop;
    if (KQUEUE) {
        my $fd = fileno $socket;

        # Writing
        my $writing = $c->{writing};
        $loop->EV_SET($fd, KQUEUE_READ, KQUEUE_ADD) unless defined $writing;
        $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_DELETE) if $writing;

        # Not writing anymore
        $c->{writing} = 0;
    }

    # Epoll
    elsif (EPOLL) { $loop->mask($socket, EPOLL_POLLIN) }

    # Poll
    else { $loop->mask($socket, POLLIN) }
}

sub one_tick {
    my $self = shift;

    # Listening
    if (!$self->{_listening} && $self->_should_listen) {

        # Add listen sockets
        my $listen = $self->{_listen} || {};
        my $loop = $self->{_loop};
        for my $lid (keys %$listen) {
            my $socket = $listen->{$lid}->{socket};
            my $fd     = fileno $socket;

            # KQueue
            $loop->EV_SET($fd, KQUEUE_READ, KQUEUE_ADD) if KQUEUE;

            # Epoll
            $loop->mask($socket, EPOLL_POLLIN) if EPOLL;

            # Poll
            $loop->mask($socket, POLLIN) unless KQUEUE || EPOLL;
        }

        # Listening
        $self->{_listening} = 1;
    }

    # Prepare
    return if $self->_prepare;

    # Events
    my (@error, @hup, @read, @write);

    # KQueue
    my $loop = $self->{_loop};
    if (KQUEUE) {

        # Catch interrupted system call errors
        my @ret;
        eval { @ret = $loop->kevent(1000 * $self->timeout) };
        die "KQueue error: $@" if $@;

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
        $loop->poll($self->timeout);

        # Read
        push @read, $_ for $loop->handles(EPOLL_POLLIN);

        # Write
        push @write, $_ for $loop->handles(EPOLL_POLLOUT);

        # Error
        push @error, $_ for $loop->handles(EPOLL_POLLERR);

        # HUP
        push @hup, $_ for $loop->handles(EPOLL_POLLHUP);
    }

    # Poll
    else {
        $loop->poll($self->timeout);

        # Read
        push @read, $_ for $loop->handles(POLLIN);

        # Write
        push @write, $_ for $loop->handles(POLLOUT);

        # Error
        push @error, $_ for $loop->handles(POLLERR);

        # HUP
        push @hup, $_ for $loop->handles(POLLHUP);
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
    $self->_timer;

    # Tick callback
    my $cb = $self->tick_cb;
    $self->_run_callback('tick', $cb) if $cb;
}

sub read_cb { shift->_add_event('read', @_) }

sub remote_info {
    my ($self, $id) = @_;

    # Connection
    return {} unless my $c = $self->{_cs}->{$id};

    # Socket
    return {} unless my $socket = $c->{socket};

    # Info
    return {address => $socket->peerhost, port => $socket->peerport};
}

sub singleton { $LOOP ||= shift->new(@_) }

sub start {
    my $self = shift;

    # Already running
    return if $self->{_running};

    # Running
    $self->{_running} = 1;

    # Loop
    $self->{_loop} ||= $self->_build_loop;

    # Mainloop
    $self->one_tick while $self->{_running};

    return $self;
}

sub start_tls {
    my $self = shift;
    my $id   = shift;

    # Shortcut
    return unless TLS;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # TLS certificate verification
    my %options = (Timeout => $self->connect_timeout);
    if ($args->{tls_ca_file}) {
        $options{SSL_ca_file}         = $args->{tls_ca_file};
        $options{SSL_verify_mode}     = 0x01;
        $options{SSL_verify_callback} = $args->{tls_verify_cb};
    }

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Socket
    return unless my $socket = $c->{socket};

    # Start
    $socket->blocking(1);
    return unless my $new = IO::Socket::SSL->start_SSL($socket, %options);
    $socket->blocking(0);

    # Upgrade
    $c->{socket} = $new;
    $self->{_cs}->{$new} = delete $self->{_cs}->{$id};

    return "$new";
}

sub stop { delete shift->{_running} }

sub timer {
    my ($self, $after, $cb) = @_;

    # Timer
    my $timer = {after => $after, cb => $cb, started => time};

    # Add timer
    my $id = "$timer";
    $self->{_ts}->{$id} = $timer;

    return $id;
}

sub write_cb { shift->_add_event('write', @_) }

sub writing {
    my ($self, $id) = @_;

    # Activity
    $self->_activity($id);

    # Connection
    my $c = $self->{_cs}->{$id};

    # Writing again
    delete $c->{read_only};

    # Socket
    return unless my $socket = $c->{socket};

    # KQueue
    my $loop = $self->{_loop} ||= $self->_build_loop;
    if (KQUEUE) {
        my $fd = fileno $socket;

        # Writing
        my $writing = $c->{writing};
        $loop->EV_SET($fd, KQUEUE_READ,  KQUEUE_ADD) unless defined $writing;
        $loop->EV_SET($fd, KQUEUE_WRITE, KQUEUE_ADD) unless $writing;

        # Writing
        $c->{writing} = 1;
    }

    # Epoll
    elsif (EPOLL) { $loop->mask($socket, EPOLL_POLLIN | EPOLL_POLLOUT) }

    # Poll
    else { $loop->mask($socket, POLLIN | POLLOUT) }
}

sub _accept {
    my ($self, $listen) = @_;

    # Accept
    my $socket = $listen->accept or return;

    # Unlock callback
    $self->_run_callback('unlock', $self->unlock_cb);

    # Add connection
    my $id = "$socket";
    my $c = $self->{_cs}->{$id} = {
        accepting => 1,
        buffer    => Mojo::ByteStream->new,
        socket    => $socket
    };

    # Timeout
    $c->{accept_timer} =
      $self->timer($self->accept_timeout, =>
          sub { shift->_error($id, 'Accept timeout.') });

    # Disable Nagle's algorithm
    setsockopt($socket, IPPROTO_TCP, TCP_NODELAY, 1)
      unless $self->{_listen}->{$listen}->{file};

    # File descriptor
    my $fd = fileno $socket;
    $self->{_fds}->{$fd} = $id;

    # Accept callback
    my $cb = $self->{_listen}->{$listen}->{cb};
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

sub _activity {
    my ($self, $id) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Activity
    return $c->{active} = time;
}

sub _add_event {
    my ($self, $event, $id, $cb) = @_;

    # Connection
    return unless my $c = $self->{_cs}->{$id};

    # Add event callback
    $c->{$event} = $cb if $cb;

    return $self;
}

# Initialize as late as possible because kqueues don't survive a fork
sub _build_loop {

    # "kqueue"
    return IO::KQueue->new if KQUEUE;

    # "epoll"
    return IO::Epoll->new if EPOLL;

    # "poll"
    return IO::Poll->new;
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

    # Drop listen socket
    if (!$c && ($c = delete $self->{_listen}->{$id})) {

        # Not listening
        return $self unless $self->{_listening};

        # Not listening anymore
        delete $self->{_listening};
    }

    # Drop socket
    if (my $socket = $c->{socket}) {

        # Remove file descriptor
        my $fd = fileno $socket;
        delete $self->{_fds}->{$fd};

        # Remove socket from kqueue
        if (my $loop = $self->{_loop}) {
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

    # Get error callback
    my $event = $self->{_cs}->{$id}->{error};

    # Cleanup
    $self->_drop_immediately($id);

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

sub _prepare {
    my $self = shift;

    # Prepare
    while (my ($id, $c) = each %{$self->{_cs}}) {

        # Accepting
        $self->_prepare_accept($id) if $c->{accepting};

        # Connecting
        $self->_prepare_connect($id) if $c->{connecting};

        # Connection needs to be finished
        if ($c->{finish}) {

            # Buffer empty
            unless ($c->{buffer} && !$c->{buffer}->size) {
                $self->_drop_immediately($id);
                next;
            }
        }

        # Read only
        $self->not_writing($id) if delete $c->{read_only};

        # Timeout
        my $timeout = $c->{timeout} || 15;

        # Last active
        my $time = $c->{active} || $self->_activity($id);

        # HUP
        $self->_hup($id) if (time - $time) >= $timeout;
    }

    # Nothing to do
    my $running = 0;

    # Connections
    my $listen = $self->{_listen} || {};
    if (keys %{$self->{_cs}}) { $running = 1 }

    # Timers
    elsif (keys %{$self->{_ts}}) { $running = 1 }

    # Listening
    elsif ($self->{_listening}) { $running = 1 }

    # Listen sockets
    elsif ($self->max_connections > 0 && keys %$listen) { $running = 1 }

    # Stopped
    unless ($running) {
        delete $self->{_running};
        return 1;
    }

    return;
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

    # Non blocking
    $c->{socket}->blocking(0);

    # Add socket to poll
    $self->not_writing($id);
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
    return unless $c->{socket}->connected;

    # Connected
    delete $c->{connecting};

    # Remove timeout
    $self->_drop_immediately(delete $c->{connect_timer});

    # Connect callback
    my $cb = $c->{connect_cb};
    $self->_run_event('connect', $cb, $id) if $cb;
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

sub _read {
    my ($self, $id) = @_;

    # Listen socket (new connection)
    my $found;
    my $listen = $self->{_listen} || {};
    for my $lid (keys %$listen) {
        my $socket = $listen->{$lid}->{socket};
        if ($id eq $socket) {
            $found = $socket;
            last;
        }
    }

    # Accept new connection
    return $self->_accept($found) if $found;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Socket
    return unless defined(my $socket = $c->{socket});

    # Read chunk
    my $read = $socket->sysread(my $buffer, CHUNK_SIZE, 0);

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
    $self->_activity($id);
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

sub _should_listen {
    my $self = shift;

    # Listen sockets
    my $listen = $self->{_listen} || {};
    return unless keys %$listen;

    # Connections
    my $cs = $self->{_cs};
    return unless keys %$cs < $self->max_connections;

    # Lock
    return unless $self->_run_callback('lock', $self->lock_cb, !keys %$cs);

    return 1;
}

sub _timer {
    my $self = shift;

    # Timers
    return unless my $ts = $self->{_ts};

    # Check
    for my $id (keys %$ts) {
        my $t = $ts->{$id};

        # Timer
        my $after = $t->{after} || 0;
        if ($after <= time - $t->{started}) {

            # Callback
            if (my $cb = $t->{cb}) { $self->_run_callback('timer', $cb) }

            # Drop
            $self->_drop_immediately($id);
        }
    }
}

sub _write {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Connect has just completed
    return if $c->{connecting};

    # Buffer
    my $buffer = $c->{buffer};

    # Try to fill the buffer before writing
    my $more = !$c->{read_only} && !$c->{finish} ? 1 : 0;
    my $event = $c->{write};
    if ($more && $event && $buffer->size < CHUNK_SIZE) {

        # Write callback
        $c->{protected} = 1;
        my $chunk = $self->_run_event('write', $event, $id);
        delete $c->{protected};

        # Add to buffer
        $buffer->add_chunk($chunk);
    }

    # Socket
    return unless my $socket = $c->{socket};
    return unless $socket->connected;

    # Try to write whole buffer
    my $chunk = $buffer->to_string;

    # Write
    my $written = $socket->syswrite($chunk, length $chunk);

    # Error
    unless (defined $written) {

        # Retry
        return if $! == EAGAIN || $! == EWOULDBLOCK;

        # Write error
        return $self->_error($id, $!);
    }

    # Remove written chunk from buffer
    $buffer->remove($written);

    # Activity
    $self->_activity($id) if $written;
}

1;
__END__

=head1 NAME

Mojo::IOLoop - Minimalistic Reactor For TCP Clients And Servers

=head1 SYNOPSIS

    use Mojo::IOLoop;

    # Create loop
    my $loop = Mojo::IOLoop->new;

    # Listen on port 3000
    $loop->listen(
        port => 3000,
        cb   => sub {
            my ($self, $id) = @_;

            # Start read only when accepting a new connection
            $self->not_writing($id);

            # Incoming data
            $self->read_cb($id => sub {
                my ($self, $id, $chunk) = @_;

                # Got some data, time to write
                $self->writing($id);
            });

            # Ready to write
            $self->write_cb($id => sub {
                my ($self, $id) = @_;

                # Back to reading only
                $self->not_writing($id);

                # The loop will take care of buffering for us
                return 'HTTP/1.1 200 OK';
            });
        }
    );

    # Connect to port 3000 with TLS activated
    my $id = $loop->connect(address => 'localhost', port => 3000, tls => 1);

    # Loop starts writing
    $loop->writing($id);

    # Writing request
    $loop->write_cb($id => sub {
        my ($self, $id) = @_;

        # Back to reading only
        $self->not_writing($id);

        # The loop will take care of buffering for us
        return "GET / HTTP/1.1\r\n\r\n";
    });

    # Reading response
    $loop->read_cb($id => sub {
        my ($self, $id, $chunk) = @_;

        # Time to write more
        $self->writing($id);
    });

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
absolute minimal feature set required to build solid and scalable TCP clients
and servers.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::INET6> and
L<IO::Socket::SSL> are supported transparently and used if installed.

=head2 ATTRIBUTES

L<Mojo::IOLoop> implements the following attributes.

=head2 C<accept_timeout>

    my $timeout = $loop->accept_timeout;
    $loop       = $loop->accept_timeout(5);

Maximum time in seconds a connection can take to be accepted before being
dropped, defaults to C<5>.

=head2 C<connect_timeout>

    my $timeout = $loop->connect_timeout;
    $loop       = $loop->connect_timeout(5);

Maximum time in seconds a conenction can take to be connected before being
dropped, defaults to C<5>.

=head2 C<lock_cb>

    my $cb = $loop->lock_cb;
    $loop  = $loop->lock_cb(sub {...});

A locking callback that decides if this loop is allowed to listen for new
incoming connections, used to sync multiple server processes.
The callback should return true or false.

    $loop->lock_cb(sub {
        my ($loop, $blocking) = @_;

        # Got the lock, listen for new connections
        return 1;
    });

=head2 C<max_connections>

    my $max = $loop->max_connections;
    $loop   = $loop->max_connections(1000);

The maximum number of connections this loop is allowed to handle before
stopping to accept new incoming connections, defaults to C<1000>.
Setting the value to C<0> will make this loop stop accepting new connections
and allow it to shutdown gracefully without interrupting existing
connections.

=head2 C<tick_cb>

    my $cb = $loop->tick_cb;
    $loop  = $loop->tick_cb(sub {...});

Callback to be invoked on every reactor tick, this for example allows you to
run multiple reactors next to each other.

    my $loop2 = Mojo::IOLoop->new(timeout => 0);
    Mojo::IOLoop->singleton->tick_cb(sub { $loop2->one_tick });

Note that the loop timeout can be changed dynamically at any time to adjust
responsiveness.

=head2 C<timeout>

    my $timeout = $loop->timeout;
    $loop       = $loop->timeout(5);

Maximum time in seconds our loop waits for new events to happen, defaults to
C<0.25>.
Note that a value of C<0> would make the loop non blocking.

=head2 C<unlock_cb>

    my $cb = $loop->unlock_cb;
    $loop  = $loop->unlock_cb(sub {...});

A callback to free the listen lock, called after accepting a new connection
and used to sync multiple server processes.

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
        port    => 3000,
        cb      => sub {...}
    );
    my $id = $loop->connect({
        address => '127.0.0.1',
        port    => 3000,
        cb      => sub {...}
    });
    my $id = $loop->connect({
        address => '[::1]',
        port    => 443,
        tls     => 1,
        cb      => sub {...}
    });

Open a TCP connection to a remote host, IPv6 will be used automatically if
available.
Note that IPv6 support depends on L<IO::Socket::INET6> and TLS support on
L<IO::Socket::SSL>.

These options are currently available.

=over 4

=item C<address>

Address or host name of the peer to connect to.

=item C<cb>

Callback to be invoked once the connection is established.

=item C<port>

Port to connect to.

=item C<tls>

Enable TLS.

=item C<tls_ca_file>

CA file to use for TLS.

=item C<tls_verify_cb>

Callback to invoke for TLS verification.

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

=head2 C<error_cb>

    $loop = $loop->error_cb($id => sub {...});

Callback to be invoked if an error event happens on the connection.

=head2 C<generate_port>

    my $port = $loop->generate_port;

Find a free TCP port, this is a utility function primarily used for tests.

=head2 C<hup_cb>

    $loop = $loop->hup_cb($id => sub {...});

Callback to be invoked if the connection gets closed.

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
Note that IPv6 support depends on L<IO::Socket::INET6> and TLS support on
L<IO::Socket::SSL>.

These options are currently available.

=over 4

=item C<address>

Local address to listen on, defaults to all.

=item C<cb>

Callback to invoke for each accepted connection.

=item C<file>

A unix domain socket to listen on.

=item C<port>

Port to listen on.

=item C<queue_size>

Maximum queue size, defaults to C<SOMAXCONN>.

=item C<tls>

Enable TLS.

=item C<tls_cert>

Path to the TLS cert file.

=item C<tls_key>

Path to the TLS key file.

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

=head2 C<not_writing>

    $loop->not_writing($id);

Activate read only mode for a connection.
Note that connections have no mode after they are created.

=head2 C<one_tick>

    $loop->one_tick;

Run reactor for exactly one tick.

=head2 C<read_cb>

    $loop = $loop->read_cb($id => sub {...});

Callback to be invoked if new data arrives on the connection.

    $loop->read_cb($id => sub {
        my ($loop, $id, $chunk) = @_;

        # Process chunk
    });

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

=head2 C<singleton>

    my $loop = Mojo::IOLoop->singleton;

The global loop object, used to access a single shared loop instance from
everywhere inside the process.

=head2 C<start>

    $loop->start;

Start the loop, this will block until the loop is finished or return
immediately if the loop is already running.

=head2 C<start_tls>

    my $id = $loop->start_tls($id);
    my $id = $loop->start_tls($id => {tls_ca_file => '/etc/tls/cacerts.pem'});

Start new TLS connection inside old connection.
Note that TLS support depends on L<IO::Socket::SSL>.

These options are currently available.

=over 4

=item C<tls_ca_file>

CA file to use for TLS.

=item C<tls_verify_cb>

Callback to invoke for TLS verification.

=back

=head2 C<stop>

    $loop->stop;

Stop the loop immediately, this will not interrupt any existing connections
and the loop can be restarted by running C<start> again.

=head2 C<timer>

    my $id = $loop->timer(5 => sub {...});

Create a new timer, invoking the callback afer a given amount of seconds.

=head2 C<write_cb>

    $loop = $loop->write_cb($id => sub {...});

Callback to be invoked if new data can be written to the connection.
The callback should return a chunk of data which will be buffered inside the
loop to guarantee safe writing.

    $loop->write_cb($id => sub {
        my ($loop, $id) = @_;
        return 'Data to be buffered by the loop!';
    });

=head2 C<writing>

    $loop->writing($id);

Activate read/write mode for a connection.
Note that connections have no mode after they are created.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
