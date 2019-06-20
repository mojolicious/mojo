package Mojo::IOLoop::UDP;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use IO::Socket::IP;

has reactor => sub { Mojo::IOLoop->singleton->reactor }, weak => 1;

sub bind {
  my ($self, $args) = (shift, ref $_[0] ? $_[0] : {@_});

  my %options = (Type => SOCK_DGRAM, LocalPort => 8080);
  my $handle = $self->{handle} = IO::Socket::IP->new(%options)
    or croak "Can't create socket: $@";

  $self->reactor->io(
    $handle => sub {
      my $reactor = shift;
      my $addr    = $handle->recv(my $buffer, 65536);
      $self->emit('recv', $addr, $buffer);
    }
  )->watch($handle, 1, 0);
}

1;
