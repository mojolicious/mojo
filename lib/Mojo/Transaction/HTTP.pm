package Mojo::Transaction::HTTP;
use Mojo::Base 'Mojo::Transaction';

use Mojo::Message::Request;
use Mojo::Message::Response;
use Mojo::Transaction::WebSocket;

has req => sub { Mojo::Message::Request->new };
has res => sub { Mojo::Message::Response->new };

# "What's a wedding?  Webster's dictionary describes it as the act of
#  removing weeds from one's garden."
sub client_read {
  my ($self, $chunk) = @_;

  # EOF
  my $preserved = $self->{state};
  $self->{state} = 'finished' if length $chunk == 0;

  # HEAD response
  my $res = $self->res;
  if ($self->req->method =~ /^HEAD$/i) {
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

  return $self;
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
  if ($self->{state} eq 'write_start_line') {

    # Chunk
    my $buffer = $req->get_start_line_chunk($self->{offset});
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Write headers
    if ($self->{write} <= 0) {
      $self->{state}  = 'write_headers';
      $self->{offset} = 0;
      $self->{write}  = $req->header_size;
    }
  }

  # Headers
  if ($self->{state} eq 'write_headers') {

    # Chunk
    my $buffer = $req->get_header_chunk($self->{offset});
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Write body
    if ($self->{write} <= 0) {
      $self->{state}  = 'write_body';
      $self->{offset} = 0;
      $self->{write}  = $req->body_size;
      $self->{write}  = 1 if $req->is_chunked;
    }
  }

  # Body
  if ($self->{state} eq 'write_body') {

    # Chunk
    my $buffer = $req->get_body_chunk($self->{offset});
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer if defined $buffer;
    $self->{write} = 1 if $req->is_chunked;

    # Read response
    $self->{state} = 'read_response'
      if (defined $buffer && !length $buffer) || $self->{write} <= 0;
  }

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

# DEPRECATED in Smiling Face With Sunglasses!
sub on_request {
  warn <<EOF;
Mojo::Transaction::HTTP->on_request is DEPRECATED in favor of
Mojo::Transaction::HTTP->on!
EOF
  shift->on(request => shift);
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

    # WebSocket
    if (($req->headers->upgrade || '') eq 'websocket') {
      $self->emit(
        request => Mojo::Transaction::WebSocket->new(handshake => $self));
    }

    # HTTP
    else { $self->emit('request') }
  }

  # Expect 100 Continue
  elsif ($req->content->is_parsing_body && !defined $self->{continued}) {
    if (($req->headers->expect || '') =~ /100-continue/i) {
      $self->{state} = 'write';
      $res->code(100);
      $self->{continued} = 0;
    }
  }

  return $self;
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
  if ($self->{state} eq 'write_start_line') {

    # Chunk
    my $buffer = $res->get_start_line_chunk($self->{offset});
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Write headers
    if ($self->{write} <= 0) {
      $self->{state}  = 'write_headers';
      $self->{offset} = 0;
      $self->{write}  = $res->header_size;
    }
  }

  # Headers
  if ($self->{state} eq 'write_headers') {

    # Chunk
    my $buffer = $res->get_header_chunk($self->{offset});
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Write body
    if ($self->{write} <= 0) {

      # HEAD request
      if ($self->req->method =~ /^head$/i) { $self->{state} = 'finished' }

      # Body
      else {
        $self->{state}  = 'write_body';
        $self->{offset} = 0;
        $self->{write}  = $res->body_size;
        $self->{write}  = 1 if $res->is_dynamic;
      }
    }
  }

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
    else {

      # Chunk
      my $buffer = $res->get_body_chunk($self->{offset});
      my $written = defined $buffer ? length $buffer : 0;
      $self->{write}  = $self->{write} - $written;
      $self->{offset} = $self->{offset} + $written;
      $self->{write}  = 1 if $res->is_dynamic;
      if (defined $buffer) {
        $chunk .= $buffer;
        delete $self->{delay};
      }

      # Delayed
      else {
        my $delay = delete $self->{delay};
        $self->{state} = 'paused' if $delay;
        $self->{delay} = 1 unless $delay;
      }

      # Finished
      $self->{state} = 'finished'
        if $self->{write} <= 0 || (defined $buffer && !length $buffer);
    }
  }

  return $chunk;
}

1;
__END__

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
    my ($tx, $ws) = @_;
  });

Emitted when a request is ready and needs to be handled, an optional
L<Mojo::Transaction::WebSocket> object will be passed for WebSocket handshake
requests.

  $tx->on(request => sub {
    my $tx = shift;
    $tx->res->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head1 ATTRIBUTES

L<Mojo::Transaction::HTTP> inherits all attributes from L<Mojo::Transaction>
and implements the following new ones.

=head2 C<req>

  my $req = $tx->req;
  $tx     = $tx->req(Mojo::Message::Request->new);

HTTP 1.1 request, defaults to a L<Mojo::Message::Request> object.

=head2 C<res>

  my $res = $tx->res;
  $tx     = $tx->res(Mojo::Message::Response->new);

HTTP 1.1 response, defaults to a L<Mojo::Message::Response> object.

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
