package Mojo::Transaction::HTTP;
use Mojo::Base 'Mojo::Transaction';

has [qw(next previous)];

sub is_empty { !!(uc $_[0]->req->method eq 'HEAD' || $_[0]->res->is_empty) }

sub keep_alive {
  my $self = shift;

  # Close
  my $req      = $self->req;
  my $res      = $self->res;
  my $req_conn = lc($req->headers->connection // '');
  my $res_conn = lc($res->headers->connection // '');
  return undef if $req_conn eq 'close' || $res_conn eq 'close';

  # Keep-alive is optional for 1.0
  return $res_conn eq 'keep-alive' if $res->version eq '1.0';
  return $req_conn eq 'keep-alive' if $req->version eq '1.0';

  # Keep-alive is the default for 1.1
  return 1;
}

sub redirects {
  my $previous = shift;
  my @redirects;
  unshift @redirects, $previous while $previous = $previous->previous;
  return \@redirects;
}

1;

=encoding utf8

=head1 NAME

Mojo::Transaction::HTTP - HTTP transaction

=head1 SYNOPSIS

  use Mojo::Transaction::HTTP;

  # Client
  my $tx = Mojo::Transaction::HTTP->new;
  $tx->req->method('GET');
  $tx->req->url->parse('http://example.com');
  $tx->req->headers->accept('application/json');
  say $tx->res->code;
  say $tx->res->headers->content_type;
  say $tx->res->body;
  say $tx->remote_address;

  # Server
  my $tx = Mojo::Transaction::HTTP->new;
  say $tx->req->method;
  say $tx->req->url->to_abs;
  say $tx->req->headers->accept;
  say $tx->remote_address;
  $tx->res->code(200);
  $tx->res->headers->content_type('text/plain');
  $tx->res->body('Hello World!');

=head1 DESCRIPTION

L<Mojo::Transaction::HTTP> is a container for HTTP transactions based on
L<RFC 7230|http://tools.ietf.org/html/rfc7230> and
L<RFC 7231|http://tools.ietf.org/html/rfc7231>.

=head1 EVENTS

L<Mojo::Transaction::HTTP> inherits all events from L<Mojo::Transaction> and
can emit the following new ones.

=head2 request

  $tx->on(request => sub {
    my $tx = shift;
    ...
  });

Emitted when a request is ready and needs to be handled.

  $tx->on(request => sub {
    my $tx = shift;
    $tx->res->headers->header('X-Bender' => 'Bite my shiny metal ass!');
  });

=head2 unexpected

  $tx->on(unexpected => sub {
    my ($tx, $res) = @_;
    ...
  });

Emitted for unexpected C<1xx> responses that will be ignored.

  $tx->on(unexpected => sub {
    my $tx = shift;
    $tx->res->on(finish => sub { say 'Follow-up response is finished.' });
  });

=head1 ATTRIBUTES

L<Mojo::Transaction::HTTP> inherits all attributes from L<Mojo::Transaction>
and implements the following new ones.

=head2 next

  my $next = $tx->next;
  $tx      = $tx->next(Mojo::Transaction::WebSocket->new);

Follow-up transaction for connections that get upgraded to a different protocol,
usually a L<Mojo::Transaction::WebSocket> object.

=head2 previous

  my $previous = $tx->previous;
  $tx          = $tx->previous(Mojo::Transaction::HTTP->new);

Previous transaction that triggered this follow-up transaction, usually a
L<Mojo::Transaction::HTTP> object.

  # Paths of previous requests
  say $tx->previous->previous->req->url->path;
  say $tx->previous->req->url->path;

=head1 METHODS

L<Mojo::Transaction::HTTP> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 client_write

  my $bytes = $tx->client_write;

Write data client-side, used to implement user agents such as
L<Mojo::UserAgent>.

=head2 is_empty

  my $bool = $tx->is_empty;

Check transaction for C<HEAD> request and C<1xx>, C<204> or C<304> response.

=head2 keep_alive

  my $bool = $tx->keep_alive;

Check if connection can be kept alive.

=head2 redirects

  my $redirects = $tx->redirects;

Return a list of all previous transactions that preceded this follow-up
transaction.

  # Paths of all previous requests
  say $_->req->url->path for @{$tx->redirects};

=head2 server_write

  my $bytes = $tx->server_write;

Write data server-side, used to implement web servers such as
L<Mojo::Server::Daemon>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
