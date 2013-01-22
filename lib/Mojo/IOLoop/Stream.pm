package Mojo::IOLoop::Stream;
use Mojo::Base 'Mojo::EventEmitter';

use Errno qw(EAGAIN ECONNRESET EINTR EPIPE EWOULDBLOCK);
use Scalar::Util 'weaken';
use Time::HiRes 'time';

has reactor => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->reactor;
};
has timeout => 15;

sub DESTROY { shift->close }

sub new { shift->SUPER::new(handle => shift, buffer => '', active => time) }

sub close {
  my $self = shift;

  # Cleanup
  return unless my $reactor = $self->{reactor};
  $reactor->remove(delete $self->{timer}) if $self->{timer};
  return unless my $handle = delete $self->{handle};
  $reactor->remove($handle);

  close $handle;
  $self->emit_safe('close');
}

sub handle { shift->{handle} }

sub is_readable {
  my $self = shift;
  $self->{active} = time;
  return $self->{handle} && $self->reactor->is_readable($self->{handle});
}

sub is_writing {
  my $self = shift;
  return undef unless exists $self->{handle};
  return !!length($self->{buffer}) || $self->has_subscribers('drain');
}

sub start {
  my $self = shift;
  return $self->_startup unless $self->{startup}++;
  return unless delete $self->{paused};
  $self->reactor->watch($self->{handle}, 1, $self->is_writing);
}

sub stop {
  my $self = shift;
  return if $self->{paused}++;
  $self->reactor->watch($self->{handle}, 0, $self->is_writing);
}

sub steal_handle {
  my $self = shift;
  $self->reactor->remove($self->{handle});
  return delete $self->{handle};
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

sub _read {
  my $self = shift;

  my $read = $self->{handle}->sysread(my $buffer, 131072, 0);
  unless (defined $read) {

    # Retry
    return if grep { $_ == $! } EAGAIN, EINTR, EWOULDBLOCK;

    # Closed
    return $self->close if grep { $_ == $! } ECONNRESET, EPIPE;

    # Read error
    return $self->emit_safe(error => $!)->close;
  }

  # EOF
  return $self->close if $read == 0;

  $self->emit_safe(read => $buffer)->{active} = time;
}

sub _startup {
  my $self = shift;

  # Timeout (ignore 0 timeout)
  my $reactor = $self->reactor;
  weaken $self;
  $self->{timer} = $reactor->recurring(
    0.5 => sub {
      return unless my $t = $self->timeout;
      $self->emit_safe('timeout')->close if (time - $self->{active}) >= $t;
    }
  );

  $reactor->io($self->{handle}, sub { pop() ? $self->_write : $self->_read });
}

sub _write {
  my $self = shift;

  my $handle = $self->{handle};
  if (length $self->{buffer}) {
    my $written = $handle->syswrite($self->{buffer});
    unless (defined $written) {

      # Retry
      return if grep { $_ == $! } EAGAIN, EINTR, EWOULDBLOCK;

      # Closed
      return $self->close if grep { $_ == $! } ECONNRESET, EPIPE;

      # Write error
      return $self->emit_safe(error => $!)->close;
    }

    $self->emit_safe(write => substr($self->{buffer}, 0, $written, ''));
    $self->{active} = time;
  }

  $self->emit_safe('drain') if !length $self->{buffer};
  return if $self->is_writing;
  $self->reactor->watch($handle, !$self->{paused}, 0);
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

=head2 timeout

  my $timeout = $stream->timeout;
  $stream     = $stream->timeout(45);

Maximum amount of time in seconds stream can be inactive before getting closed
automatically, defaults to C<15>. Setting the value to C<0> will allow this
stream to be inactive indefinitely.

=head1 METHODS

L<Mojo::IOLoop::Stream> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 new

  my $stream = Mojo::IOLoop::Stream->new($handle);

Construct a new L<Mojo::IOLoop::Stream> object.

=head2 close

  $stream->close;

Close stream immediately.

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

=head2 write

  $stream = $stream->write($bytes);
  $stream = $stream->write($bytes => sub {...});

Write data to stream, the optional drain callback will be invoked once all
data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
