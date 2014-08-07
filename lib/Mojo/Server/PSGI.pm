package Mojo::Server::PSGI;
use Mojo::Base 'Mojo::Server';

sub run {
  my ($self, $env) = @_;

  my $tx  = $self->build_tx;
  my $req = $tx->req->parse($env);
  $tx->local_port($env->{SERVER_PORT})->remote_address($env->{REMOTE_ADDR});

  # Request body (may block if we try to read too much)
  my $len = $env->{CONTENT_LENGTH};
  until ($req->is_finished) {
    my $chunk = ($len && $len < 131072) ? $len : 131072;
    last unless my $read = $env->{'psgi.input'}->read(my $buffer, $chunk, 0);
    $req->parse($buffer);
    last if ($len -= $read) <= 0;
  }

  # Handle request
  $self->emit(request => $tx);

  # Response headers
  my $res  = $tx->res->fix_headers;
  my $hash = $res->headers->to_hash(1);
  my @headers;
  for my $name (keys %$hash) {
    push @headers, map { $name => $_ } @{$hash->{$name}};
  }

  # PSGI response
  my $io = Mojo::Server::PSGI::_IO->new(tx => $tx, empty => $tx->is_empty);
  return [$res->code // 404, \@headers, $io];
}

sub to_psgi_app {
  my $self = shift;

  # Preload application and wrap it
  $self->app;
  return sub { $self->run(@_) }
}

package Mojo::Server::PSGI::_IO;
use Mojo::Base -base;

# Finish transaction
sub close { shift->{tx}->server_close }

sub getline {
  my $self = shift;

  # Empty
  return undef if $self->{empty};

  # No content yet, try again later
  my $chunk = $self->{tx}->res->get_body_chunk($self->{offset} //= 0);
  return '' unless defined $chunk;

  # End of content
  return undef unless length $chunk;

  $self->{offset} += length $chunk;
  return $chunk;
}

1;

=encoding utf8

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

L<Mojo::Server::PSGI> allows L<Mojolicious> applications to run on all L<PSGI>
compatible servers.

See L<Mojolicious::Guides::Cookbook/"DEPLOYMENT"> for more.

=head1 EVENTS

L<Mojo::Server::PSGI> inherits all events from L<Mojo::Server>.

=head1 ATTRIBUTES

L<Mojo::Server::PSGI> inherits all attributes from L<Mojo::Server>.

=head1 METHODS

L<Mojo::Server::PSGI> inherits all methods from L<Mojo::Server> and implements
the following new ones.

=head2 run

  my $res = $psgi->run($env);

Run L<PSGI>.

=head2 to_psgi_app

  my $app = $psgi->to_psgi_app;

Turn L<Mojo> application into L<PSGI> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
