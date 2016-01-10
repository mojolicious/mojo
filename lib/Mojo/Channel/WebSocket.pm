package Mojo::Channel::WebSocket;
use Mojo::Base 'Mojo::Channel';

use Mojo::WebSocket 'parse_frame';

sub close { shift->{tx}->closed }

sub read {
  my ($self, $chunk) = @_;

  my $tx = $self->{tx};
  $self->{read} .= $chunk // '';
  while (my $frame = parse_frame \$self->{read}, $tx->max_websocket_size) {
    $tx->finish(1009) and last unless ref $frame;
    $tx->frame($frame);
  }

  $tx->resume;
}


sub write {
  my $self = shift;

  my $tx = $self->{tx};
  unless (length($tx->{write} // '')) {
    $tx->{state} = $tx->is_closing ? 'finished' : 'read';
    $tx->emit('drain');
  }

  return delete $tx->{write} // '';
}


1;
