package Mojo::Server::CGI;
use Mojo::Base 'Mojo::Server';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 131072;

has nph => 0;

# "Lisa, you're a Buddhist, so you believe in reincarnation.
#  Eventually, Snowball will be reborn as a higher lifeform...
#  like a snowman."
sub run {
  my $self = shift;

  # Environment
  my $tx  = $self->build_tx;
  my $req = $tx->req;
  $req->parse(\%ENV);

  # Store connection information
  $tx->remote_address($ENV{REMOTE_ADDR});
  $tx->local_port($ENV{SERVER_PORT});

  # Request body
  binmode STDIN;
  while (!$req->is_finished) {
    my $read = STDIN->read(my $buffer, CHUNK_SIZE, 0);
    last unless $read;
    $req->parse($buffer);
  }

  # Handle
  $self->emit(request => $tx);

  # Response start line
  STDOUT->autoflush(1);
  binmode STDOUT;
  my $res    = $tx->res;
  my $offset = 0;
  if ($self->nph) {
    while (1) {
      my $chunk = $res->get_start_line_chunk($offset);

      # No start line yet, try again
      sleep 1 and next unless defined $chunk;

      # End of start line
      last unless length $chunk;

      # Start line
      return unless STDOUT->opened;
      print STDOUT $chunk;
      $offset += length $chunk;
    }
  }

  # Response headers
  $res->fix_headers;
  my $code    = $res->code    || 404;
  my $message = $res->message || $res->default_message;
  $res->headers->status("$code $message") unless $self->nph;
  $offset = 0;
  while (1) {
    my $chunk = $res->get_header_chunk($offset);

    # No headers yet, try again
    sleep 1 and next unless defined $chunk;

    # End of headers
    last unless length $chunk;

    # Headers
    return unless STDOUT->opened;
    print STDOUT $chunk;
    $offset += length $chunk;
  }

  # Response body
  $offset = 0;
  while (1) {
    my $chunk = $res->get_body_chunk($offset);

    # No content yet, try again
    sleep 1 and next unless defined $chunk;

    # End of content
    last unless length $chunk;

    # Content
    return unless STDOUT->opened;
    print STDOUT $chunk;
    $offset += length $chunk;
  }

  # Finish transaction
  $tx->server_close;

  return $res->code;
}

1;
__END__

=head1 NAME

Mojo::Server::CGI - CGI server

=head1 SYNOPSIS

  use Mojo::Server::CGI;

  my $cgi = Mojo::Server::CGI->new;
  $cgi->off('request')
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

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

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

L<Mojo::Server::CGI> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<run>

  $cgi->run;

Run CGI.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
