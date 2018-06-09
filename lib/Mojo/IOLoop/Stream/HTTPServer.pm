package Mojo::IOLoop::Stream::HTTPServer;
use Mojo::Base 'Mojo::IOLoop::Stream';

use Mojo::Server;
use Mojo::Transaction::WebSocket;
use Mojo::Util 'term_escape';
use Mojo::WebSocket 'server_handshake';
use Scalar::Util 'weaken';

use constant DEBUG => $ENV{MOJO_SERVER_DEBUG} || 0;

has app => sub { Mojo::Server->new->build_app('Mojo::HelloWorld') };
has max_requests => 100;

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(read  => sub { shift->_read_content(shift) });
  $self->on(close => sub { shift->_close });
  return $self;
}

sub _build_tx {
  my $self = shift;

  my $tx = $self->app->build_tx;
  $tx->res->headers->server('Mojolicious (Perl)');
  my $handle = $self->handle;
  unless ($handle->isa('IO::Socket::UNIX')) {
    $tx->local_address($handle->sockhost)->local_port($handle->sockport);
    $tx->remote_address($handle->peerhost)->remote_port($handle->peerport);
  }
  $tx->req->url->base->scheme('https') if $handle->isa('IO::Socket::SSL');

  weaken $self;
  $tx->on(
    request => sub {
      my $tx = shift;

      # WebSocket
      my $req = $tx->req;
      if ($req->is_handshake) {
        my $ws = $self->{next}
          = Mojo::Transaction::WebSocket->new(handshake => $tx);
        $self->emit(request => server_handshake $ws);
      }

      # HTTP
      else { $self->emit(request => $tx) }

      # Last keep-alive request or corrupted connection
      $tx->res->headers->connection('close')
        if ($self->{keep_alive} || 1) >= $self->max_requests || $req->error;

      $tx->on(resume => sub { $self->_write_content });
      $self->_write_content;
    }
  );

  $self->emit(start => $tx);

  # Kept alive if we have more than one request on the connection
  return ++$self->{keep_alive} > 1 ? $tx->kept_alive(1) : $tx;
}

sub _close { delete($_[0]->{tx})->closed if $_[0]->{tx} }

sub _finish {
  my $self = shift;

  # Always remove connection for WebSockets
  return unless my $tx = $self->{tx};

  # Finish transaction
  delete($self->{tx})->closed;

  # Upgrade connection to WebSocket
  if (my $ws = delete $self->{next}) {

    # Successful upgrade
    if ($ws->handshake->res->code == 101) {
      $self->emit(upgrade => $ws->established(1));
    }

    # Failed upgrade
    else { $ws->closed }
  }

  # Close connection if necessary
  return $self->close_gracefully if $tx->error || !$tx->keep_alive;

  # Build new transaction for leftovers
  return unless length(my $leftovers = $tx->req->content->leftovers);
  $self->{tx} = $tx = $self->_build_tx;
  $tx->server_read($leftovers);
}

sub _read_content {
  my ($self, $chunk) = @_;
  my $tx = $self->{tx} ||= $self->_build_tx;
  warn term_escape "-- Server <<< Client (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  $tx->server_read($chunk);
}

sub _url { shift->req->url->to_abs }

sub _write_content {
  my $self = shift;

  # Protect from resume event recursion
  return if !(my $tx = $self->{tx}) || $self->{write_lock};
  local $self->{write_lock} = 1;
  my $chunk = $tx->server_write;
  warn term_escape "-- Server >>> Client (@{[_url($tx)]})\n$chunk\n" if DEBUG;
  my $next
    = $tx->is_finished ? '_finish' : length $chunk ? '_write_content' : undef;
  return $self->write($chunk) unless $next;
  $self->write($chunk => sub { shift->$next() });
}

1;

=encoding utf8

=head1 NAME

Mojo::IOLoop::Stream::HTTPServer - Non-blocking I/O HTTP server stream

=head1 SYNOPSIS

  use Mojo::IOLoop::Server;
  use Mojo::IOLoop::Stream::HTTPServer;
  
  # Create listen socket
  my $server = Mojo::IOLoop::Server->new;
  $server->on(
    accept => sub {
      my $stream = Mojo::IOLoop::Stream::HTTPServer->new(pop);
  
      $stream->on(
        request => sub {
          my ($stream, $tx) = @_;
          $tx->res->code(200);
          $tx->res->headers->content_type('text/plain');
          $tx->res->body('Hello World!');
          $tx->resume;
        }
      );
      $stream->start;
    }
  );
  $server->listen(port => 3000);
  
  # Start reactor if necessary
  $stream->reactor->start unless $stream->reactor->is_running;

=head1 DESCRIPTION

L<Mojo::IOLoop::Stream::HTTPServer> is a container for I/O streams used by
L<Mojo::IOLoop> to support the HTTP protocol server-side.

=head1 EVENTS

L<Mojo::IOLoop::Stream::HTTPServer> inherits all events from
L<Mojo::IOLoop::Stream> and can emit the following new ones.

=head2 request

  $stream->on(request => sub {
    my ($sream, $tx) = @_;
    ...
  });

Emitted when a request is ready and needs to be handled.

  $stream->on(request => sub {
    my ($stream, $tx) = @_;
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body('Hello World!');
    $tx->resume;
  });

=head2 start

  $stream->on(start => sub {
    my ($stream, $tx) = @_;
    ...
  });

Emitted whenever a transaction for a new request is about to start.

=head2 upgrade

  $stream->on(upgrade => sub {
    my ($stream, $ws) = @_;
    ...
  });

Emitted when the connection should be upgraded to the WebSocket protocol.

=head1 ATTRIBUTES

L<Mojo::IOLoop::Stream::HTTPServer> inherits all attributes from
L<Mojo::IOLoop::Stream> and implements the following ones.

=head2 app

  my $app = $stream->app;
  $stream = $stream->app(Mojolicious->new);

Application responsible for building transactions, defaults to a
L<Mojo::HelloWorld> object.

=head2 max_requests

  my $max = $stream->max_requests;
  $stream = $stream->max_requests(250);

Maximum number of keep-alive requests per connection, defaults to C<100>.

=head1 METHODS

L<Mojo::IOLoop::Stream::HTTPServer> inherits all methods from
L<Mojo::IOLoop::Stream> and implements the following new ones.

=head2 new

  my $stream = Mojo::IOLoop::Stream::HTTPServer->new($handle);

Construct a new L<Mojo::IOLoop::Stream::HTTPServer> object.

=head1 DEBUGGING

You can set the C<MOJO_SERVER_DEBUG> environment variable to get some advanced
diagnostics information printed to C<STDERR>.

  MOJO_SERVER_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut

