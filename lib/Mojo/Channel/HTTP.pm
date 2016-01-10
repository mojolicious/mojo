package Mojo::Channel::HTTP;
use Mojo::Base 'Mojo::Channel';

sub close { shift->{tx}->closed }

sub is_server {undef}

sub write {
  my $self = shift;

  # Client starts writing right away
  my $server = $self->is_server;
  my $tx     = $self->{tx};
  $tx->{state} ||= 'write' unless $server;
  return '' unless $tx->{state} eq 'write';

  # Nothing written yet
  $tx->{$_} ||= 0 for qw(offset write);
  my $msg = $server ? $tx->res : $tx->req;
  @$tx{qw(http_state write)} = ('start_line', $msg->start_line_size)
    unless $tx->{http_state};

  # Start-line
  my $chunk = '';
  $chunk .= $self->_start_line($msg) if $tx->{http_state} eq 'start_line';

  # Headers
  $chunk .= $self->_headers($msg, $server) if $tx->{http_state} eq 'headers';

  # Body
  $chunk .= $self->_body($msg, $server) if $tx->{http_state} eq 'body';

  return $chunk;
}

sub _body {
  my ($self, $msg, $finish) = @_;

  # Prepare body chunk
  my $tx      = $self->{tx};
  my $buffer  = $msg->get_body_chunk($tx->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $tx->{write} = $msg->content->is_dynamic ? 1 : ($tx->{write} - $written);
  $tx->{offset} += $written;
  if (defined $buffer) { delete $self->{delay} }

  # Delayed
  elsif (delete $tx->{delay}) { $tx->{state} = 'paused' }
  else                        { $tx->{delay} = 1 }

  # Finished
  $tx->{state} = $finish ? 'finished' : 'read'
    if $tx->{write} <= 0 || defined $buffer && $buffer eq '';

  return defined $buffer ? $buffer : '';
}

sub _headers {
  my ($self, $msg, $head) = @_;

  # Prepare header chunk
  my $tx      = $self->{tx};
  my $buffer  = $msg->get_header_chunk($tx->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $tx->{write} -= $written;
  $tx->{offset} += $written;

  # Switch to body
  if ($tx->{write} <= 0) {
    $tx->{offset} = 0;

    # Response without body
    if ($head && $tx->is_empty) { $tx->{state} = 'finished' }

    # Body
    else {
      $tx->{http_state} = 'body';
      $tx->{write} = $msg->content->is_dynamic ? 1 : $msg->body_size;
    }
  }

  return $buffer;
}

sub _start_line {
  my ($self, $msg) = @_;

  # Prepare start-line chunk
  my $tx      = $self->{tx};
  my $buffer  = $msg->get_start_line_chunk($tx->{offset});
  my $written = defined $buffer ? length $buffer : 0;
  $tx->{write} -= $written;
  $tx->{offset} += $written;

  # Switch to headers
  @$tx{qw(http_state write offset)} = ('headers', $msg->header_size, 0)
    if $tx->{write} <= 0;

  return $buffer;
}

1;
