package Mojo::IOLoop::Stream::HTTPClient;
use Mojo::Base 'Mojo::IOLoop::Stream';

use Mojo::Transaction::WebSocket;
use Mojo::Util 'term_escape';
use Mojo::WebSocket 'challenge';
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_CLIENT_DEBUG} || 0;

has request_timeout => sub { $ENV{MOJO_REQUEST_TIMEOUT} // 0 };

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(read => sub { shift->_read_content(shift) });
  $self->on(close => sub { $_[0]->{closing}++ || $_[0]->_finish(1) });
  return $self;
}

sub process {
  my ($self, $tx) = @_;

  $self->{tx} = $tx;
  my $handle = $self->handle;
  unless ($handle->isa('IO::Socket::UNIX')) {
    $tx->local_address($handle->sockhost)->local_port($handle->sockport);
    $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);
  }

  weaken $self;
  $tx->on(resume => sub { $self->_write_content });
  if (my $timeout = $self->request_timeout) {
    $self->{req_timeout} = $self->reactor->timer(
      $timeout => sub { $self->_error('Request timeout') });
  }
  $self->_write_content;
}

sub _error {
  my ($self, $err) = @_;
  $self->{tx}->res->error({message => $err}) if $self->{tx};
  $self->_finish(1);
}

sub _finish {
  my ($self, $close) = @_;

  # Remove request timeout and finish transaction
  $self->reactor->remove($self->{req_timeout}) if $self->{req_timeout};
  return ++$self->{closing} && $self->close unless my $tx = delete $self->{tx};

  # Premature connection close
  my $res = $tx->res->finish;
  if ($close && !$res->code && !$res->error) {
    $res->error({message => 'Premature connection close'});
  }

  # Upgrade connection to WebSocket
  if (my $ws = $self->_upgrade($tx)) {
    $self->emit(upgrade => $ws);
    return $ws->client_read($ws->handshake->res->content->leftovers);
  }

  ++$self->{closing} && $self->close_gracefully
    if $tx->error || !$tx->keep_alive;
  $res->error({message => $res->message, code => $res->code}) if $res->is_error;
  $tx->closed;
}

sub _read_content {
  my ($self, $chunk) = @_;

  # Corrupted connection
  return $self->close unless my $tx = $self->{tx};

  warn term_escape "-- Client <<< Server (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  $tx->client_read($chunk);
  $self->_finish if $tx->is_finished;
}

sub _upgrade {
  my ($self, $tx) = @_;
  my $code = $tx->res->code // 0;
  return undef unless $tx->req->is_handshake && $code == 101;
  my $ws = Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1);
  return challenge($ws) ? $ws->established(1) : undef;
}

sub _url { shift->req->url->to_abs }

sub _write_content {
  my $self = shift;

  # Protect from resume event recursion
  return if !(my $tx = $self->{tx}) || $self->{cont_writing};
  local $self->{cont_writing} = 1;
  my $chunk = $tx->client_write;
  warn term_escape "-- Client >>> Server (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  return unless length $chunk;
  $self->write($chunk => sub { $_[0]->_write_content });
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Stream::HTTPClient - Non-blocking I/O HTTP client stream

=head1 SYNOPSIS

  use Mojo::IOLoop::Client;
  use Mojo::IOLoop::Stream::HTTPClient;
  use Mojo::Transaction::HTTP;
  
  # Create transaction
  my $tx = Mojo::Transaction::HTTP->new;
  $tx->req->method('GET')
  $tx->url->parse('https://mojolicious.org');
  $tx->on(
    finish => sub {
      my $tx = shift;
      say $tx->res->code;
    }
  );
  
  # Create socket connection
  my $client = Mojo::IOLoop::Client->new;
  $client->on(
    connect => sub {
      my $stream = Mojo::IOLoop::Stream::HTTPClient->new(pop);
      $stream->start;
      $stream->process($tx);
    }
  );
  $client->connect(address => 'mojolicious.org', port => 80);

  # Start reactor if necessary
  $stream->reactor->start unless $stream->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Stream::HTTPClient> is a container for I/O streams used by
L<Mojo::IOLoop> to support the HTTP protocol client-side.

=head1 EVENTS

L<Mojo::IOLoop::Stream::HTTPClient> inherits all events from
L<Mojo::IOLoop::Stream> and can emit the following new ones.

=head2 upgrade

  $stream->on(upgrade => sub {
    my ($stream, $ws) = @_;
    ...
  });

Emitted when the connection should be upgraded to the WebSocket protocol.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream::HTTPClient> inherits all attributes from
L<Mojo::IOLoop::Stream> and implements the following ones.

=head2 request_timeout

  my $timeout = $stream->request_timeout;
  $stream     = $stream->request_timeout(5);

Maximum amount of time in seconds sending the request and receiving a whole
response may take before getting canceled, defaults to the value of the
C<MOJO_REQUEST_TIMEOUT> environment variable or C<0>. Setting the value to C<0>
will allow to wait indefinitely.

=head1 METHODS

L<Mojo::IOLoop::Stream::HTTPClient> inherits all methods from
L<Mojo::IOLoop::Stream> and implements the following new ones.

=head2 new

  my $stream = Mojo::IOLoop::Stream::HTTPClient->new($handle);

Construct a new L<Mojo::IOLoop::Stream::HTTPClient> object.

=head2 process

  $stream->process(Mojo::Transaction::HTTP->new);

Process a L<Mojo::Transaction::HTTP> object with the current connection.

=head1 DEBUGGING

You can set the C<MOJO_CLIENT_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_CLIENT_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

