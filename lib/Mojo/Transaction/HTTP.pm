package Mojo::Transaction::HTTP;
use Mojo::Base 'Mojo::Transaction';

use Mojo::Transaction::WebSocket;

# "What's a wedding?  Webster's dictionary describes it as the act of
#  removing weeds from one's garden."
sub client_read {
  my ($self, $chunk) = @_;

  # EOF
  my $preserved = $self->{state};
  $self->{state} = 'finished' if length $chunk == 0;

  # HEAD response
  my $res = $self->res;
  if ($self->req->method eq 'HEAD') {
    $res->parse_until_body($chunk);
    $self->{state} = 'finished' if $res->content->is_parsing_body;
  }

  # Normal response
  else {
    $res->parse($chunk);
    $self->{state} = 'finished' if $res->is_finished;
  }

  # Unexpected 100 Continue
  if ($self->{state} eq 'finished' && ($res->code || '') eq '100') {
    $self->res($res->new);
    $self->{state} = $preserved;
  }

  # Check for errors
  $self->{state} = 'finished' if $self->error;
}

sub client_write {
  my $self = shift;

  # Writing
  $self->{offset} ||= 0;
  $self->{write}  ||= 0;
  my $req = $self->req;
  unless ($self->{state}) {

    # Connection header
    my $headers = $req->headers;
    unless ($headers->connection) {
      if   ($self->keep_alive) { $headers->connection('keep-alive') }
      else                     { $headers->connection('close') }
    }

    # Write start line
    $self->{state} = 'write_start_line';
    $self->{write} = $req->start_line_size;
  }

  # Start line
  my $chunk = '';
  $chunk .= $self->_start_line($req) if $self->{state} eq 'write_start_line';

  # Headers
  $chunk .= $self->_headers($req, 0) if $self->{state} eq 'write_headers';

  # Body
  $chunk .= $self->_body($req, 0) if $self->{state} eq 'write_body';

  return $chunk;
}

sub keep_alive {
  my $self = shift;

  # Close
  my $req      = $self->req;
  my $res      = $self->res;
  my $req_conn = lc($req->headers->connection || '');
  my $res_conn = lc($res->headers->connection || '');
  return if $req_conn eq 'close' || $res_conn eq 'close';

  # Keep alive
  return 1 if $req_conn eq 'keep-alive' || $res_conn eq 'keep-alive';

  # No keep alive for 0.9 and 1.0
  return if $req->version ~~ [qw/0.9 1.0/];
  return if $res->version ~~ [qw/0.9 1.0/];

  return 1;
}

sub server_leftovers {
  my $self = shift;

  # Check for leftovers
  my $req = $self->req;
  return unless $req->has_leftovers;
  $req->{state} = 'finished';

  return $req->leftovers;
}

sub server_read {
  my ($self, $chunk) = @_;

  # Parse
  my $req = $self->req;
  $req->parse($chunk) unless $req->error;
  $self->{state} ||= 'read';

  # Parser error
  my $res = $self->res;
  if ($req->error && !$self->{handled}++) {
    $self->emit('request');
    $res->headers->connection('close');
  }

  # EOF
  elsif ((length $chunk == 0) || ($req->is_finished && !$self->{handled}++)) {
    $self->emit(
      upgrade => Mojo::Transaction::WebSocket->new(handshake => $self))
      if lc($req->headers->upgrade || '') eq 'websocket';
    $self->emit('request');
  }

  # Expect 100 Continue
  elsif ($req->content->is_parsing_body && !defined $self->{continued}) {
    if (($req->headers->expect || '') =~ /100-continue/i) {
      $self->{state} = 'write';
      $res->code(100);
      $self->{continued} = 0;
    }
  }
}

