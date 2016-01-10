package Mojo::Channel::HTTP;
use Mojo::Base 'Mojo::Channel';

sub close { shift->{tx}->delivered }

sub is_server {undef}

sub start {
  my $self = shift;
  @$self{qw(tx cb)} = @_;
  delete @$self{qw(delay http_state offset write)};
  return $self;
}

sub write {
  my $self = shift;

  # Client starts writing right away
  my $tx = $self->{tx};
  $tx->{state} ||= 'write' unless my $server = $self->is_server;

  # Nothing written yet
  $self->{$_} ||= 0 for qw(offset write);
  my $msg = $server ? $tx->res : $tx->req;
  @$self{qw(http_state write)} = ('start_line', $msg->start_line_size)
    unless $self->{http_state};

  # Start-line
  my $chunk = '';
  $chunk .= $self->_start_line($msg) if $self->{http_state} eq 'start_line';

  # Headers
  $chunk .= $self->_headers($msg, $server) if $self->{http_state} eq 'headers';

  # Body
  $chunk .= $self->_body($msg, $server) if $self->{http_state} eq 'body';

  return $chunk;
}

sub _body {
  my ($self, $msg, $finish) = @_;

  # Prepare body chunk
  my $tx      = $self->{tx};
  my $buffer  = $msg->get_body_chunk($self->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $self->{write} = $msg->content->is_dynamic ? 1 : ($self->{write} - $written);
  $self->{offset} += $written;
  if (defined $buffer) { delete $self->{delay} }

  # Delayed
  elsif (delete $self->{delay}) { $tx->{state} = 'read' }
  else                          { $self->{delay} = 1 }

  # Finished
  $tx->{state} = $finish ? 'finished' : 'read'
    if $self->{write} <= 0 || defined $buffer && $buffer eq '';

  return defined $buffer ? $buffer : '';
}

sub _headers {
  my ($self, $msg, $head) = @_;

  # Prepare header chunk
  my $tx      = $self->{tx};
  my $buffer  = $msg->get_header_chunk($self->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $self->{write} -= $written;
  $self->{offset} += $written;

  # Switch to body
  if ($self->{write} <= 0) {
    $self->{offset} = 0;

    # Response without body
    if ($head && $tx->is_empty) { $tx->{state} = 'finished' }

    # Body
    else {
      $self->{http_state} = 'body';
      $self->{write} = $msg->content->is_dynamic ? 1 : $msg->body_size;
    }
  }

  return $buffer;
}

sub _start_line {
  my ($self, $msg) = @_;

  # Prepare start-line chunk
  my $buffer  = $msg->get_start_line_chunk($self->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $self->{write} -= $written;
  $self->{offset} += $written;

  # Switch to headers
  @$self{qw(http_state write offset)} = ('headers', $msg->header_size, 0)
    if $self->{write} <= 0;

  return $buffer;
}

1;
