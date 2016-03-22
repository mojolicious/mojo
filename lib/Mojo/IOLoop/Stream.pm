package Mojo::IOLoop::Stream;
use Mojo::Base 'Mojo::EventEmitter';

use Errno qw(EAGAIN ECONNRESET EINTR EWOULDBLOCK);
use Mojo::IOLoop;
use Mojo::Util;
use Scalar::Util 'weaken';

has reactor => sub { Mojo::IOLoop->singleton->reactor };

sub DESTROY { Mojo::Util::_global_destruction() or shift->close }

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

sub new { shift->SUPER::new(handle => shift, buffer => '', timeout => 15) }

sub start {
  my $self = shift;

  # Resume
  my $reactor = $self->reactor;
  return $reactor->watch($self->{handle}, 1, $self->is_writing)
    if delete $self->{paused};

  weaken $self;
  my $cb = sub { pop() ? $self->_write : $self->_read };
  $reactor->io($self->timeout($self->{timeout})->{handle} => $cb);
}

sub steal_handle {
  my $self = shift;
  $self->reactor->remove($self->{handle});
  return delete $self->{handle};
}

sub stop {
  my $self = shift;
  $self->reactor->watch($self->{handle}, 0, $self->is_writing)
    unless $self->{paused}++;
}

sub timeout {
  my $self = shift;

  return $self->{timeout} unless @_;

  my $reactor = $self->reactor;
  $reactor->remove(delete $self->{timer}) if $self->{timer};
  return $self unless my $timeout = $self->{timeout} = shift;
  weaken $self;
  $self->{timer}
    = $reactor->timer($timeout => sub { $self->emit('timeout')->close });

  return $self;
}

sub write {
  my ($self, $chunk, $cb) = @_;

  $self->{buffer} .= $chunk;
  if ($cb) { $self->once(drain => $cb) }
  elsif (!length $self->{buffer}) { return $self }
  $self->reactor->watch($self->{handle}, !$self->{paused}, 1)
    if $self->{handle};

  return $self;
}

sub _again { $_[0]->reactor->again($_[0]{timer}) if $_[0]{timer} }

sub _read {
  my $self = shift;

  my $read = $self->{handle}->sysread(my $buffer, 131072, 0);
  return $read == 0 ? $self->close : $self->emit(read => $buffer)->_again
    if defined $read;

  # Retry
  return if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

  # Closed (maybe real error)
  $! == ECONNRESET ? $self->close : $self->emit(error => $!)->close;
}

sub _write {
  my $self = shift;

  # Handle errors only when reading (to avoid timing problems)
  my $handle = $self->{handle};
  if (length $self->{buffer}) {
    return unless defined(my $written = $handle->syswrite($self->{buffer}));
    $self->emit(write => substr($self->{buffer}, 0, $written, ''))->_again;
  }

  $self->emit('drain') unless length $self->{buffer};
  return if $self->is_writing;
  return $self->close if $self->{graceful};
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

L<Mojo::IOLoop::Stream> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

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

Emitted if the stream has been inactive for too long and will get closed
automatically.

=head2 write

  $stream->on(write => sub {
    my ($stream, $bytes) = @_;
    ...
  });

Emitted if new data has been written to the stream.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream> implements the following attributes.

=head2 reactor

  my $reactor = $stream->reactor;
  $stream     = $stream->reactor(Mojo::Reactor::Poll->new);

Low-level event reactor, defaults to the C<reactor> attribute value of the
global L<Mojo::IOLoop> singleton.

=head1 METHODS

L<Mojo::IOLoop::Stream> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 close

  $stream->close;

Close stream immediately.

=head2 close_gracefully

  $stream->close_gracefully;

Close stream gracefully.

=head2 handle

  my $handle = $stream->handle;

Get handle for stream, usually an L<IO::Socket::IP> or L<IO::Socket::SSL>
object.

=head2 is_readable

  my $bool = $stream->is_readable;

Quick non-blocking check if stream is readable, useful for identifying tainted
sockets.

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

Maximum amount of time in seconds stream can be inactive before getting closed
automatically, defaults to C<15>. Setting the value to C<0> will allow this
stream to be inactive indefinitely.

=head2 write

  $stream = $stream->write($bytes);
  $stream = $stream->write($bytes => sub {...});

Write data to stream, the optional drain callback will be executed once all data
has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
