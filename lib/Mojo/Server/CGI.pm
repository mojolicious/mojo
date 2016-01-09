package Mojo::Server::CGI;
use Mojo::Base 'Mojo::Server';

has 'nph';

sub run {
  my $self = shift;

  my $tx  = $self->build_tx;
  my $req = $tx->req->parse(\%ENV);
  $tx->local_port($ENV{SERVER_PORT})->remote_address($ENV{REMOTE_ADDR});

  # Request body (may block if we try to read too much)
  binmode STDIN;
  my $len = $req->headers->content_length;
  until ($req->is_finished) {
    my $chunk = ($len && $len < 131072) ? $len : 131072;
    last unless my $read = STDIN->read(my $buffer, $chunk, 0);
    $req->parse($buffer);
    last if ($len -= $read) <= 0;
  }

  $self->emit(request => $tx);

  # Response start-line
  STDOUT->autoflush(1);
  binmode STDOUT;
  my $res = $tx->res->fix_headers;
  return undef if $self->nph && !_write($res, 'get_start_line_chunk');

  # Response headers
  my $code = $res->code    || 404;
  my $msg  = $res->message || $res->default_message;
  $res->headers->status("$code $msg") unless $self->nph;
  return undef unless _write($res, 'get_header_chunk');

  # Response body
  return undef unless $tx->is_empty || _write($res, 'get_body_chunk');

  # Finish transaction
  $tx->closed;

  return $res->code;
}

sub _write {
  my ($res, $method) = @_;

  my $offset = 0;
  while (1) {

    # No chunk yet, try again
    sleep 1 and next unless defined(my $chunk = $res->$method($offset));

    # End of part
    last unless my $len = length $chunk;

    # Make sure we can still write
    $offset += $len;
    return undef unless STDOUT->opened;
    print STDOUT $chunk;
  }

  return 1;
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::CGI - CGI server

=head1 SYNOPSIS

  use Mojo::Server::CGI;

  my $cgi = Mojo::Server::CGI->new;
  $cgi->unsubscribe('request')->on(request => sub {
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

L<Mojo::Server::CGI> is a simple and portable implementation of
L<RFC 3875|http://tools.ietf.org/html/rfc3875>.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 EVENTS

L<Mojo::Server::CGI> inherits all events from L<Mojo::Server>.

=head1 ATTRIBUTES

L<Mojo::Server::CGI> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 nph

  my $bool = $cgi->nph;
  $cgi     = $cgi->nph($bool);

Activate non-parsed header mode.

=head1 METHODS

L<Mojo::Server::CGI> inherits all methods from L<Mojo::Server> and implements
the following new ones.

=head2 run

  my $status = $cgi->run;

Run CGI.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
