package Mojo::Channel::HTTP::Client;
use Mojo::Base 'Mojo::Channel::HTTP';

sub read {
  my ($self, $chunk) = @_;

  # Skip body for HEAD request
  my $tx  = $self->{tx};
  my $res = $tx->res;
  $res->content->skip_body(1) if uc $tx->req->method eq 'HEAD';
  return unless $res->parse($chunk)->is_finished;

  # Unexpected 1xx response
  return $tx->{state} = 'finished'
    if !$res->is_status_class(100) || $res->headers->upgrade;
  $tx->res($res->new)->emit(unexpected => $res);
  return if (my $leftovers = $res->content->leftovers) eq '';
  $self->read($leftovers);
}

1;
