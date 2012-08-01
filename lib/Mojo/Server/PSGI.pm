package Mojo::Server::PSGI;
use Mojo::Base 'Mojo::Server';

# "Things aren't as happy as they used to be down here at the unemployment
#  office.
#  Joblessness is no longer just for philosophy majors.
#  Useful people are starting to feel the pinch."
sub run {
  my ($self, $env) = @_;

  # Environment
  my $tx  = $self->build_tx;
  my $req = $tx->req->parse($env);

  # Store connection information
  $tx->local_port($env->{SERVER_PORT})->remote_address($env->{REMOTE_ADDR});

  # Request body
  my $len = $env->{CONTENT_LENGTH};
  until ($req->is_finished) {
    my $chunk = ($len && $len < 131072) ? $len : 131072;
    last unless my $read = $env->{'psgi.input'}->read(my $buffer, $chunk, 0);
    $req->parse($buffer);
    last if ($len -= $read) <= 0;
  }

  # Handle
  $self->emit(request => $tx);

  # Response headers
  my $res     = $tx->res->fix_headers;
  my $headers = $res->content->headers;
  my @headers;
  for my $name (@{$headers->names}) {
    push @headers, $name => $_ for map {@$_} $headers->header($name);
  }

  # PSGI response
  return [$res->code || 404,
    \@headers, Mojo::Server::PSGI::_IO->new(tx => $tx)];
}

sub to_psgi_app {
  my $self = shift;

  # Preload application and wrap it
  $self->app;
  return sub { $self->run(@_) }
}

# "Wow! Homer must have got one of those robot cars!
#  *Car crashes in background*
#  Yeah, one of those AMERICAN robot cars."
package Mojo::Server::PSGI::_IO;
use Mojo::Base -base;

sub close { shift->{tx}->server_close }

sub getline {
  my $self = shift;

  # No content yet, try again later
  my $chunk = $self->{tx}->res->get_body_chunk($self->{offset} //= 0);
  return '' unless defined $chunk;

  # End of content
  return unless length $chunk;

  # Content
  $self->{offset} += length $chunk;
  return $chunk;
}

1;

=head1 NAME

Mojo::Server::PSGI - PSGI server

=head1 SYNOPSIS

  use Mojo::Server::PSGI;

  my $psgi = Mojo::Server::PSGI->new;
  $psgi->unsubscribe('request');
  $psgi->on(request => sub {
    my ($psgi, $tx) = @_;

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
  my $app = $psgi->to_psgi_app;

=head1 DESCRIPTION

L<Mojo::Server::PSGI> allows L<Mojo> applications to run on all PSGI
compatible servers.

See L<Mojolicious::Guides::Cookbook> for more.

=head1 EVENTS

L<Mojo::Server::PSGI> inherits all events from L<Mojo::Server>.

=head1 METHODS

L<Mojo::Server::PSGI> inherits all methods from L<Mojo::Server> and implements
the following new ones.

=head2 C<run>

  my $res = $psgi->run($env);

Run L<PSGI>.

=head2 C<to_psgi_app>

  my $app = $psgi->to_psgi_app;

Turn L<Mojo> application into L<PSGI> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
