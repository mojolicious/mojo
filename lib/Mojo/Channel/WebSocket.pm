package Mojo::Channel::WebSocket;
use Mojo::Base 'Mojo::Channel';

sub read {
  my ($self, $chunk) = @_;

  my $tx = $self->{tx};
  $self->{read} .= $chunk // '';
  while (my $frame = $tx->parse_frame(\$self->{read})) {
    $tx->finish(1009) and last unless ref $frame;
    $tx->emit(frame => $frame);
  }

  $tx->emit('resume');
}


sub write {
  my $self = shift;
  my $tx = $self->{tx};

  unless (length($tx->{write} // '')) {
    $tx->{state} = $tx->{finished} ? 'finished' : 'read';
    $tx->emit('drain');
  }

  return delete $tx->{write} // '';
}


1;
