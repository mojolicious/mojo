package Mojo::Server::CGI;
use Mojo::Base 'Mojo::Server';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 256000;

has nph => 0;

# "Lisa, you're a Buddhist, so you believe in reincarnation.
#  Eventually, Snowball will be reborn as a higher lifeform...
#  like a snowman."
sub run {
  my $self = shift;

  my $tx  = $self->on_build_tx->($self);
  my $req = $tx->req;

  # Environment
  $req->parse(\%ENV);

  # Store connection information
  $tx->remote_address($ENV{REMOTE_ADDR});
  $tx->local_port($ENV{SERVER_PORT});

  # Request body
  while (!$req->is_done) {
    my $read = STDIN->sysread(my $buffer, CHUNK_SIZE, 0);
    last unless $read;
    $req->parse($buffer);
  }

  # Handle
  $self->on_handler->($self, $tx);

  my $res = $tx->res;

  # Response start line
  my $offset = 0;
  if ($self->nph) {
    while (1) {
      my $chunk = $res->get_start_line_chunk($offset);

      # No start line yet, try again
      unless (defined $chunk) {
        sleep 1;
        next;
      }

      # End of start line
      last unless length $chunk;

      # Start line
      return unless STDOUT->opened;
      my $written = STDOUT->syswrite($chunk);
      return unless defined $written;
      $offset += $written;
    }
  }

  # Fix headers
  $res->fix_headers;

  # Status
  if (my $code = $res->code) {
    my $message = $res->message || $res->default_message;
    $res->headers->header(Status => "$code $message") unless $self->nph;
  }

  # Response headers
  $offset = 0;
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
    return unless STDOUT->opened;
    my $written = STDOUT->syswrite($chunk);
    return unless defined $written;
    $offset += $written;
  }

  # Response body
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
    return unless STDOUT->opened;
    my $written = STDOUT->syswrite($chunk);
    return unless defined $written;
    $offset += $written;
  }

  # Finish transaction
  $tx->on_finish->($tx);

  return $res->code;
}

1;
__END__

=head1 NAME

Mojo::Server::CGI - CGI Server

=head1 SYNOPSIS

  use Mojo::Server::CGI;

  my $cgi = Mojo::Server::CGI->new;
  $cgi->on_handler(sub {
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
  $cgi->run;

=head1 DESCRIPTION

L<Mojo::Server::CGI> is a simple and portable implementation of RFC 3875.

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

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

Process CGI.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
