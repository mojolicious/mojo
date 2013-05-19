package Mojo::IOLoop::Stream;
use Mojo::Base 'Mojo::EventEmitter';

use Errno qw(EAGAIN ECONNRESET EINTR EPIPE EWOULDBLOCK);
use Scalar::Util 'weaken';

has reactor => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->reactor;
};

sub DESTROY { shift->close }

sub new { shift->SUPER::new(handle => shift, buffer => '') }

sub close {
  my $self = shift;

  # Cleanup
  return unless my $reactor = $self->{reactor};
  return unless my $handle  = delete $self->timeout(0)->{handle};
  $reactor->remove($handle);

  close $handle;
  $self->emit_safe('close');
}

sub close_gracefully {
  my $self = shift;
  return $self->{graceful} = 1 if $self->is_writing;
  $self->close;
}

sub handle { shift->{handle} }

sub is_readable {
  my $self = shift;
  $self->_again;
  return $self->{handle} && $self->reactor->is_readable($self->{handle});
}

sub is_writing {
  my $self = shift;
  return undef unless $self->{handle};
  return !!length($self->{buffer}) || $self->has_subscribers('drain');
}

sub start {
  my $self = shift;

  my $reactor = $self->reactor;
  $reactor->io($self->timeout(15)->{handle},
    sub { pop() ? $self->_write : $self->_read })
    unless $self->{timer};

  # Resume
  $reactor->watch($self->{handle}, 1, $self->is_writing)
    if delete $self->{paused};
}

sub stop {
  my $self = shift;
  $self->reactor->watch($self->{handle}, 0, $self->is_writing)
    unless $self->{paused}++;
}

sub steal_handle {
  my $self = shift;
  $self->reactor->remove($self->{handle});
  return delete $self->{handle};
}

sub timeout {
  my $self = shift;

  return $self->{timeout} unless @_;

  my $reactor = $self->reactor;
  $reactor->remove(delete $self->{timer}) if $self->{timer};
  return $self unless my $timeout = $self->{timeout} = shift;
  weaken $self;
  $self->{timer}
    = $reactor->timer($timeout => sub { $self->emit_safe('timeout')->close });

  return $self;
}

sub write {
  my ($self, $chunk, $cb) = @_;

  $self->{buffer} .= $chunk;
  if ($cb) { $self->once(drain => $cb) }
  else     { return $self unless length $self->{buffer} }
  $self->reactor->watch($self->{handle}, !$self->{paused}, 1)
    if $self->{handle};

  return $self;
}

sub _again { $_[0]->reactor->again($_[0]{timer}) if $_[0]{timer} }

sub _error {
  my $self = shift;

  # Retry
  return if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

  # Closed
  return $self->close if $! == ECONNRESET || $! == EPIPE;

  # Error
  $self->emit_safe(error => $!)->close;
}

sub _read {
  my $self = shift;
  my $read = $self->{handle}->sysread(my $buffer, 131072, 0);
  return $self->_error unless defined $read;
  return $self->close if $read == 0;
  $self->emit_safe(read => $buffer)->_again;
}

sub _write {
  my $self = shift;

  my $handle = $self->{handle};
  if (length $self->{buffer}) {
    my $written = $handle->syswrite($self->{buffer});
    return $self->_error unless defined $written;
    $self->emit_safe(write => substr($self->{buffer}, 0, $written, ''));
    $self->_again;
  }

  $self->emit_safe('drain') unless length $self->{buffer};
  return if $self->is_writing;
  return $self->close if $self->{graceful};
  $self->reactor->watch($handle, !$self->{paused}, 0) if $self->{handle};
}

1;

=head1 NAME

Mojo::IOLoop::Stream - Non-blocking I/O stream

=head1 SYNOPSIS

  use Mojo::IOLoop::Stream;

  # Create stream
  my $stream = Mojo::IOLoop::Stream->new($handle);
  $stream->on(read => sub {
    my ($stream, $bytes) = @_;
    ...
  });
  $stream->on(close => sub {
    my $stream = shift;
    ...
  });
  $stream->on(error => sub {
    my ($stream, $err) = @_;
    ...
  });

  # Start and stop watching for new data
  $stream->start;
  $stream->stop;

  # Start reactor if necessary
  $stream->reactor->start unless $stream->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Stream> is a container for I/O streams used by
L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Stream> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 close

  $stream->on(close => sub {
    my $stream = shift;
    ...
  });

Emitted safely if the stream gets closed.

=head2 drain

  $stream->on(drain => sub {
    my $stream = shift;
    ...
  });

Emitted safely once all data has been written.

=head2 error

  $stream->on(error => sub {
    my ($stream, $err) = @_;
    ...
  });

Emitted safely if an error occurs on the stream.

=head2 read

  $stream->on(read => sub {
    my ($stream, $bytes) = @_;
    ...
  });

Emitted safely if new data arrives on the stream.

=head2 timeout

  $stream->on(timeout => sub {
    my $stream = shift;
    ...
  });

Emitted safely if the stream has been inactive for too long and will get
closed automatically.

=head2 write

  $stream->on(write => sub {
    my ($stream, $bytes) = @_;
    ...
  });

Emitted safely if new data has been written to the stream.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream> implements the following attributes.

=head2 reactor

  my $reactor = $stream->reactor;
  $stream     = $stream->reactor(Mojo::Reactor::Poll->new);

Low level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Stream> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 new

  my $stream = Mojo::IOLoop::Stream->new($handle);

Construct a new L<Mojo::IOLoop::Stream> object.

=head2 close

  $stream->close;

Close stream immediately.

=head2 close_gracefully

  $stream->close_gracefully;

Close stream gracefully.

=head2 handle

  my $handle = $stream->handle;

Get handle for stream.

=head2 is_readable

  my $success = $stream->is_readable;

Quick non-blocking check if stream is readable, useful for identifying tainted
sockets.

=head2 is_writing

  my $success = $stream->is_writing;

Check if stream is writing.

=head2 start

  $stream->start;

Start watching for new data on the stream.

=head2 stop

  $stream->stop;

Stop watching for new data on the stream.

=head2 steal_handle

  my $handle = $stream->steal_handle;

Steal handle from stream and prevent it from getting closed automatically.

=head2 timeout

  my $timeout = $stream->timeout;
  $stream     = $stream->timeout(45);

Maximum amount of time in seconds stream can be inactive before getting closed
automatically, defaults to C<15>. Setting the value to C<0> will allow this
stream to be inactive indefinitely.

=head2 write

  $stream = $stream->write($bytes);
  $stream = $stream->write($bytes => sub {...});

Write data to stream, the optional drain callback will be invoked once all
data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
