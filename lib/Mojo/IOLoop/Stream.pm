package Mojo::IOLoop::Stream;
use Mojo::Base 'Mojo::IOLoop::EventEmitter';

use Errno qw/EAGAIN EINTR ECONNRESET EWOULDBLOCK/;
use Scalar::Util 'weaken';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

# Windows
use constant WINDOWS => $^O eq 'MSWin32' || $^O =~ /cygwin/ ? 1 : 0;

has iowatcher => sub {
  require Mojo::IOLoop;
  Mojo::IOLoop->singleton->iowatcher;
};

# "And America has so many enemies.
#  Iran, Iraq, China, Mordor, the hoochies that laid low Tiger Woods,
#  undesirable immigrants - by which I mean everyone that came after me,
#  including my children..."
sub DESTROY {
  my $self = shift;
  $self->pause if $self->{iowatcher};
  $self->emit('close') if $self->{handle};
}

sub new {
  my $self = shift->SUPER::new;
  $self->{handle} = shift;
  $self->{handle}->blocking(0);
  $self->{buffer} = '';
  return $self;
}

sub handle { shift->{handle} }

sub is_finished {
  my $self = shift;
  return if length $self->{buffer};
  return if @{$self->subscribers('drain')};
  return 1;
}

sub pause {
  my $self = shift;
  $self->iowatcher->remove($self->{handle}) if $self->{handle};
}

sub resume {
  my $self = shift;
  weaken $self;
  $self->iowatcher->add(
    $self->{handle},
    on_readable => sub { $self->_read },
    on_writable => sub { $self->_write }
  );
}

# "No children have ever meddled with the Republican Party and lived to tell
#  about it."
sub steal_handle {
  my $self = shift;
  $self->pause;
  return delete $self->{handle};
}

sub write {
  my ($self, $chunk, $cb) = @_;

  # Prepare chunk for writing
  $self->{buffer} .= $chunk;

  # UNIX only quick write
  unless (WINDOWS) {
    local $self->{quick} = 1 if $cb;
    $self->_write;
  }

  # Write with roundtrip
  if ($cb) { $self->once(drain => $cb) }
  else     { return unless length $self->{buffer} }

  # Start writing
  return unless my $handle = $self->{handle};
  $self->iowatcher->writing($handle);
}

sub _read {
  my $self = shift;

  # Read
  my $read = $self->{handle}->sysread(my $buffer, CHUNK_SIZE, 0);

  # Error
  unless (defined $read) {

    # Retry
    return if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

    # Connection reset
    return $self->emit('close') if $! == ECONNRESET;

    # Read error
    return $self->emit(error => $!);
  }

  # EOF
  return $self->emit('close') if $read == 0;

  # Handle read
  $self->emit(read => $buffer);
}

sub _write {
  my $self = shift;

  # Handle drain
  $self->emit('drain') if !length $self->{buffer} && !$self->{quick};

  # Write as much as possible
  my $handle = $self->{handle};
  if (length $self->{buffer}) {
    my $written = $handle->syswrite($self->{buffer});

    # Error
    unless (defined $written) {

      # Retry
      return if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

      # Close
      return $self->emit('close')
        if $handle->can('connected') && !$handle->connected;

      # Write error
      return $self->emit(error => $!);
    }

    # Remove written chunk from buffer
    substr $self->{buffer}, 0, $written, '';
  }

  # Stop writing
  return
    if length $self->{buffer}
      || $self->{quick}
      || @{$self->subscribers('drain')};
  $self->iowatcher->not_writing($handle);
}

1;
__END__

=head1 NAME

Mojo::IOLoop::Stream - IOLoop Stream

=head1 SYNOPSIS

  use Mojo::IOLoop::Stream;

  # Create stream
  my $stream = Mojo::IOLoop::Stream->new($handle);
  $stream->on(read => sub {
    my ($self, $chunk) = @_;
    ...
  });
  $stream->on(close => sub {
    my $self = shift;
    ...
  });
  $stream->on(error => sub {
    my ($self, $error) = @_;
    ...
  });

  # Start and stop watching for new data
  $stream->resume;
  $stream->pause;

=head1 DESCRIPTION

L<Mojo::IOLoop::Stream> is a container for streaming handles used by
L<Mojo::IOLoop>.
Note that this module is EXPERIMENTAL and might change without warning!

=head1 EVENTS

L<Mojo::IOLoop::Stream> can emit the following events.

=head2 C<close>

Emitted if the stream gets closed.

=head2 C<drain>

Emitted once all data has been written.

=head2 C<error>

Emitted if an error happens on the stream.

=head2 C<read>

Emitted if new data arrives on the stream.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream> implements the following attributes.

=head2 C<iowatcher>

  my $watcher = $stream->iowatcher;
  $stream     = $stream->iowatcher(Mojo::IOWatcher->new);

Low level event watcher, usually a L<Mojo::IOWatcher> or
L<Mojo::IOWatcher::EV> object.

=head1 METHODS

L<Mojo::IOLoop::Stream> inherits all methods from
L<Mojo::IOLoop::EventEmitter> and implements the following new ones.

=head2 C<new>

  my $stream = Mojo::IOLoop::Stream->new($handle);

Construct a new L<Mojo::IOLoop::Stream> object.

=head2 C<handle>

  my $handle = $stream->handle;

Get handle for stream.

=head2 C<is_finished>

  my $finished = $stream->is_finished;

Check if stream is in a state where it is safe to close or steal the handle.

=head2 C<pause>

  $stream->pause;

Stop watching for new data on the stream.

=head2 C<resume>

  $stream->resume;

Start watching for new data on the stream.

=head2 C<steal_handle>

  my $handle = $stream->steal_handle;

Steal handle from stream and prevent it from getting closed automatically.

=head2 C<write>

  $stream->write('Hello!');

Write data to stream, the optional drain callback will be invoked once all
data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
