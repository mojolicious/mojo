package Mojo::IOLoop::Stream;
use Mojo::Base 'Mojo::EventEmitter';

use Errno qw(EAGAIN ECONNRESET EINTR EWOULDBLOCK);
use Mojo::IOLoop;
use Mojo::Util;
use Scalar::Util qw(weaken);

has high_water_mark => 1048576;
has reactor         => sub { Mojo::IOLoop->singleton->reactor }, weak => 1;

sub DESTROY { Mojo::Util::_global_destruction() or shift->close }

sub bytes_read { shift->{read} || 0 }

sub bytes_waiting { length(shift->{buffer} // '') }

sub bytes_written { shift->{written} || 0 }

sub can_write { $_[0]{handle} && $_[0]->bytes_waiting < $_[0]->high_water_mark }

sub close {
  my $self = shift;
  return unless my $reactor = $self->reactor;
  return unless my $handle  = delete $self->timeout(0)->{handle};
  $reactor->remove($handle);
  $self->emit('close');
}

sub close_gracefully { $_[0]->is_writing ? $_[0]{graceful}++ : $_[0]->close }

sub handle { shift->{handle} }

sub is_readable {
  my $self = shift;
  $self->_again;
  return $self->{handle} && Mojo::Util::_readable(0, fileno $self->{handle});
}

sub is_writing {
  my $self = shift;
  return undef unless $self->{handle};
  return !!length($self->{buffer}) || $self->has_subscribers('drain');
}

sub new { shift->SUPER::new(handle => shift, timeout => 15) }

sub start {
  my $self = shift;

  # Resume
  return unless $self->{handle};
  my $reactor = $self->reactor;
  return $reactor->watch($self->{handle}, 1, $self->is_writing) if delete $self->{paused};

  weaken $self;
  my $cb = sub { pop() ? $self->_write : $self->_read };
  $reactor->io($self->timeout($self->{timeout})->{handle} => $cb);
}

sub steal_handle {
  my $self = shift;
  $self->reactor->remove($self->{handle});
  return delete $self->{handle};
}

sub stop { $_[0]->reactor->watch($_[0]{handle}, 0, $_[0]->is_writing) if $_[0]{handle} && !$_[0]{paused}++ }

sub timeout {
  my ($self, $timeout) = @_;

  return $self->{timeout} unless defined $timeout;
  $self->{timeout} = $timeout;

  my $reactor = $self->reactor;
  if ($self->{timer}) {
    if   (!$self->{timeout}) { $reactor->remove(delete $self->{timer}) }
    else                     { $reactor->again($self->{timer}, $self->{timeout}) }
  }
  elsif ($self->{timeout}) {
    weaken $self;
    $self->{timer}
      = $reactor->timer($timeout => sub { $self and delete($self->{timer}) and $self->emit('timeout')->close });
  }

  return $self;
}

sub write {
  my ($self, $chunk, $cb) = @_;

  # IO::Socket::SSL will corrupt data with the wrong internal representation
  utf8::downgrade $chunk;
  $self->{buffer} .= $chunk;
  if    ($cb)                     { $self->once(drain => $cb) }
  elsif (!length $self->{buffer}) { return $self }
  $self->reactor->watch($self->{handle}, !$self->{paused}, 1) if $self->{handle};

  return $self;
}

sub _again { $_[0]->reactor->again($_[0]{timer}) if $_[0]{timer} }

sub _read {
  my $self = shift;

  if (defined(my $read = $self->{handle}->sysread(my $buffer, 131072, 0))) {
    $self->{read} += $read;
    return $read == 0 ? $self->close : $self->emit(read => $buffer)->_again;
  }

  # Retry
  return undef if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

  # Closed (maybe real error)
  $! == ECONNRESET ? $self->close : $self->emit(error => $!)->close;
}

sub _write {
  my $self = shift;

  # Handle errors only when reading (to avoid timing problems)
  my $handle = $self->{handle};
  if (length $self->{buffer}) {
    return undef unless defined(my $written = $handle->syswrite($self->{buffer}));
    $self->{written} += $written;
    $self->emit(write => substr($self->{buffer}, 0, $written, ''))->_again;
  }

  # Clear the buffer to free the underlying SV* memory
  undef $self->{buffer}, $self->emit('drain') unless length $self->{buffer};
  return undef                                        if $self->is_writing;
  return $self->close                                 if $self->{graceful};
  $self->reactor->watch($handle, !$self->{paused}, 0) if $self->{handle};
}

1;

=encoding utf8

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

L<Mojo::IOLoop::Stream> is a container for I/O streams used by L<Mojo::IOLoop>.

=head1 EVENTS

L<Mojo::IOLoop::Stream> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

=head2 close

  $stream->on(close => sub {
    my $stream = shift;
    ...
  });

Emitted if the stream gets closed.

=head2 drain

  $stream->on(drain => sub {
    my $stream = shift;
    ...
  });

Emitted once all data has been written.

=head2 error

  $stream->on(error => sub {
    my ($stream, $err) = @_;
    ...
  });

Emitted if an error occurs on the stream, fatal if unhandled.

=head2 read

  $stream->on(read => sub {
    my ($stream, $bytes) = @_;
    ...
  });

Emitted if new data arrives on the stream.

=head2 timeout

  $stream->on(timeout => sub {
    my $stream = shift;
    ...
  });

Emitted if the stream has been inactive for too long and will get closed automatically.

=head2 write

  $stream->on(write => sub {
    my ($stream, $bytes) = @_;
    ...
  });

Emitted if new data has been written to the stream.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream> implements the following attributes.

=head2 high_water_mark

  my $size = $msg->high_water_mark;
  $msg     = $msg->high_water_mark(1024);

Maximum size of L</"write"> buffer in bytes before L</"can_write"> returns false, defaults to C<1048576> (1MiB).

=head2 reactor

  my $reactor = $stream->reactor;
  $stream     = $stream->reactor(Mojo::Reactor::Poll->new);

Low-level event reactor, defaults to the C<reactor> attribute value of the global L<Mojo::IOLoop> singleton. Note that
this attribute is weakened.

=head1 METHODS

L<Mojo::IOLoop::Stream> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 bytes_read

  my $num = $stream->bytes_read;

Number of bytes received.

=head2 bytes_waiting

  my $num = $stream->bytes_waiting;

Number of bytes that have been enqueued with L</"write"> and are waiting to be written.

=head2 bytes_written

  my $num = $stream->bytes_written;

Number of bytes written.

=head2 can_write

  my $bool = $stream->can_write;

Returns true if calling L</"write"> is safe.

=head2 close

  $stream->close;

Close stream immediately.

=head2 close_gracefully

  $stream->close_gracefully;

Close stream gracefully.

=head2 handle

  my $handle = $stream->handle;

Get handle for stream, usually an L<IO::Socket::IP> or L<IO::Socket::SSL> object.

=head2 is_readable

  my $bool = $stream->is_readable;

Quick non-blocking check if stream is readable, useful for identifying tainted sockets.

=head2 is_writing

  my $bool = $stream->is_writing;

Check if stream is writing.

=head2 new

  my $stream = Mojo::IOLoop::Stream->new($handle);

Construct a new L<Mojo::IOLoop::Stream> object.

=head2 start

  $stream->start;

Start or resume watching for new data on the stream.

=head2 steal_handle

  my $handle = $stream->steal_handle;

Steal L</"handle"> and prevent it from getting closed automatically.

=head2 stop

  $stream->stop;

Stop watching for new data on the stream.

=head2 timeout

  my $timeout = $stream->timeout;
  $stream     = $stream->timeout(45);

Maximum amount of time in seconds stream can be inactive before getting closed automatically, defaults to C<15>.
Setting the value to C<0> will allow this stream to be inactive indefinitely.

=head2 write

  $stream = $stream->write($bytes);
  $stream = $stream->write($bytes => sub {...});

Enqueue data to be written to the stream as soon as possible, the optional drain callback will be executed once all
data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
