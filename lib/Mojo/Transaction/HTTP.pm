package Mojo::Transaction::HTTP;
use Mojo::Base 'Mojo::Transaction';

use Mojo::Message::Request;
use Mojo::Message::Response;

has [qw/on_upgrade on_request/];
has req => sub { Mojo::Message::Request->new };
has res => sub { Mojo::Message::Response->new };

# "What's a wedding?  Webster's dictionary describes it as the act of
#  removing weeds from one's garden."
sub client_read {
  my ($self, $chunk) = @_;

  # Preserve state
  my $preserved = $self->{state};

  # Done
  my $read = length $chunk;
  $self->{state} = 'done' if $read == 0;

  # HEAD response
  my $req = $self->req;
  my $res = $self->res;
  if ($req->method =~ /^head$/i) {
    $res->parse_until_body($chunk);
    $self->{state} = 'done' if $res->content->is_parsing_body;
  }

  # Normal response
  else {
    $res->parse($chunk);

    # Done
    $self->{state} = 'done' if $res->is_done;
  }

  # Unexpected 100 Continue
  if ($self->{state} eq 'done' && ($res->code || '') eq '100') {
    $self->res($res->new);
    $self->{state} = $preserved;
  }

  # Check for errors
  $self->{state} = 'done' if $self->error;

  return $self;
}

sub client_write {
  my $self = shift;

  # Offsets
  $self->{offset} ||= 0;
  $self->{write}  ||= 0;

  # Writing
  my $req = $self->req;
  unless ($self->{state}) {

    # Connection header
    my $headers = $req->headers;
    unless ($headers->connection) {
      if ($self->keep_alive || $self->kept_alive) {
        $headers->connection('keep-alive');
      }
      else { $headers->connection('close') }
    }

    # Ready for next state
    $self->{state} = 'write_start_line';
    $self->{write} = $req->start_line_size;
  }

  # Start line
  my $chunk = '';
  if ($self->{state} eq 'write_start_line') {
    my $buffer = $req->get_start_line_chunk($self->{offset});

    # Written
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Done
    if ($self->{write} <= 0) {
      $self->{state}  = 'write_headers';
      $self->{offset} = 0;
      $self->{write}  = $req->header_size;
    }
  }

  # Headers
  if ($self->{state} eq 'write_headers') {
    my $buffer = $req->get_header_chunk($self->{offset});

    # Written
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Done
    if ($self->{write} <= 0) {

      $self->{state}  = 'write_body';
      $self->{offset} = 0;
      $self->{write}  = $req->body_size;

      # Chunked
      $self->{write} = 1 if $req->is_chunked;
    }
  }

  # Body
  if ($self->{state} eq 'write_body') {
    my $buffer = $req->get_body_chunk($self->{offset});

    # Written
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer if defined $buffer;

    # End
    $self->{state} = 'read_response'
      if defined $buffer && !length $buffer;

    # Chunked
    $self->{write} = 1 if $req->is_chunked;

    # Done
    $self->{state} = 'read_response' if $self->{write} <= 0;
  }

  return $chunk;
}

sub keep_alive {
  my ($self, $keep_alive) = @_;

  # Custom
  if ($keep_alive) {
    $self->{keep_alive} = $keep_alive;
    return $self;
  }

  # No keep alive for 0.9 and 1.0
  my $req     = $self->req;
  my $version = $req->version;
  $self->{keep_alive} ||= 0 if $req->version eq '0.9' || $version eq '1.0';
  my $res = $self->res;
  $version = $res->version;
  $self->{keep_alive} ||= 0 if $version eq '0.9' || $version eq '1.0';

  # Connection headers
  my $req_connection = $req->headers->connection || '';
  my $res_connection = $res->headers->connection || '';

  # Keep alive
  $self->{keep_alive} = 1
    if $req_connection =~ /^keep-alive$/i
      || $res_connection =~ /^keep-alive$/i;

  # Close
  $self->{keep_alive} = 0
    if $req_connection =~ /^close$/i || $res_connection =~ /^close$/i;

  # Default
  $self->{keep_alive} = 1 unless defined $self->{keep_alive};

  return $self->{keep_alive};
}

sub server_leftovers {
  my $self = shift;

  # Check leftovers
  my $req = $self->req;
  return unless $req->content->has_leftovers;
  my $leftovers = $req->leftovers;

  # Done
  $req->{state} = 'done';

  return $leftovers;
}