sub server_write {
  my $self = shift;

  # Not writing
  my $chunk = '';
  return $chunk unless $self->{state};

  # Writing
  $self->{offset} ||= 0;
  $self->{write}  ||= 0;
  my $res = $self->res;
  if ($self->{state} eq 'write') {

    # Connection header
    my $headers = $res->headers;
    unless ($headers->connection) {
      if   ($self->keep_alive) { $headers->connection('keep-alive') }
      else                     { $headers->connection('close') }
    }

    # Write start line
    $self->{state} = 'write_start_line';
    $self->{write} = $res->start_line_size;
  }

  # Start line
  $chunk .= $self->_start_line($res) if $self->{state} eq 'write_start_line';

  # Headers
  $chunk .= $self->_headers($res, 1) if $self->{state} eq 'write_headers';

  # Body
  if ($self->{state} eq 'write_body') {

    # 100 Continue
    if ($self->{write} <= 0) {

      # Continued
      if (defined $self->{continued} && $self->{continued} == 0) {
        $self->{continued} = 1;
        $self->{state}     = 'read';
        $self->res($res->new);
      }

      # Finished
      elsif (!defined $self->{continued}) { $self->{state} = 'finished' }
    }

    # Normal body
    else { $chunk .= $self->_body($res, 1) }
  }

  return $chunk;
}

sub _body {
  my ($self, $message, $finish) = @_;

  # Chunk
  my $buffer = $message->get_body_chunk($self->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $self->{write}  = $self->{write} - $written;
  $self->{offset} = $self->{offset} + $written;
  $self->{write}  = 1 if $message->is_dynamic;
  if (defined $buffer) { delete $self->{delay} }

  # Delayed
  else {
    my $delay = delete $self->{delay};
    $self->{state} = 'paused' if $delay;
    $self->{delay} = 1 unless $delay;
  }

  # Finished
  $self->{state} = $finish ? 'finished' : 'read_response'
    if $self->{write} <= 0 || (defined $buffer && !length $buffer);

  return defined $buffer ? $buffer : '';
}

sub _headers {
  my ($self, $message, $head) = @_;

  # Chunk
  my $buffer = $message->get_header_chunk($self->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $self->{write}  = $self->{write} - $written;
  $self->{offset} = $self->{offset} + $written;

  # Write body
  if ($self->{write} <= 0) {

    # HEAD request
    if ($head && $self->req->method eq 'HEAD') { $self->{state} = 'finished' }

    # Body
    else {
      $self->{state}  = 'write_body';
      $self->{offset} = 0;
      $self->{write}  = $message->body_size;
      $self->{write}  = 1 if $message->is_dynamic;
    }
  }

  return $buffer;
}

sub _start_line {
  my ($self, $message) = @_;

  # Chunk
  my $buffer = $message->get_start_line_chunk($self->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $self->{write}  = $self->{write} - $written;
  $self->{offset} = $self->{offset} + $written;

  # Write headers
  if ($self->{write} <= 0) {
    $self->{state}  = 'write_headers';
    $self->{offset} = 0;
    $self->{write}  = $message->header_size;
  }

  return $buffer;
}

1;

=head1 NAME

Mojo::Transaction::HTTP - HTTP 1.1 transaction container

=head1 SYNOPSIS

  use Mojo::Transaction::HTTP;

  my $tx = Mojo::Transaction::HTTP->new;

=head1 DESCRIPTION

L<Mojo::Transaction::HTTP> is a container for HTTP 1.1 transactions as
described in RFC 2616.

=head1 EVENTS

L<Mojo::Transaction::HTTP> inherits all events from L<Mojo::Transaction> and
can emit the following new ones.

=head2 C<request>

  $tx->on(request => sub {
    my $tx = shift;
    ...
  });

Emitted when a request is ready and needs to be handled.

  $tx->on(request => sub {
    my $tx = shift;
    $tx->res->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head2 C<upgrade>

  $tx->on(upgrade => sub {
    my ($tx, $ws) = @_;
    ...
  });

Emitted when transaction gets upgraded to a L<Mojo::Transaction::WebSocket>
object.

  $tx->on(upgrade => sub {
    my ($tx, $ws) = @_;
    $ws->res->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head1 ATTRIBUTES

L<Mojo::Transaction::HTTP> inherits all attributes from L<Mojo::Transaction>.

=head1 METHODS

L<Mojo::Transaction::HTTP> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<client_read>

  $tx->client_read($chunk);

Read and process client data.

=head2 C<client_write>

  my $chunk = $tx->client_write;

Write client data.

=head2 C<keep_alive>

  my $success = $tx->keep_alive;

Check if connection can be kept alive.

=head2 C<server_leftovers>

  my $leftovers = $tx->server_leftovers;

Leftovers from the server request, used for pipelining.

=head2 C<server_read>

  $tx->server_read($chunk);

Read and process server data.

=head2 C<server_write>

  my $chunk = $tx->server_write;

Write server data.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
