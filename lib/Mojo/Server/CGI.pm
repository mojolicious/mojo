package Mojo::Server::CGI;
use Mojo::Base 'Mojo::Server';

has 'nph';

# "Lisa, you're a Buddhist, so you believe in reincarnation.
#  Eventually, Snowball will be reborn as a higher lifeform...
#  like a snowman."
sub run {
  my $self = shift;

  # Environment
  my $tx  = $self->build_tx;
  my $req = $tx->req->parse(\%ENV);

  # Store connection information
  $tx->local_port($ENV{SERVER_PORT})->remote_address($ENV{REMOTE_ADDR});

  # Request body
  binmode STDIN;
  until ($req->is_finished) {
    last unless my $read = STDIN->read(my $buffer, 131072, 0);
    $req->parse($buffer);
  }

  # Handle
  $self->emit(request => $tx);

  # Response start line
  STDOUT->autoflush(1);
  binmode STDOUT;
  my $res = $tx->res;
  return if $self->nph && !_write($res, 'get_start_line_chunk');

  # Response headers
  $res->fix_headers;
  my $code    = $res->code    || 404;
  my $message = $res->message || $res->default_message;
  $res->headers->status("$code $message") unless $self->nph;
  return unless _write($res, 'get_header_chunk');

  # Response body
  return unless _write($res, 'get_body_chunk');

  # Finish transaction
  $tx->server_close;

  return $res->code;
}

sub _write {
  my ($res, $method) = @_;

  # Write chunks to STDOUT
  my $offset = 0;
  while (1) {

    # No chunk yet, try again
    sleep 1 and next unless defined(my $chunk = $res->$method($offset));

    # End of part
    last unless length $chunk;

    # Part
    return unless STDOUT->opened;
    print STDOUT $chunk;
    $offset += length $chunk;
  }

  return 1;
}

1;

=head1 NAME

Mojo::Server::CGI - CGI server

=head1 SYNOPSIS

  use Mojo::Server::CGI;

  my $cgi = Mojo::Server::CGI->new;
  $cgi->unsubscribe('request')
  $cgi->on(request => sub {
    my ($cgi, $tx) = @_;

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
  $cgi->run;

=head1 DESCRIPTION

L<Mojo::Server::CGI> is a simple and portable implementation of RFC 3875.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 EVENTS

L<Mojo::Server::CGI> inherits all events from L<Mojo::Server>.

=head1 ATTRIBUTES

L<Mojo::Server::CGI> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 C<nph>

  my $nph = $cgi->nph;
  $cgi    = $cgi->nph(1);

Activate non parsed header mode.

=head1 METHODS

L<Mojo::Server::CGI> inherits all methods from L<Mojo::Server> and implements
the following new ones.

=head2 C<run>

  $cgi->run;

Run CGI.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