sub server_read {
  my ($self, $chunk) = @_;

  # Parse
  my $req = $self->req;
  $req->parse($chunk) unless $req->error;
  $self->{state} ||= 'read';

  # Parser error
  my $res     = $self->res;
  my $handled = $self->{handled};
  if ($req->error && !$handled) {

    # Handler callback
    $self->on_request->($self);

    # Close connection
    $res->headers->connection('close');

    # Protect handler from incoming pipelined requests
    $self->{handled} = 1;
  }

  # EOF
  elsif ((length $chunk == 0) || ($req->is_done && !$handled)) {

    # Upgrade callback
    my $ws;
    $ws = $self->on_upgrade->($self) if $req->headers->upgrade;

    # Handler callback
    $self->on_request->($ws ? ($ws, $self) : $self);

    # Protect handler from incoming pipelined requests
    $self->{handled} = 1;
  }

  # Expect 100 Continue
  elsif ($req->content->is_parsing_body && !defined $self->{continued}) {
    if (($req->headers->expect || '') =~ /100-continue/i) {

      # Writing
      $self->{state} = 'write';

      # Continue
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

  # Offsets
  $self->{offset} ||= 0;
  $self->{write}  ||= 0;

  # Writing
  my $res = $self->res;
  if ($self->{state} eq 'write') {

    # Connection header
    my $headers = $res->headers;
    unless ($headers->connection) {
      if   ($self->keep_alive) { $headers->connection('keep-alive') }
      else                     { $headers->connection('close') }
    }

    # Ready for next state
    $self->{state} = 'write_start_line';
    $self->{write} = $res->start_line_size;
  }

  # Start line
  if ($self->{state} eq 'write_start_line') {
    my $buffer = $res->get_start_line_chunk($self->{offset});

    # Written
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Done
    if ($self->{write} <= 0) {
      $self->{state}  = 'write_headers';
      $self->{offset} = 0;
      $self->{write}  = $res->header_size;
    }
  }

  # Headers
  if ($self->{state} eq 'write_headers') {
    my $buffer = $res->get_header_chunk($self->{offset});

    # Written
    my $written = defined $buffer ? length $buffer : 0;
    $self->{write}  = $self->{write} - $written;
    $self->{offset} = $self->{offset} + $written;
    $chunk .= $buffer;

    # Done
    if ($self->{write} <= 0) {

      # HEAD request
      if ($self->req->method =~ /^head$/i) {

        # Don't send body if request method is HEAD
        $self->{state} = 'done';
      }

      # Body
      else {
        $self->{state}  = 'write_body';
        $self->{offset} = 0;
        $self->{write}  = $res->body_size;

        # Dynamic
        $self->{write} = 1 if $res->is_dynamic;
      }
    }
  }

  # Body
  if ($self->{state} eq 'write_body') {

    # 100 Continue
    if ($self->{write} <= 0) {

      # Continue done
      if (defined $self->{continued} && $self->{continued} == 0) {
        $self->{continued} = 1;
        $self->{state}     = 'read';

        # New response after continue
        $self->res($res->new);
      }

      # Everything done
      elsif (!defined $self->{continued}) { $self->{state} = 'done' }
    }

    # Normal body
    else {
      my $buffer = $res->get_body_chunk($self->{offset});

      # Written
      my $written = defined $buffer ? length $buffer : 0;
      $self->{write}  = $self->{write} - $written;
      $self->{offset} = $self->{offset} + $written;
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

      # Dynamic
      $self->{write} = 1 if $res->is_dynamic;

      # Done
      $self->{state} = 'done'
        if $self->{write} <= 0 || (defined $buffer && !length $buffer);
    }
  }

  return $chunk;
}

1;
__END__

=head1 NAME

Mojo::Transaction::HTTP - HTTP 1.1 Transaction Container

=head1 SYNOPSIS

  use Mojo::Transaction::HTTP;

  my $tx = Mojo::Transaction::HTTP->new;

  my $req = $tx->req;
  my $res = $tx->res;

  my $keep_alive = $tx->keep_alive;

=head1 DESCRIPTION

L<Mojo::Transaction::HTTP> is a container for HTTP 1.1 transactions as
described in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Transaction::HTTP> inherits all attributes from L<Mojo::Transaction>
and implements the following new ones.

=head2 C<on_upgrade>

  my $cb = $tx->on_upgrade;
  $tx    = $tx->on_upgrade(sub {...});

Callback to be invoked for WebSocket upgrades.

=head2 C<on_request>

  my $cb = $tx->on_request;
  $tx    = $tx->on_request(sub {...});

Callback to be invoked for requests.

=head2 C<req>

  my $req = $tx->req;
  $tx     = $tx->req(Mojo::Message::Request->new);

HTTP 1.1 request, by default a L<Mojo::Message::Request> object.

=head2 C<res>

  my $res = $tx->res;
  $tx     = $tx->res(Mojo::Message::Response->new);

HTTP 1.1 response, by default a L<Mojo::Message::Response> object.

=head1 METHODS

L<Mojo::Transaction::HTTP> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<client_read>

  $tx = $tx->client_read($chunk);

Read and process client data.

=head2 C<client_write>

  my $chunk = $tx->client_write;

Write client data.

=head2 C<keep_alive>

  my $keep_alive = $tx->keep_alive;
  $tx            = $tx->keep_alive(1);

Connection can be kept alive.

=head2 C<server_leftovers>

  my $leftovers = $tx->server_leftovers;

Leftovers from the server request, used for pipelining.

=head2 C<server_read>

  $tx = $tx->server_read($chunk);

Read and process server data.

=head2 C<server_write>

  my $chunk = $tx->server_write;

Write server data.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
