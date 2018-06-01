package Mojo::IOLoop::Stream::WebSocketClient;
use Mojo::Base 'Mojo::IOLoop::Stream::HTTPClient';

use Scalar::Util 'weaken';

sub process {
  my ($self, $tx) = @_;
  $self->{tx} = $tx;
  weaken $self;
  $tx->on(resume => sub { $self->_write_content });
  $self->_write_content;
}

sub _finish {
  my $self = shift;
  return ++$self->{closing} && $self->close unless $self->{tx};
  delete($self->{tx})->closed;
  ++$self->{closing} && $self->close_gracefully;
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Stream::WebSocketClient - Non-blocking I/O WebSocket client stream

=head1 SYNOPSIS

  use Mojo::IOLoop::Stream::WebSocketClient;
  use Mojo::Transaction::WebSocket;
  
  # Create transaction
  my $ws = Mojo::Transaction::WebSocket->new;
  $ws->on(message => sub {
    my ($ws, $msg) = @_;
    say "Message: $msg";
  });
  
  # Create stream and process transaction with it
  my $stream = Mojo::IOLoop::Stream::WebSocketClient->new($handle);
  $stream->process($ws);

  # Start reactor if necessary
  $stream->reactor->start unless $stream->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Stream::WebSocketClient> is a container for I/O streams used by
L<Mojo::IOLoop> to support the WebSocket protocol client-side.

=head1 EVENTS

L<Mojo::IOLoop::Stream::WebSocketClient> inherits all events from
L<Mojo::IOLoop::Stream::HTTPClient>.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream::WebSocketClient> inherits all attributes from
L<Mojo::IOLoop::Stream::HTTPClient>.

=head1 METHODS

L<Mojo::IOLoop::Stream::WebSocketClient> inherits all methods from
L<Mojo::IOLoop::Stream::HTTPClient> and implements the following new ones.

=head2 process

  $stream->process(Mojo::Transaction::WebSocket->new);

Process a L<Mojo::Transaction::WebSocket> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

