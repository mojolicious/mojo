package Mojo::Server::FastCGI;
use Mojo::Base 'Mojo::Server';

use Errno qw/EAGAIN EINTR EWOULDBLOCK/;
use IO::Socket;

use constant DEBUG => $ENV{MOJO_FASTCGI_DEBUG} || 0;

# Roles
my @ROLES = qw/RESPONDER  AUTHORIZER FILTER/;
my %ROLE_NUMBERS;
{
  my $i = 1;
  for my $role (@ROLES) {
    $ROLE_NUMBERS{$role} = $i;
    $i++;
  }
}

# Types
my @TYPES = qw/
  BEGIN_REQUEST
  ABORT_REQUEST
  END_REQUEST
  PARAMS
  STDIN
  STDOUT
  STDERR
  DATA
  GET_VALUES
  GET_VALUES_RESULT
  UNKNOWN_TYPE
  /;
my %TYPE_NUMBERS;
{
  my $i = 1;
  for my $type (@TYPES) {
    $TYPE_NUMBERS{$type} = $i;
    $i++;
  }
}

# "Wow! Homer must have got one of those robot cars!
#  *Car crashes in background*
#  Yeah, one of those AMERICAN robot cars."
sub accept_connection {
  my $self = shift;

  # Listen socket
  unless ($self->{listen}) {
    my $listen = IO::Socket->new;

    # Open
    unless ($listen->fdopen(0, 'r')) {
      $self->app->log->error("Can't open FastCGI socket fd0: $!");
      return;
    }

    $self->{listen} = $listen;
  }
  $self->app->log->debug('FastCGI listen socket opened.') if DEBUG;

  # Accept
  my $c;
  unless ($c = $self->{listen}->accept) {
    $self->app->log->error("Can't accept FastCGI connection: $!");
    return;
  }
  $self->app->log->debug('Accepted FastCGI connection.') if DEBUG;

  return $c;
}

sub read_record {
  my ($self, $c) = @_;
  return unless $c;

  # Header
  my $header = $self->_read_chunk($c, 8);
  return unless $header;
  my ($version, $type, $id, $clen, $plen) = unpack 'CCnnC', $header;

  # Body
  my $body = $self->_read_chunk($c, $clen + $plen);

  # No content, just paddign bytes
  $body = undef unless $clen;

  # Ignore padding bytes
  $body = $plen ? substr($body, 0, $clen, '') : $body;

  if (DEBUG) {
    my $t = $self->type_name($type);
    $self->app->log->debug(
      qq/Reading FastCGI record: $type - $id - "$body"./);
  }

  return $self->type_name($type), $id, $body;
}

sub read_request {
  my ($self, $c) = @_;
  $self->app->log->debug('Reading FastCGI request.') if DEBUG;

  # Transaction
  my $tx = $self->on_transaction->($self);
  $tx->connection($c);
  my $req = $tx->req;

  # Type
  my ($type, $id, $body) = $self->read_record($c);
  unless ($type && $type eq 'BEGIN_REQUEST') {
    $self->app->log->error("First FastCGI record wasn't a begin request.");
    return;
  }
  $ENV{FCGI_ID} = $tx->{fcgi_id} = $id;

  # Role/Flags
  my ($role, $flags) = unpack 'nC', $body;
  $ENV{FCGI_ROLE} = $tx->{fcgi_role} = $self->role_name($role);

  # Slurp
  my $buffer = '';
  my $env    = {};
  while (($type, $id, $body) = $self->read_record($c)) {

    # Wrong id
    next unless $id == $tx->{fcgi_id};

    # Params
    if ($type eq 'PARAMS') {

      # Normal param chunk
      if ($body) {
        $buffer .= $body;
        next;
      }

      # Params done
      while (length $buffer) {

        # Name and value length
        my $name_len  = $self->_nv_length(\$buffer);
        my $value_len = $self->_nv_length(\$buffer);

        # Name and value
        my $name  = substr $buffer, 0, $name_len,  '';
        my $value = substr $buffer, 0, $value_len, '';

        # Environment
        $env->{$name} = $value;
        $self->app->log->debug(qq/FastCGI param: $name - "$value"./)
          if DEBUG;

        # Store connection information
        $tx->remote_address($value) if $name =~ /REMOTE_ADDR/i;
        $tx->local_port($value)     if $name =~ /SERVER_PORT/i;
      }
    }

    # Stdin
    elsif ($type eq 'STDIN') {

      # Environment
      if (keys %$env) {
        $req->parse($env);
        $env = {};
      }

      # EOF
      last unless $body;

      # Chunk
      $req->parse($body);

      # Error
      return $tx if $req->error;
    }
  }

  return $tx;
}

sub role_name {
  my ($self, $role) = @_;
  return unless $role;
  return $ROLES[$role - 1];
}

sub role_number {
  my ($self, $role) = @_;
  return unless $role;
  return $ROLE_NUMBERS{uc $role};
}

sub run {
  my $self = shift;

  # Preload application
  $self->app;

  # New incoming request
  while (my $c = $self->accept_connection) {

    # Request
    my $tx = $self->read_request($c);

    # Error
    unless ($tx) {
      $self->app->log->error("No transaction for FastCGI request.");
      next;
    }

    # Handle
    $self->app->log->debug('Handling FastCGI request.') if DEBUG;
    $self->on_request->($self, $tx);

    # Response
    $self->write_response($tx);

    # Finish transaction
    $tx->on_finish->($tx);
  }
}

sub type_name {
  my ($self, $type) = @_;
  return unless $type;
  return $TYPES[$type - 1];
}

sub type_number {
  my ($self, $type) = @_;
  return unless $type;
  return $TYPE_NUMBERS{uc $type};
}

