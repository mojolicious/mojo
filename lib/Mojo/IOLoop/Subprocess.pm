package Mojo::IOLoop::Subprocess;
use Mojo::Base 'Mojo::EventEmitter';

use Config;
use Mojo::IOLoop;
use Mojo::IOLoop::Stream;
use Mojo::JSON;
use Mojo::Promise;
use POSIX ();

has deserialize => sub { \&Mojo::JSON::decode_json };
has ioloop      => sub { Mojo::IOLoop->singleton }, weak => 1;
has serialize   => sub { \&Mojo::JSON::encode_json };

sub exit_code { shift->{exit_code} }

sub pid { shift->{pid} }

sub run {
  my ($self, @args) = @_;
  $self->ioloop->next_tick(sub { $self->_start(@args) });
  return $self;
}

sub run_p {
  my ($self, $child) = @_;

  my $p      = Mojo::Promise->new;
  my $parent = sub {
    my ($self, $err) = (shift, shift);
    $err ? $p->reject($err) : $p->resolve(@_);
  };
  $self->ioloop->next_tick(sub { $self->_start($child, $parent) });

  return $p;
}

sub _start {
  my ($self, $child, $parent) = @_;

  # No fork emulation support
  return $self->$parent('Subprocesses do not support fork emulation') if $Config{d_pseudofork};

  # Pipe for subprocess communication
  return $self->$parent("Can't create pipe: $!") unless pipe(my $reader, $self->{writer});
  $self->{writer}->autoflush(1);

  # Child
  return $self->$parent("Can't fork: $!") unless defined(my $pid = $self->{pid} = fork);
  unless ($pid) {
    eval {
      $self->ioloop->reset({freeze => 1});
      my $results = eval { [$self->$child] } // [];
      print {$self->{writer}} '0-', $self->serialize->([$@, @$results]);
      $self->emit('cleanup');
    } or warn $@;
    POSIX::_exit(0);
  }

  # Parent
  my $me = $$;
  close $self->{writer};
  my $stream = Mojo::IOLoop::Stream->new($reader)->timeout(0);
  $self->emit('spawn')->ioloop->stream($stream);
  my $buffer = '';
  $stream->on(
    read => sub {
      $buffer .= pop;
      while (1) {
        my ($len) = $buffer =~ /^([0-9]+)\-/;
        last unless $len and length $buffer >= $len + $+[0];
        my $snippet = substr $buffer, 0, $len + $+[0], '';
        my $args    = $self->deserialize->(substr $snippet, $+[0]);
        $self->emit(progress => @$args);
      }
    }
  );
  $stream->on(
    close => sub {
      return unless $$ == $me;
      waitpid $pid, 0;
      $self->{exit_code} = $? >> 8;
      substr $buffer, 0, 2, '';
      my $results = eval { $self->deserialize->($buffer) } // [];
      $self->$parent(shift(@$results) // $@, @$results);
    }
  );
}

sub progress {
  my ($self, @args) = @_;
  my $serialized = $self->serialize->(\@args);
  print {$self->{writer}} length($serialized), '-', $serialized;
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Subprocess - Subprocesses

=head1 SYNOPSIS

  use Mojo::IOLoop::Subprocess;

  # Operation that would block the event loop for 5 seconds
  my $subprocess = Mojo::IOLoop::Subprocess->new;
  $subprocess->run(
    sub ($subprocess) {
      sleep 5;
      return '♥', 'Mojolicious';
    },
    sub ($subprocess, $err, @results) {
      say "Subprocess error: $err" and return if $err;
      say "I $results[0] $results[1]!";
    }
  );

  # Operation that would block the event loop for 5 seconds (with promise)
  $subprocess->run_p(sub {
    sleep 5;
    return '♥', 'Mojolicious';
  })->then(sub (@results) {
    say "I $results[0] $results[1]!";
  })->catch(sub  {
    my $err = shift;
    say "Subprocess error: $err";
  });

  # Start event loop if necessary
  $subprocess->ioloop->start unless $subprocess->ioloop->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Subprocess> allows L<Mojo::IOLoop> to perform computationally expensive operations in subprocesses,
without blocking the event loop.

=head1 EVENTS

L<Mojo::IOLoop::Subprocess> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

=head2 cleanup

  $subprocess->on(cleanup => sub ($subprocess) {...});

Emitted in the subprocess right before the process will exit.

  $subprocess->on(cleanup => sub ($subprocess) { say "Process $$ is about to exit" });

=head2 progress

  $subprocess->on(progress => sub ($subprocess, @data) {...});

Emitted in the parent process when the subprocess calls the L<progress|/"progress1"> method.

=head2 spawn

  $subprocess->on(spawn => sub ($subprocess) {...});

Emitted in the parent process when the subprocess has been spawned.

  $subprocess->on(spawn => sub ($subprocess) {
    my $pid = $subprocess->pid;
    say "Performing work in process $pid";
  });

=head1 ATTRIBUTES

L<Mojo::IOLoop::Subprocess> implements the following attributes.

=head2 deserialize

  my $cb      = $subprocess->deserialize;
  $subprocess = $subprocess->deserialize(sub {...});

A callback used to deserialize subprocess return values, defaults to using L<Mojo::JSON>.

  $subprocess->deserialize(sub ($bytes) { return [] });

=head2 ioloop

  my $loop    = $subprocess->ioloop;
  $subprocess = $subprocess->ioloop(Mojo::IOLoop->new);

Event loop object to control, defaults to the global L<Mojo::IOLoop> singleton. Note that this attribute is weakened.

=head2 serialize

  my $cb      = $subprocess->serialize;
  $subprocess = $subprocess->serialize(sub {...});

A callback used to serialize subprocess return values, defaults to using L<Mojo::JSON>.

  $subprocess->serialize(sub ($array) { return '' });

=head1 METHODS

L<Mojo::IOLoop::Subprocess> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 exit_code

  my $code = $subprocess->exit_code;

Returns the subprocess exit code, or C<undef> if the subprocess is still running.

=head2 pid

  my $pid = $subprocess->pid;

Process id of the spawned subprocess if available.

=head2 progress

  $subprocess->progress(@data);

Send data serialized with L<Mojo::JSON> to the parent process at any time during the subprocess's execution. Must be
called by the subprocess and emits the L</"progress"> event in the parent process with the data.

  # Send progress information to the parent process
  $subprocess->run(
    sub ($subprocess) {
      $subprocess->progress('0%');
      sleep 5;
      $subprocess->progress('50%');
      sleep 5;
      return 'Hello Mojo!';
    },
    sub ($subprocess, $err, @results) {
      say 'Progress is 100%';
      say $results[0];
    }
  );
  $subprocess->on(progress => sub ($subprocess, @data) { say "Progress is $data[0]" });

=head2 run

  $subprocess = $subprocess->run(sub {...}, sub {...});

Execute the first callback in a child process and wait for it to return one or more values, without blocking
L</"ioloop"> in the parent process. Then execute the second callback in the parent process with the results. The return
values of the first callback and exceptions thrown by it, will be serialized with L<Mojo::JSON>, so they can be shared
between processes.

=head2 run_p

  my $promise = $subprocess->run_p(sub {...});

Same as L</"run">, but returns a L<Mojo::Promise> object instead of accepting a second callback.

  $subprocess->run_p(sub {
    sleep 5;
    return '♥', 'Mojolicious';
  })->then(sub (@results) {
    say "I $results[0] $results[1]!";
  })->catch(sub ($err) {
    say "Subprocess error: $err";
  })->wait;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
