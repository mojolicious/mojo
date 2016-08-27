package Mojo::IOLoop::Subprocess;
use Mojo::Base -base;

use Carp 'croak';
use Config;
use Mojo::IOLoop;
use Mojo::IOLoop::Stream;
use Storable;

has deserialize => sub { \&Storable::thaw };
has ioloop      => sub { Mojo::IOLoop->singleton };
has serialize   => sub { \&Storable::freeze };

sub pid { shift->{pid} }

sub run {
  my ($self, $first, $second) = @_;

  # No fork emulation support
  croak 'Subprocesses do not support fork emulation' if $Config{d_pseudofork};

  # Pipe for subprocess communication
  pipe(my $reader, my $writer) or croak "Can't create pipe: $!";

  # Child
  croak "Can't fork: $!" unless defined($self->{pid} = fork);
  unless ($self->{pid}) {
    $self->ioloop->reset;
    print $writer $self->serialize->([$self->$first]);
    exit 0;
  }

  # Parent
  my $stream = Mojo::IOLoop::Stream->new($reader);
  $self->ioloop->stream($stream);
  my $buffer;
  $stream->on(read => sub { $buffer .= pop });
  $stream->on(
    close => sub {
      waitpid $self->{pid}, 0;
      return $self->$second("Non-zero exit status (@{[$? >> 8]})") if $?;
      my $result = eval { $self->deserialize->($buffer) } || [];
      $self->$second($@, @$result);
    }
  );
  return $self;
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Subprocess - Subprocesses

=head1 SYNOPSIS

  use Mojo::IOLoop::Subprocess;

  # Operation that would block the event loop for 5 seconds
  my $sp = Mojo::IOLoop::Subprocess->new;
  $sp->run(
    sub {
      my $sp = shift;
      sleep 5;
      return '♥', 'Mojolicious';
    },
    sub {
      my ($sp, $err, @results) = @_;
      say "I $results[0] $results[1]!";
    }
  );

  # Start event loop if necessary
  $sp->ioloop->start unless $sp->ioloop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Subprocess> allows L<Mojo::IOLoop> to perform computationally
expensive operations in subprocesses, without blocking the event loop. Note that
this module is EXPERIMENTAL and might change without warning!

=head1 ATTRIBUTES

L<Mojo::IOLoop::Subprocess> implements the following attributes.

=head2 deserialize

  my $cb = $sp->deserialize;
  $sp    = $sp->deserialize(sub {...});

A callback used to deserialize subprocess return values, defaults to using
L<Storable>.

  $sessions->deserialize(sub {
    my $bytes = shift;
    return [];
  });

=head2 ioloop

  my $loop = $sp->ioloop;
  $sp      = $sp->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop> singleton.

=head2 serialize

  my $cb = $sp->serialize;
  $sp    = $sp->serialize(sub {...});

A callback used to serialize subprocess return values, defaults to using
L<Storable>.

  $sessions->serialize(sub {
    my $array = shift;
    return '';
  });

=head1 METHODS

L<Mojo::IOLoop::Subprocess> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 pid

  my $pid = $sp->pid;

Process id of the spawned subprocess if available.

=head2 run

  $sp = $sp->run(sub {...}, sub {...});

Execute the first callback in a child process and wait for it to return one or
more values, without blocking L</"ioloop"> in the parent process. Then execute
the second callback in the parent process with the results. The return values of
the first callback will be serialized with L<Storable>, so they can be shared
between processes.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
