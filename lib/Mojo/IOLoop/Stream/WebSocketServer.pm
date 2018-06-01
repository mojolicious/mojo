package Mojo::IOLoop::Stream::WebSocketServer;
use Mojo::Base 'Mojo::IOLoop::Stream::HTTPServer';

use Scalar::Util 'weaken';

sub process {
  my ($self, $tx) = @_;
  $self->{tx} = $tx;
  weaken $self;
  $tx->on(resume => sub { $self->_write_content });
  $self->_write_content;
}

sub _close { delete($_[0]->{tx})->closed if $_[0]->{tx} }

sub _finish { shift->close_gracefully }

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Stream::WebSocketServer - Non-blocking I/O WebSocket server stream

=head1 SYNOPSIS

  use Mojo::IOLoop::Stream::WebSocketServer;
  use Mojo::Transaction::WebSocket;
  
  # Create transaction
  my $ws = Mojo::Transaction::WebSocket->new;
  $ws->on(message => sub {
    my ($ws, $msg) = @_;
    say "Message: $msg";
  });

  # Create stream and process transaction with it
  my $stream = Mojo::IOLoop::Stream::WebSocketServer->new($handle);
  $stream->process($ws);

  # Start reactor if necessary
  $stream->reactor->start unless $stream->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Stream::WebSocketServer> is a container for I/O streams used by
L<Mojo::IOLoop> to support the WebSocket protocol server-side.

=head1 EVENTS

L<Mojo::IOLoop::Stream::WEBSocketServer> inherits all events from
L<Mojo::IOLoop::Stream::HTTPServer>.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream::WebSocketServer> inherits all attributes from
L<Mojo::IOLoop::Stream::HTTPServer>.

=head1 METHODS

L<Mojo::IOLoop::Stream::WebSocketServer> inherits all methods from
L<Mojo::IOLoop::Stream::HTTPServer> and implements the following new ones.

=head2 process

  $stream->process(Mojo::Transaction::WebSocket->new);

Process a L<Mojo::Transaction::WebSocket> object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

