package Mojo::IOLoop::Stream;
use Mojo::Base 'Mojo::EventEmitter';

use Errno qw/EAGAIN ECONNRESET EINTR EPIPE EWOULDBLOCK/;
use Scalar::Util 'weaken';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

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
  return unless my $handle = $self->{handle};
  close $handle;
  $self->emit_safe('close');
}

sub new {
  my $self = shift->SUPER::new;
  $self->{handle} = shift;
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

  # Write with roundtrip
  if ($cb) { $self->once(drain => $cb) }
  else     { return unless length $self->{buffer} }

  # Start writing
  $self->iowatcher->writing($self->{handle}) if $self->{handle};
}

sub _read {
  my $self = shift;

  # Read
  my $read = $self->{handle}->sysread(my $buffer, CHUNK_SIZE, 0);

  # Error
  unless (defined $read) {

    # Retry
    return if $! ~~ [EAGAIN, EINTR, EWOULDBLOCK];

    # Closed
    return $self->emit_safe('close') if $! == ECONNRESET;

    # Read error
    return $self->emit_safe(error => $!);
  }

  # EOF
  return $self->emit_safe('close') if $read == 0;

  # Handle read
  $self->emit_safe(read => $buffer);
}

sub _write {
  my $self = shift;

  # Write as much as possible
  my $handle = $self->{handle};
  if (length $self->{buffer}) {
    my $written = $handle->syswrite($self->{buffer});

    # Error
    unless (defined $written) {

      # Retry
      return if $! ~~ [EAGAIN, EINTR, EWOULDBLOCK];

      # Closed
      return $self->emit_safe('close') if $! ~~ [ECONNRESET, EPIPE];

      # Write error
      return $self->emit_safe(error => $!);
    }

    # Remove written chunk from buffer
    substr $self->{buffer}, 0, $written, '';
  }

  # Handle drain
  $self->emit_safe('drain') if !length $self->{buffer};

  # Stop writing
  return if length $self->{buffer} || @{$self->subscribers('drain')};
  $self->iowatcher->not_writing($handle);
}

1;
__END__

=head1 NAME

Mojo::IOLoop::Stream - IOLoop stream

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

  $stream->on(close => sub {
    my $stream = shift;
  });

Emitted if the stream gets closed.

=head2 C<drain>

  $stream->on(drain => sub {
    my $stream = shift;
  });

Emitted once all data has been written.

=head2 C<error>

  $stream->on(error => sub {
    my ($stream, $error) = @_;
  });

Emitted if an error happens on the stream.

=head2 C<read>

  $stream->on(read => sub {
    my ($stream, $chunk) = @_;
  });

Emitted if new data arrives on the stream.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream> implements the following attributes.

=head2 C<iowatcher>

  my $watcher = $stream->iowatcher;
  $stream     = $stream->iowatcher(Mojo::IOWatcher->new);

Low level event watcher, usually a L<Mojo::IOWatcher> or
L<Mojo::IOWatcher::EV> object.

=head1 METHODS

L<Mojo::IOLoop::Stream> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<new>

  my $stream = Mojo::IOLoop::Stream->new($handle);

Construct a new L<Mojo::IOLoop::Stream> object.

=head2 C<handle>

  my $handle = $stream->handle;

Get handle for stream.

=head2 C<is_finished>

  my $success = $stream->is_finished;

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
  $stream->write('Hello!', sub {...});

Write data to stream, the optional drain callback will be invoked once all
data has been written.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
