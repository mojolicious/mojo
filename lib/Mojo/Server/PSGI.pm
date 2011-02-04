package Mojo::Server::PSGI;
use Mojo::Base 'Mojo::Server';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 256000;

# "Things aren't as happy as they used to be down here at the unemployment
#  office.
#  Joblessness is no longer just for philosophy majors.
#  Useful people are starting to feel the pinch."
sub run {
  my ($self, $env) = @_;

  my $tx  = $self->on_build_tx->($self);
  my $req = $tx->req;

  # Environment
  $req->parse($env);

  # Store connection information
  $tx->remote_address($env->{REMOTE_ADDR});
  $tx->local_port($env->{SERVER_PORT});

  # Request body
  while (!$req->is_done) {
    my $read = $env->{'psgi.input'}->read(my $buffer, CHUNK_SIZE, 0);
    last if $read == 0;
    $req->parse($buffer);
  }

  # Handle
  $self->on_handler->($self, $tx);

  my $res = $tx->res;

  # Status
  my $status = $res->code;

  # Response headers
  $res->fix_headers;
  my $headers = $res->content->headers;
  my @headers;
  for my $name (@{$headers->names}) {
    for my $values ($headers->header($name)) {
      push @headers, $name => $_ for @$values;
    }
  }

  # Response body
  my $body = Mojo::Server::PSGI::_Handle->new(_res => $res);

  # Finish transaction
  $tx->on_finish->($tx);

  return [$status, \@headers, $body];
}

package Mojo::Server::PSGI::_Handle;
use Mojo::Base -base;

sub close { }

sub getline {
  my $self = shift;

  # Blocking read
  $self->{_offset} = 0 unless defined $self->{_offset};
  my $offset = $self->{_offset};
  while (1) {
    my $chunk = $self->{_res}->get_body_chunk($offset);

    # No content yet, try again
    unless (defined $chunk) {
      sleep 1;
      next;
    }

    # End of content
    last unless length $chunk;

    # Content
    $offset += length $chunk;
    $self->{_offset} = $offset;
    return $chunk;
  }

  return;
}

1;
__END__

=head1 NAME

Mojo::Server::PSGI - PSGI Server

=head1 SYNOPSIS

  use Mojo::Server::PSGI;

  my $psgi = Mojo::Server::PSGI->new;
  $psgi->on_handler(sub {
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
  my $app  = sub { $psgi->run(@_) };

=head1 DESCRIPTION

L<Mojo::Server::PSGI> allows L<Mojo> applications to run on all PSGI
compatible servers.

See L<Mojolicious::Guides::Cookbook> for deployment recipes.

=head1 METHODS

L<Mojo::Server::PSGI> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<run>

  my $res = $psgi->run($env);

Start PSGI.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
