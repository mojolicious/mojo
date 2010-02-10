# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Transaction::HTTP;

use strict;
use warnings;

use base 'Mojo::Transaction';

use Mojo::Message::Request;
use Mojo::Message::Response;

__PACKAGE__->attr([qw/continue_handler_cb continued handler_cb upgrade_cb/]);
__PACKAGE__->attr(req => sub { Mojo::Message::Request->new });
__PACKAGE__->attr(res => sub { Mojo::Message::Response->new });

__PACKAGE__->attr('_continue');
__PACKAGE__->attr([qw/_offset _to_write/] => 0);
__PACKAGE__->attr(_started => sub {time});

# What's a wedding?  Webster's dictionary describes it as the act of removing
# weeds from one's garden.
sub client_leftovers {
    my $self = shift;

    # No leftovers
    return unless $self->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $self->res->leftovers;
    $self->done;

    return $leftovers;
}

sub client_read {
    my ($self, $chunk) = @_;

    # Length
    my $read = length $chunk;

    # Read 100 Continue
    if ($self->is_state('read_continue')) {
        $self->res->done if $read == 0;
        $self->res->parse($chunk);

        # We got a 100 Continue response
        if (   $self->res->is_state(qw/done done_with_leftovers/)
            && $self->res->code == 100)
        {
            $self->_new_response;
            $self->continued(1);
            $self->_continue(0);
        }

        # We got something else
        elsif ($self->res->is_finished) {
            $self->continued(0);
            $self->done;
        }
    }

    # Read response
    else {
        $self->done if $read == 0;

        # HEAD request is special case
        if ($self->req->method eq 'HEAD') {
            $self->res->parse_until_body($chunk);
            while ($self->res->content->is_state('body')) {

                # Check for unexpected 1XX
                if ($self->res->is_status_class(100)) {
                    $self->_new_response(1);
                }

                # Leftovers
                elsif ($self->res->has_leftovers) {
                    $self->res->state('done_with_leftovers');
                    $self->state('done_with_leftovers');
                    last;
                }

                # Done
                else {
                    $self->done;
                    last;
                }
            }

            # Spin
            $self->_client_spin;

            return $self;
        }

        # Parse
        $self->res->parse($chunk);

        # Finished
        while ($self->res->is_finished) {

            # Check for unexpected 100
            if (($self->res->code || '') eq '100') { $self->_new_response }

            else {

                # Inherit state
                $self->state($self->res->state);
                $self->error($self->res->error) if $self->res->has_error;
                last;
            }
        }
    }

    # Spin
    $self->_client_spin;

    return $self;
}

sub client_write {
    my $self = shift;

    my $chunk;

    # Body
    if ($self->is_state('write_body')) {
        $chunk = $self->req->get_body_chunk($self->_offset);

        # End
        if (defined $chunk && !length $chunk) {
            $self->state('read_response');
            $self->_client_spin;
            return;
        }
    }

    # Headers
    $chunk = $self->req->get_header_chunk($self->_offset)
      if $self->is_state('write_headers');

    # Start line
    $chunk = $self->req->get_start_line_chunk($self->_offset)
      if $self->is_state('write_start_line');

    # Written
    my $written = defined $chunk ? length $chunk : 0;
    $self->_to_write($self->_to_write - $written);
    $self->_offset($self->_offset + $written);

    # Chunked
    $self->_to_write(1)
      if $self->req->is_chunked && $self->is_state('write_body');

    # Spin
    $self->_client_spin;

    return $chunk;
}

sub keep_alive {
    my ($self, $keep_alive) = @_;

    if ($keep_alive) {
        $self->{keep_alive} = $keep_alive;
        return $self;
    }

    my $req = $self->req;
    my $res = $self->res;

    # No keep alive for 0.9
    $self->{keep_alive} ||= 0
      if ($req->version eq '0.9') || ($res->version eq '0.9');

    # No keep alive for 1.0
    $self->{keep_alive} ||= 0
      if ($req->version eq '1.0') || ($res->version eq '1.0');

    # Keep alive
    $self->{keep_alive} = 1
      if ($req->headers->connection || '') =~ /keep-alive/i
      or ($res->headers->connection || '') =~ /keep-alive/i;

    # Close
    $self->{keep_alive} = 0
      if ($req->headers->connection || '') =~ /close/i
      or ($res->headers->connection || '') =~ /close/i;

    # Default
    $self->{keep_alive} = 1 unless defined $self->{keep_alive};
    return $self->{keep_alive};
}

