package Mojo::Channel::HTTP::Server;
use Mojo::Base 'Mojo::Channel::HTTP';

sub read {
  my ($self, $chunk) = @_;

  # Parse request
  my $tx  = $self->{tx};
  my $req = $tx->req;
  $req->parse($chunk) unless $req->error;
  $tx->{state} ||= 'read';

  # Generate response
  $tx->emit('request') if $req->is_finished && !$tx->{handled}++;
}

1;
