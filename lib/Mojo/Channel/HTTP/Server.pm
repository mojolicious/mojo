package Mojo::Channel::HTTP::Server;
use Mojo::Base 'Mojo::Channel::HTTP';

sub is_server {1}

sub read {
  my ($self, $chunk) = @_;

  # Parse request
  my $tx  = $self->{tx};
  my $req = $tx->req;
  $req->parse($chunk) unless $req->error;
  $tx->{state} ||= 'read';

  # Generate response
  $tx->handle if $req->is_finished && !$self->{handled}++;
}

sub start {
  my $self = shift;
  delete $self->{handled};
  return $self->SUPER::start(@_);
}

1;