sub server_leftovers {
    my $self = shift;

    # No leftovers
    return unless $self->req->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $self->req->leftovers;

    # Done
    $self->req->done;

    return $leftovers;
}

sub server_read {
    my ($self, $chunk) = @_;

    # Request
    my $req = $self->req;

    # Parse
    $req->parse($chunk) unless $req->has_error;

    # Parser error
    if ($req->has_error) {

        # Request entity too large
        if ($req->error =~ /^Maximum (?:message|line) size exceeded.$/) {
            $self->res->code(413);
        }

        # Bad request
        else { $self->res->code(400) }

        # Close connection
        $self->res->headers->connection('Close');

        # Write
        $self->state('write');
    }

    # EOF
    elsif ((length $chunk == 0) || $req->is_finished) {

        # Writing
        $self->state('write');

        # Upgrade callback
        my $ws;
        $ws = $self->upgrade_cb->($self) if $req->headers->upgrade;

        # Handler callback
        $self->handler_cb->($ws ? ($ws, $self) : $self);
    }

    # Expect 100 Continue
    elsif ($req->content->is_state('body') && !defined $self->continued) {
        if (($req->headers->expect || '') =~ /100-continue/i) {

            # Writing
            $self->state('write');

            # Continue handler callback
            $self->continue_handler_cb->($self);
            $self->continued(0);
        }
    }

    return $self;
}

sub server_write {
    my $self = shift;

    # Chunk
    my $chunk = '';

    # Offsets
    my $offset   = $self->_offset;
    my $to_write = $self->_to_write;

    # Writing
    if ($self->is_state('write')) {

        # Connection header
        unless ($self->res->headers->connection) {
            if ($self->keep_alive) {
                $self->res->headers->connection('Keep-Alive');
            }
            else { $self->res->headers->connection('Close') }
        }

        # Ready for next state
        $self->state('write_start_line');
        $to_write = $self->res->start_line_size;
    }

    # Start line
    if ($self->is_state('write_start_line')) {
        my $buffer = $self->res->get_start_line_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $to_write = $to_write - $written;
        $offset   = $offset + $written;

        # Append
        $chunk .= $buffer;

        # Done
        if ($to_write <= 0) {
            $self->state('write_headers');
            $offset   = 0;
            $to_write = $self->res->header_size;
        }
    }

    # Headers
    if ($self->is_state('write_headers')) {
        my $buffer = $self->res->get_header_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $to_write = $to_write - $written;
        $offset   = $offset + $written;

        # Append
        $chunk .= $buffer;

        # Done
        if ($to_write <= 0) {

            # HEAD request
            if ($self->req->method eq 'HEAD') {

                # Don't send body if request method is HEAD
                $self->req->is_state('done_with_leftovers')
                  ? $self->state('done_with_leftovers')
                  : $self->state('done');
            }

            # Body
            else {
                $self->state('write_body');
                $offset   = 0;
                $to_write = $self->res->body_size;

                # Chunked
                $to_write = 1 if $self->res->is_chunked;
            }
        }
    }

    # Body
    if ($self->is_state('write_body')) {

        # 100 Continue
        if ($to_write <= 0) {

            # Continue done
            if (defined $self->continued && $self->continued == 0) {
                $self->continued(1);
                $self->state('read');

                # Continue
                if ($self->res->code == 100) { $self->res($self->res->new) }

                # Don't continue
                else { $self->done }
            }

            # Everything done
            elsif (!defined $self->continued) {
                $self->req->is_state('done_with_leftovers')
                  ? $self->state('done_with_leftovers')
                  : $self->state('done');
            }

        }

        # Normal body
        else {
            my $buffer = $self->res->get_body_chunk($offset);

            # Written
            my $written = defined $buffer ? length $buffer : 0;
            $to_write = $to_write - $written;
            $offset   = $offset + $written;

            # Append
            $chunk .= $buffer;

            # Chunked
            $to_write = 1 if $self->res->is_chunked;

            # Done
            $self->req->is_state('done_with_leftovers')
              ? $self->state('done_with_leftovers')
              : $self->state('done')
              if $to_write <= 0 || (defined $buffer && !length $buffer);
        }
    }

    # Offsets
    $self->_offset($offset);
    $self->_to_write($to_write);

    return $chunk;
}

