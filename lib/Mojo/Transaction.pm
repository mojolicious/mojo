package Mojo::Transaction;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Message::Request;
use Mojo::Message::Response;

has [
  qw(kept_alive local_address local_port original_remote_address remote_port)];
has req => sub { Mojo::Message::Request->new };
has res => sub { Mojo::Message::Response->new };

sub client_read  { croak 'Method "client_read" not implemented by subclass' }
sub client_write { croak 'Method "client_write" not implemented by subclass' }

sub closed { shift->completed->emit('finish') }

sub completed { ++$_[0]{completed} and return $_[0] }

sub connection {
  my $self = shift;
  return $self->emit(connection => $self->{connection} = shift) if @_;
  return $self->{connection};
}

sub error { $_[0]->req->error || $_[0]->res->error }

sub is_finished { !!shift->{completed} }

sub is_websocket {undef}

sub remote_address {
  my $self = shift;

  return $self->original_remote_address(@_) if @_;
  return $self->original_remote_address unless $self->req->reverse_proxy;

  # Reverse proxy
  return ($self->req->headers->header('X-Forwarded-For') // '') =~ /([^,\s]+)$/
    ? $1
    : $self->original_remote_address;
}

sub server_read  { croak 'Method "server_read" not implemented by subclass' }
sub server_write { croak 'Method "server_write" not implemented by subclass' }

sub success { $_[0]->error ? undef : $_[0]->res }

1;

=encoding utf8

=head1 NAME

Mojo::Transaction - Transaction base class

=head1 SYNOPSIS

  package Mojo::Transaction::MyTransaction;
  use Mojo::Base 'Mojo::Transaction';

  sub client_read  {...}
  sub client_write {...}
  sub server_read  {...}
  sub server_write {...}

=head1 DESCRIPTION

L<Mojo::Transaction> is an abstract base class for transactions, like
L<Mojo::Transaction::HTTP> and L<Mojo::Transaction::WebSocket>.

=head1 EVENTS

L<Mojo::Transaction> inherits all events from L<Mojo::EventEmitter> and can
emit the following new ones.

=head2 connection

  $tx->on(connection => sub {
    my ($tx, $connection) = @_;
    ...
  });

Emitted when a connection has been assigned to transaction.

=head2 finish

  $tx->on(finish => sub {
    my $tx = shift;
    ...
  });

Emitted when transaction is finished.

=head1 ATTRIBUTES

L<Mojo::Transaction> implements the following attributes.

=head2 kept_alive

  my $bool = $tx->kept_alive;
  $tx      = $tx->kept_alive($bool);

Connection has been kept alive.

=head2 local_address

  my $address = $tx->local_address;
  $tx         = $tx->local_address('127.0.0.1');

Local interface address.

=head2 local_port

  my $port = $tx->local_port;
  $tx      = $tx->local_port(8080);

Local interface port.

=head2 original_remote_address

  my $address = $tx->original_remote_address;
  $tx         = $tx->original_remote_address('127.0.0.1');

Remote interface address.

=head2 remote_port

  my $port = $tx->remote_port;
  $tx      = $tx->remote_port(8081);

Remote interface port.

=head2 req

  my $req = $tx->req;
  $tx     = $tx->req(Mojo::Message::Request->new);

HTTP request, defaults to a L<Mojo::Message::Request> object.

=head2 res

  my $res = $tx->res;
  $tx     = $tx->res(Mojo::Message::Response->new);

HTTP response, defaults to a L<Mojo::Message::Response> object.

=head1 METHODS

L<Mojo::Transaction> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 client_read

  $tx->client_read($bytes);

Read data client-side, used to implement user agents such as L<Mojo::UserAgent>.
Meant to be overloaded in a subclass.

=head2 client_write

  my $bytes = $tx->client_write;

Write data client-side, used to implement user agents such as
L<Mojo::UserAgent>. Meant to be overloaded in a subclass.

=head2 closed

  $tx = $tx->closed;

Same as L</"completed">, but also indicates that all transaction data has been
sent.

=head2 completed

  $tx = $tx->completed;

Low-level method to finalize transaction.

=head2 connection

  my $id = $tx->connection;
  $tx    = $tx->connection($id);

Connection identifier.

=head2 error

  my $err = $tx->error;

Get request or response error and return C<undef> if there is no error,
commonly used together with L</"success">.

  # Longer version
  my $err = $tx->req->error || $tx->res->error;

  # Check for different kinds of errors
  if (my $err = $tx->error) {
    die "$err->{code} response: $err->{message}" if $err->{code};
    die "Connection error: $err->{message}";
  }

=head2 is_finished

  my $bool = $tx->is_finished;

Check if transaction is finished.

=head2 is_websocket

  my $bool = $tx->is_websocket;

False, this is not a L<Mojo::Transaction::WebSocket> object.

=head2 remote_address

  my $address = $tx->remote_address;
  $tx         = $tx->remote_address('127.0.0.1');

Same as L</"original_remote_address"> or the last value of the
C<X-Forwarded-For> header if L</"req"> has been performed through a reverse
proxy.

=head2 server_read

  $tx->server_read($bytes);

Read data server-side, used to implement web servers such as
L<Mojo::Server::Daemon>. Meant to be overloaded in a subclass.

=head2 server_write

  my $bytes = $tx->server_write;

Write data server-side, used to implement web servers such as
L<Mojo::Server::Daemon>. Meant to be overloaded in a subclass.

=head2 success

  my $res = $tx->success;

Returns the L<Mojo::Message::Response> object from L</"res"> if transaction was
successful or C<undef> otherwise. Connection and parser errors have only a
message in L</"error">, C<400> and C<500> responses also a code.

  # Sensible exception handling
  if (my $res = $tx->success) { say $res->body }
  else {
    my $err = $tx->error;
    die "$err->{code} response: $err->{message}" if $err->{code};
    die "Connection error: $err->{message}";
  }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