sub write_records {
  my ($self, $c, $type, $id, $body) = @_;
  return unless defined $c && defined $type && defined $id;
  $body ||= '';

  # Write records
  my $empty    = $body ? 0 : 1;
  my $offset   = 0;
  my $body_len = length $body;
  while (($body_len > 0) || $empty) {

    # Need to split content
    my $payload_len = $body_len > 32 * 1024 ? 32 * 1024 : $body_len;
    my $pad_len = (8 - ($payload_len % 8)) % 8;

    # FCGI version 1 record
    my $template = "CCnnCxa${payload_len}x$pad_len";

    if (DEBUG) {
      my $chunk = substr($body, $offset, $payload_len);
      $self->app->log->debug(
        qq/Writing FastCGI record: $type - $id - "$chunk"./);
    }

    # Write whole record
    my $record = pack $template, 1, $self->type_number($type), $id,
      $payload_len,
      $pad_len,
      substr($body, $offset, $payload_len);
    my $woffset = 0;
    while ($woffset < length $record) {
      my $written = $c->syswrite($record, undef, $woffset);

      # Error
      unless (defined $written) {

        # Retry
        next if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;

        # Write error
        return;
      }

      $woffset += $written;
    }
    $body_len -= $payload_len;
    $offset += $payload_len;

    # Done
    last if $empty;
  }

  return 1;
}

sub write_response {
  my ($self, $tx) = @_;
  $self->app->log->debug('Writing FastCGI response.') if DEBUG;

  # Status
  my $res     = $tx->res;
  my $code    = $res->code || 404;
  my $message = $res->message || $res->default_message;
  $res->headers->status("$code $message") unless $res->headers->status;

  # Fix headers
  $res->fix_headers;

  # Headers
  my $c      = $tx->connection;
  my $offset = 0;
  while (1) {
    my $chunk = $res->get_header_chunk($offset);

    # No headers yet, try again
    unless (defined $chunk) {
      sleep 1;
      next;
    }

    # End of headers
    last unless length $chunk;

    # Headers
    $offset += length $chunk;
    return
      unless $self->write_records($c, 'STDOUT', $tx->{fcgi_id}, $chunk);
  }

  # Body
  $offset = 0;
  while (1) {
    my $chunk = $res->get_body_chunk($offset);

    # No content yet, try again
    unless (defined $chunk) {
      sleep 1;
      next;
    }

    # End of content
    last unless length $chunk;

    # Content
    $offset += length $chunk;
    return
      unless $self->write_records($c, 'STDOUT', $tx->{fcgi_id}, $chunk);
  }

  # The end
  return
    unless $self->write_records($c, 'STDOUT', $tx->{fcgi_id}, undef);
  return
    unless $self->write_records($c, 'END_REQUEST', $tx->{fcgi_id},
    pack('CCCCCCCC', 0));
}

sub _nv_length {
  my ($self, $bodyref) = @_;

  # Try first byte
  my $len = unpack 'C', substr($$bodyref, 0, 1, '');

  # 4 byte length
  if ($len & 0x80) {
    $len = pack 'C', $len & 0x7F;
    substr $len, 1, 0, substr($$bodyref, 0, 3, '');
    $len = unpack 'N', $len;
  }

  return $len;
}

sub _read_chunk {
  my ($self, $c, $len) = @_;

  # Read
  my $chunk = '';
  while (length $chunk < $len) {
    my $read = $c->sysread(my $buffer, $len - length $chunk, 0);
    unless (defined $read) {
      next if $! == EAGAIN || $! == EINTR || $! == EWOULDBLOCK;
      last;
    }
    last unless $read;
    $chunk .= $buffer;
  }

  return $chunk;
}

1;
__END__

=head1 NAME

Mojo::Server::FastCGI - FastCGI Server

=head1 SYNOPSIS

  use Mojo::Server::FastCGI;

  my $fcgi = Mojo::Server::FastCGI->new;
  $fcgi->on_request(sub {
    my ($self, $tx) = @_;

    # Request
    my $method = $tx->req->method;
    my $path   = $tx->req->url->path;

    # Response
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body("$method request for $path!");

    # Resume transaction
    $tx->resume;
  });
  $fcgi->run;

=head1 DESCRIPTION

L<Mojo::Server::FastCGI> is a portable pure-Perl FastCGI implementation as
described in the C<FastCGI Specification>.

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

=head1 ATTRIBUTES

L<Mojo::Server::FastCGI> inherits all attributes from L<Mojo::Server>.

=head1 METHODS

L<Mojo::Server::FastCGI> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<accept_connection>

  my $c = $fcgi->accept_connection;

Accept FastCGI connection.

=head2 C<read_record>

  my ($type, $id, $body) = $fcgi->read_record($c);

Parse FastCGI record.

=head2 C<read_request>

  my $tx = $fcgi->read_request($c);

Parse FastCGI request.

=head2 C<role_name>

  my $name = $fcgi->role_name(3);

FastCGI role name.

=head2 C<role_number>

  my $number = $fcgi->role_number('FILTER');

FastCGI role number.

=head2 C<run>

  $fcgi->run;

Start FastCGI.

=head2 C<type_name>

  my $name = $fcgi->type_name(5);

FastCGI type name.

=head2 C<type_number>

  my $number = $fcgi->type_number('STDIN');

FastCGI type number.

=head2 C<write_records>

  $fcgi->write_record($c, 'STDOUT', $id, 'HTTP/1.1 200 OK');

Write FastCGI record.

=head2 C<write_response>

  $fcgi->write_response($tx);

Write FastCGI response.

=head1 DEBUGGING

You can set the C<MOJO_FASTCGI_DEBUG> environment variable to get some
advanced diagnostics information sent to the L<Mojo> logger as C<debug>
messages.

  MOJO_FASTCGI_DEBUG=1

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