sub _client_spin {
    my $self = shift;

    # Check for request/response errors
    $self->error('Request error.')  if $self->req->has_error;
    $self->error('Response error.') if $self->res->has_error;

    if ($self->is_state('start')) {

        # Connection header
        unless ($self->req->headers->connection) {
            if ($self->keep_alive || $self->kept_alive) {
                $self->req->headers->connection('Keep-Alive');
            }
            else { $self->req->headers->connection('Close') }
        }

        # We might have to handle 100 Continue
        $self->_continue($self->continue_timeout)
          if ($self->req->headers->expect || '') =~ /100-continue/;

        # Ready for next state
        $self->state('write_start_line');
        $self->_to_write($self->req->start_line_size);
    }

    # Make sure we don't wait longer than the set time for a 100 Continue
    # (defaults to 5 seconds)
    if ($self->_continue) {
        my $continue = $self->_continue;
        $continue = $self->continue_timeout - (time - $self->_started);
        $continue = 0 if $continue < 0;
        $self->_continue($continue);
    }

    # Request start line written
    if ($self->is_state('write_start_line')) {
        if ($self->_to_write <= 0) {
            $self->state('write_headers');
            $self->_offset(0);
            $self->_to_write($self->req->header_size);
        }
    }

    # Request headers written
    if ($self->is_state('write_headers')) {
        if ($self->_to_write <= 0) {

            $self->_continue
              ? $self->state('read_continue')
              : $self->state('write_body');
            $self->_offset(0);
            $self->_to_write($self->req->body_size);

            # Chunked
            $self->_to_write(1) if $self->req->is_chunked;
        }
    }

    # 100 Continue timeout
    if ($self->is_state('read_continue')) {
        $self->state('write_body') unless $self->_continue;
    }

    # Request body written
    if ($self->is_state('write_body')) {
        $self->state('read_response') if $self->_to_write <= 0;
    }

    return $self;
}

# Replace client response after receiving 100 Continue
sub _new_response {
    my $self = shift;

    # 1 is special case for HEAD
    my $until_body = @_ ? shift : 0;

    my $new = $self->res->new;

    # Check for leftovers in old response
    if ($self->res->has_leftovers) {

        $until_body
          ? $new->parse_until_body($self->res->leftovers)
          : $new->parse($self->res->leftovers);

        $new->is_finished
          ? $self->state($new->state)
          : $self->state('read_response');
    }

    $self->res($new);
}

1;
__END__

=head1 NAME

Mojo::Transaction::HTTP - HTTP 1.1 Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction::HTTP;

    my $tx = Mojo::Transaction::HTTP->new;

    my $req = $tx->req;
    my $res = $tx->res;

    my $keep_alive = $tx->keep_alive;

=head1 DESCRIPTION

L<Mojo::Transaction::HTTP> is a container and state machine for HTTP 1.1
transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction::HTTP> inherits all attributes from L<Mojo::Transaction>
and implements the following new ones.

=head2 C<continue_handler_cb>

    my $cb = $tx->continue_handler_cb;
    $tx    = $tx->continue_handler_cb(sub {...});

=head2 C<continued>

    my $continued = $tx->continued;
    $tx           = $tx->continued(1);

=head2 C<handler_cb>

    my $cb = $tx->handler_cb;
    $tx    = $tx->handler_cb(sub {...});

=head2 C<keep_alive>

    my $keep_alive = $tx->keep_alive;
    $tx            = $tx->keep_alive(1);

=head2 C<req>

    my $req = $tx->req;
    $tx     = $tx->req(Mojo::Message::Request->new);

=head2 C<res>

    my $res = $tx->res;
    $tx     = $tx->res(Mojo::Message::Response->new);

=head2 C<upgrade_cb>

    my $cb = $tx->upgrade_cb;
    $tx    = $tx->upgrade_cb(sub {...});

=head1 METHODS

L<Mojo::Transaction::HTTP> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<client_leftovers>

    my $leftovers = $tx->client_leftovers;

=head2 C<client_read>

    $tx = $tx->client_read($chunk);

=head2 C<client_write>

    my $chunk = $tx->client_write;

=head2 C<server_leftovers>

    my $leftovers = $tx->server_leftovers;

=head2 C<server_read>

    $tx = $tx->server_read($chunk);

=head2 C<server_write>

    my $chunk = $tx->server_write;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
