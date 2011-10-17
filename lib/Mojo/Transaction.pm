package Mojo::Transaction;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';

has [qw/connection kept_alive local_address local_port previous remote_port/];

# "Please don't eat me! I have a wife and kids. Eat them!"
sub client_close { shift->server_close(@_) }

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

sub is_websocket {undef}

sub is_writing {
  return 1 unless my $state = shift->{state};
  return 1 if $state ~~ [qw/write write_start_line write_headers write_body/];
  return;
}

# DEPRECATED in Smiling Face With Sunglasses!
sub on_finish {
  warn <<EOF;
Mojo::Transaction->on_finish is DEPRECATED in favor of using
Mojo::Transaction->on!!!
EOF
  shift->on(finish => shift);
}

# DEPRECATED in Smiling Face With Sunglasses!
sub on_resume {
  warn <<EOF;
Mojo::Transaction->on_resume is DEPRECATED in favor of using
Mojo::Transaction->on!!!
EOF
  shift->on(resume => shift);
}

sub remote_address {
  my ($self, $address) = @_;

  # New address
  if ($address) {
    $self->{remote_address} = $address;
    return $self;
  }

  # Reverse proxy
  if ($ENV{MOJO_REVERSE_PROXY}) {
    return $self->{forwarded_for} if $self->{forwarded_for};
    return $self->{forwarded_for} = $1
      if ($self->req->headers->x_forwarded_for || '') =~ /([^,\s]+)$/;
  }

  return $self->{remote_address};
}

sub req { croak 'Method "req" not implemented by subclass' }
sub res { croak 'Method "res" not implemented by subclass' }

sub resume {
  my $self = shift;
  if (($self->{state} || '') eq 'paused') { $self->{state} = 'write_body' }
  elsif (!$self->is_writing) { $self->{state} = 'write' }
  $self->emit('resume');
  return $self;
}

sub server_close {
  my $self = shift;
  $self->emit('finish');
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

Mojo::Transaction - Transaction base class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Transaction';

=head1 DESCRIPTION

L<Mojo::Transaction> is an abstract base class for transactions.

=head1 EVENTS

L<Mojo::Transaction> can emit the following events.

=head2 C<finish>

  $tx->on(finish => sub {
    my $tx = shift;
  });

Emitted when a transaction is finished.

=head2 C<resume>

  $tx->on(resume => sub {
    my $tx = shift;
  });

Emitted when a transaction is resumed.

=head1 ATTRIBUTES

L<Mojo::Transaction> implements the following attributes.

=head2 C<connection>

  my $connection = $tx->connection;
  $tx            = $tx->connection($connection);

Connection identifier or socket.

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

L<Mojo::Transaction> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<client_close>

  $tx = $tx->client_close;

Transaction closed.

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

  my $success = $tx->is_done;

Check if transaction is done.

=head2 C<is_websocket>

  my $false = $tx->is_websocket;

False.

=head2 C<is_writing>

  my $success = $tx->is_writing;

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
    say $res->body;
  }
  else {
    my ($message, $code) = $tx->error;
    if ($code) {
      say "$code $message response.";
    }
    else {
      say "Connection error: $message";
    }
  }

Error messages can be accessed with the C<error> method of the transaction
object.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
