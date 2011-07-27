package Mojo::Transaction;
use Mojo::Base -base;

use Carp 'croak';

has [qw/connection kept_alive local_address local_port previous remote_port/];
has [qw/on_finish on_resume/] => sub {
  sub {1}
};
has keep_alive => 0;

# "Please don't eat me! I have a wife and kids. Eat them!"
sub client_read  { croak 'Method "client_read" not implemented by subclass' }
sub client_write { croak 'Method "client_write" not implemented by subclass' }

sub error {
  my $self = shift;
  my $req  = $self->req;
  return $req->error if $req->error;
  my $res = $self->res;
  return $res->error if $res->error;
  return;
}

sub is_done {
  return 1 if (shift->{state} || '') eq 'done';
  return;
}

sub is_websocket {0}

sub is_writing {
  return 1 unless my $state = shift->{state};
  return 1
    if $state eq 'write'
      || $state eq 'write_start_line'
      || $state eq 'write_headers'
      || $state eq 'write_body';
  return;
}

sub remote_address {
  my ($self, $address) = @_;

  # Set
  if ($address) {
    $self->{remote_address} = $address;
    return $self;
  }

  # Reverse proxy
  if ($ENV{MOJO_REVERSE_PROXY}) {

    # Forwarded
    my $forwarded = $self->{forwarded_for};
    return $forwarded if $forwarded;

    # Reverse proxy
    if ($forwarded = $self->req->headers->header('X-Forwarded-For')) {

      # Real address
      if ($forwarded =~ /([^,\s]+)$/) {
        $self->{forwarded_for} = $1;
        return $1;
      }
    }
  }

  # Get
  return $self->{remote_address};
}

sub req { croak 'Method "req" not implemented by subclass' }
sub res { croak 'Method "res" not implemented by subclass' }

sub resume {
  my $self = shift;

  # Delayed
  if (($self->{state} || '') eq 'paused') {
    $self->{state} = 'write_body';
  }

  # Writing
  elsif (!$self->is_writing) { $self->{state} = 'write' }

  # Callback
  $self->on_resume->($self);

  return $self;
}

sub server_close {
  my $self = shift;
  $self->on_finish->($self);
  return $self;
}

sub server_read  { croak 'Method "server_read" not implemented by subclass' }
sub server_write { croak 'Method "server_write" not implemented by subclass' }

sub success {
  my $self = shift;
  return $self->res unless $self->error;
  return;
}

1;
__END__

=head1 NAME

Mojo::Transaction - Transaction Base Class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Transaction';

=head1 DESCRIPTION

L<Mojo::Transaction> is an abstract base class for transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction> implements the following attributes.

=head2 C<connection>

  my $connection = $tx->connection;
  $tx            = $tx->connection($connection);

Connection identifier or socket.

=head2 C<keep_alive>

  my $keep_alive = $tx->keep_alive;
  $tx            = $tx->keep_alive(1);

Connection can be kept alive.

=head2 C<kept_alive>

  my $kept_alive = $tx->kept_alive;
  $tx            = $tx->kept_alive(1);

Connection has been kept alive.

=head2 C<local_address>

  my $local_address = $tx->local_address;
  $tx               = $tx->local_address($address);

Local interface address.

=head2 C<local_port>

  my $local_port = $tx->local_port;
  $tx            = $tx->local_port($port);

Local interface port.

=head2 C<on_finish>

  my $cb = $tx->on_finish;
  $tx    = $tx->on_finish(sub {...});

Callback to be invoked when the transaction has been finished.

  $tx->on_finish(sub {
    my $self = shift;
  });

=head2 C<on_resume>

  my $cb = $tx->on_resume;
  $tx    = $tx->on_resume(sub {...});

Callback to be invoked whenever the transaction is resumed.

=head2 C<previous>

  my $previous = $tx->previous;
  $tx          = $tx->previous(Mojo::Transaction->new);

Previous transaction that triggered this followup transaction.

=head2 C<remote_address>

  my $remote_address = $tx->remote_address;
  $tx                = $tx->remote_address($address);

Remote interface address.

=head2 C<remote_port>

  my $remote_port = $tx->remote_port;
  $tx             = $tx->remote_port($port);

Remote interface port.

=head1 METHODS

L<Mojo::Transaction> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<client_read>

  $tx = $tx->client_read($chunk);

Read and process client data.

=head2 C<client_write>

  my $chunk = $tx->client_write;

Write client data.

=head2 C<error>

  my $message          = $message->error;
  my ($message, $code) = $message->error;

Parser errors and codes.

=head2 C<is_done>

  my $done = $tx->is_done;

Check if transaction is done.

=head2 C<is_websocket>

  my $is_websocket = $tx->is_websocket;

Check if transaction is a WebSocket.

=head2 C<is_writing>

  my $writing = $tx->is_writing;

Check if transaction is writing.

=head2 C<req>

  my $req = $tx->req;

Transaction request, usually a L<Mojo::Message::Request> object.

=head2 C<res>

  my $res = $tx->res;

Transaction response, usually a L<Mojo::Message::Response> object.

=head2 C<resume>

  $tx = $tx->resume;

Resume transaction.

=head2 C<server_close>

  $tx = $tx->server_close;

Transaction closed.

=head2 C<server_read>

  $tx = $tx->server_read($chunk);

Read and process server data.

=head2 C<server_write>

  my $chunk = $tx->server_write;

Write server data.

=head2 C<success>

  my $res = $tx->success;

Returns the L<Mojo::Message::Response> object (C<res>) if transaction was
successful or C<undef> otherwise.
Connection and parser errors have only a message in C<error>, 400 and 500
responses also a code.

  if (my $res = $tx->success) {
    print $res->body;
  }
  else {
    my ($message, $code) = $tx->error;
    if ($code) {
      print "$code $message response.\n";
    }
    else {
      print "Connection error: $message\n";
    }
  }

Error messages can be accessed with the C<error> method of the transaction
object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
