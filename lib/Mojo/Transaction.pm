package Mojo::Transaction;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Message::Request;
use Mojo::Message::Response;

has [qw(kept_alive local_address local_port previous remote_port)];
has req => sub { Mojo::Message::Request->new };
has res => sub { Mojo::Message::Response->new };

sub client_close {
  my $self = shift;
  $self->res->finish;
  return $self->server_close;
}

sub client_read  { croak 'Method "client_read" not implemented by subclass' }
sub client_write { croak 'Method "client_write" not implemented by subclass' }

sub connection {
  my $self = shift;
  return $self->emit(connection => $self->{connection} = shift) if @_;
  return $self->{connection};
}

sub error {
  my $self = shift;
  my $req  = $self->req;
  return $req->error if $req->error;
  my $res = $self->res;
  return $res->error ? $res->error : undef;
}

sub is_finished { (shift->{state} // '') eq 'finished' }

sub is_websocket {undef}

sub is_writing { (shift->{state} // 'write') eq 'write' }

sub remote_address {
  my $self = shift;

  # New address
  if (@_) {
    $self->{remote_address} = shift;
    return $self;
  }

  # Reverse proxy
  if ($ENV{MOJO_REVERSE_PROXY}) {
    return $self->{forwarded_for} if $self->{forwarded_for};
    my $forwarded = $self->req->headers->header('X-Forwarded-For') // '';
    $forwarded =~ /([^,\s]+)$/ and return $self->{forwarded_for} = $1;
  }

  return $self->{remote_address};
}

sub resume       { shift->_state(qw(write resume)) }
sub server_close { shift->_state(qw(finished finish)) }

sub server_read  { croak 'Method "server_read" not implemented by subclass' }
sub server_write { croak 'Method "server_write" not implemented by subclass' }

sub success { $_[0]->error ? undef : $_[0]->res }

sub _state {
  my ($self, $state, $event) = @_;
  $self->{state} = $state;
  return $self->emit($event);
}

1;

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

L<Mojo::Transaction> is an abstract base class for transactions.

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

=head2 resume

  $tx->on(resume => sub {
    my $tx = shift;
    ...
  });

Emitted when transaction is resumed.

=head1 ATTRIBUTES

L<Mojo::Transaction> implements the following attributes.

=head2 kept_alive

  my $kept_alive = $tx->kept_alive;
  $tx            = $tx->kept_alive(1);

Connection has been kept alive.

=head2 local_address

  my $address = $tx->local_address;
  $tx         = $tx->local_address('127.0.0.1');

Local interface address.

=head2 local_port

  my $port = $tx->local_port;
  $tx      = $tx->local_port(8080);

Local interface port.

=head2 previous

  my $previous = $tx->previous;
  $tx          = $tx->previous(Mojo::Transaction->new);

Previous transaction that triggered this followup transaction.

  # Path of previous request
  say $tx->previous->req->url->path;

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

=head2 client_close

  $tx->client_close;

Transaction closed client-side, used to implement user agents.

=head2 client_read

  $tx->client_read($bytes);

Read data client-side, used to implement user agents. Meant to be overloaded
in a subclass.

=head2 client_write

  my $bytes = $tx->client_write;

Write data client-side, used to implement user agents. Meant to be overloaded
in a subclass.

=head2 connection

  my $connection = $tx->connection;
  $tx            = $tx->connection($connection);

Connection identifier or socket.

=head2 error

  my $err          = $tx->error;
  my ($err, $code) = $tx->error;

Error and code.

=head2 is_finished

  my $success = $tx->is_finished;

Check if transaction is finished.

=head2 is_websocket

  my $false = $tx->is_websocket;

False.

=head2 is_writing

  my $success = $tx->is_writing;

Check if transaction is writing.

=head2 resume

  $tx = $tx->resume;

Resume transaction.

=head2 remote_address

  my $address = $tx->remote_address;
  $tx         = $tx->remote_address('127.0.0.1');

Remote interface address.

=head2 server_close

  $tx->server_close;

Transaction closed server-side, used to implement web servers.

=head2 server_read

  $tx->server_read($bytes);

Read data server-side, used to implement web servers. Meant to be overloaded
in a subclass.

=head2 server_write

  my $bytes = $tx->server_write;

Write data server-side, used to implement web servers. Meant to be overloaded
in a subclass.

=head2 success

  my $res = $tx->success;

Returns the L<Mojo::Message::Response> object (C<res>) if transaction was
successful or C<undef> otherwise. Connection and parser errors have only a
message in C<error>, 400 and 500 responses also a code.

  # Sensible exception handling
  if (my $res = $tx->success) { say $res->body }
  else {
    my ($err, $code) = $tx->error;
    say $code ? "$code response: $err" : "Connection error: $err";
  }

Error messages can be accessed with the C<error> method of the transaction
object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
