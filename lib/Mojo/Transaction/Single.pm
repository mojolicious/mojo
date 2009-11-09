# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Transaction::Single;

use strict;
use warnings;

use base 'Mojo::Transaction';

use Mojo::Message::Request;
use Mojo::Message::Response;

__PACKAGE__->attr([qw/continued handler_cb continue_handler_cb/]);
__PACKAGE__->attr(req => sub { Mojo::Message::Request->new });
__PACKAGE__->attr(res => sub { Mojo::Message::Response->new });

__PACKAGE__->attr('_continue');
__PACKAGE__->attr([qw/_offset _to_write/] => 0);
__PACKAGE__->attr(_started => sub {time});

# What's a wedding?  Webster's dictionary describes it as the act of removing
# weeds from one's garden.
sub client_connected {
    my $self = shift;

    # Connection header
    unless ($self->req->headers->connection) {
        if ($self->keep_alive || $self->kept_alive) {
            $self->req->headers->connection('Keep-Alive');
        }
        else {
            $self->req->headers->connection('Close');
        }
    }

    # We identify ourself
    $self->req->headers->user_agent('Mozilla/5.0 (compatible; Mojo; Perl)')
      unless $self->req->headers->user_agent;

    # We might have to handle 100 Continue
    $self->_continue($self->continue_timeout)
      if ($self->req->headers->expect || '') =~ /100-continue/;

    # Ready for next state
    $self->state('write_start_line');
    $self->_to_write($self->req->start_line_size);

    return $self;
}

sub client_get_chunk {
    my $self = shift;

    my $chunk;

    # Body
    if ($self->is_state('write_body')) {
        $chunk = $self->req->get_body_chunk($self->_offset);

        # End
        if (defined $chunk && !length $chunk) {
            $self->state('read_response');
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

    return $chunk;
}

sub client_info {
    my $self = shift;

    my $scheme = $self->req->url->scheme;
    my $host   = $self->req->url->host;
    my $port   = $self->req->url->port || 80;

    # Proxy
    if (my $proxy = $self->req->proxy) {
        $scheme = $proxy->scheme;
        $host   = $proxy->host;
        $port   = $proxy->port || 80;
    }

    return {host => $host, port => $port, scheme => $scheme};
}

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

    # Buffer early response, most likely an error
    $self->res->buffer->add_chunk($chunk) if $self->client_is_writing;

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
    elsif ($self->is_state('read_response')) {
        $self->done if $read == 0;

        # HEAD request is special case
        if ($self->req->method eq 'HEAD') {
            $self->res->parse_until_body($chunk);
            while ($self->res->content->is_state('body')) {

                # Check for unexpected 1XX
                if ($self->res->is_status_class(100)) {
                    $self->_new_response(1);
                }

                # Leftovers?
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
            return $self;
        }

        # Parse
        $self->res->parse($chunk);

        while ($self->res->is_finished) {

            # Check for unexpected 100
            if (   $self->res->is_state(qw/done done_with_leftovers/)
                && $self->res->is_status_class(100))
            {
                $self->_new_response;
            }

            else {

                # Inherit state
                $self->state($self->res->state);
                $self->error($self->res->error) if $self->res->has_error;
                last;
            }
        }
    }

    return $self;
}

sub client_spin {
    my $self = shift;

    # Check for request/response errors
    $self->error('Request error.')  if $self->req->has_error;
    $self->error('Response error.') if $self->res->has_error;

    # Make sure we don't wait longer than 5 seconds for a 100 Continue
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

    # Keep alive?
    $self->{keep_alive} = 1
      if ($req->headers->connection || '') =~ /keep-alive/i
      or ($res->headers->connection || '') =~ /keep-alive/i;

    # Close?
    $self->{keep_alive} = 0
      if ($req->headers->connection || '') =~ /close/i
      or ($res->headers->connection || '') =~ /close/i;

    # Default
    $self->{keep_alive} = 1 unless defined $self->{keep_alive};
    return $self->{keep_alive};
}

sub server_get_chunk {
    my $self = shift;

    my $chunk;

    # Body
    if ($self->is_state('write_body')) {
        $chunk = $self->res->get_body_chunk($self->_offset);

        # End
        if (defined $chunk && !length $chunk) {
            $self->req->is_state('done_with_leftovers')
              ? $self->state('done_with_leftovers')
              : $self->state('done');
            return;
        }
    }

    # Headers
    $chunk = $self->res->get_header_chunk($self->_offset)
      if $self->is_state('write_headers');

    # Start line
    $chunk = $self->res->get_start_line_chunk($self->_offset)
      if $self->is_state('write_start_line');

    # Written
    my $written = defined $chunk ? length $chunk : 0;
    $self->_to_write($self->_to_write - $written);
    $self->_offset($self->_offset + $written);

    # Chunked
    $self->_to_write(1)
      if $self->res->is_chunked && $self->is_state('write_body');

    # Done early
    if ($self->is_state('write_body') && $self->_to_write <= 0) {
        $self->req->is_state('done_with_leftovers')
          ? $self->state('done_with_leftovers')
          : $self->state('done');
    }

    return $chunk;
}

sub server_read {
    my ($self, $chunk) = @_;

    # Parse
    $self->req->parse($chunk);

    # Expect 100 Continue?
    if ($self->req->content->is_state('body') && !defined $self->continued) {
        if (($self->req->headers->expect || '') =~ /100-continue/i) {

            # Writing
            $self->state('write');

            # Continue handler callback
            $self->continue_handler_cb->($self);
            $self->continued(0);
        }
    }

    # EOF
    if ((length $chunk == 0) || $self->req->is_finished) {

        # Writing
        $self->state('write');

        # Handler callback
        $self->handler_cb->($self);
    }

    return $self;
}

sub server_spin {
    my $self = shift;

    # We identify ourself
    $self->res->headers->server('Mojo (Perl)')
      unless $self->res->headers->server;

    # Reading
    $self->state('read') if $self->is_state('start');

    # Writing
    if ($self->is_state('write')) {

        # Connection header
        unless ($self->res->headers->connection) {
            if ($self->keep_alive) {
                $self->res->headers->connection('Keep-Alive');
            }
            else {
                $self->res->headers->connection('Close');
            }
        }

        # Ready for next state
        $self->state('write_start_line');
        $self->_to_write($self->res->start_line_size);
    }

    # Response start line
    if ($self->is_state('write_start_line') && $self->_to_write <= 0) {
        $self->state('write_headers');
        $self->_offset(0);
        $self->_to_write($self->res->header_size);
    }

    # Response headers
    if ($self->is_state('write_headers') && $self->_to_write <= 0) {

        if ($self->req->method eq 'HEAD') {

            # Don't send body if request method is HEAD
            $self->req->is_state('done_with_leftovers')
              ? $self->state('done_with_leftovers')
              : $self->state('done');
        }
        else {

            $self->state('write_body');
            $self->_offset(0);
            $self->_to_write($self->res->body_size);

            # Chunked
            $self->_to_write(1) if $self->res->is_chunked;
        }
    }

    # Response body
    if ($self->is_state('write_body') && $self->_to_write <= 0) {

        # Continue done
        if (defined $self->continued && $self->continued == 0) {
            $self->continued(1);
            $self->state('read');

            # Continue
            if ($self->res->code == 100) {
                $self->res($self->res->new);
            }

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

Mojo::Transaction::Single - HTTP Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction::Single;

    my $tx = Mojo::Transaction::Single->new;

    my $req = $tx->req;
    my $res = $tx->res;

    my $keep_alive = $tx->keep_alive;

=head1 DESCRIPTION

L<Mojo::Transaction::Single> is a container for HTTP transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction::Single> inherits all attributes from
L<Mojo::Transaction> and implements the following new ones.

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

=head1 METHODS

L<Mojo::Transaction::Single> inherits all methods from L<Mojo::Transaction>
and implements the following new ones.

=head2 C<client_connected>

    $tx = $tx->client_connected;

=head2 C<client_get_chunk>

    my $chunk = $tx->client_get_chunk;

=head2 C<client_info>

    my $info = $tx->client_info;

=head2 C<client_leftovers>

    my $leftovers = $tx->client_leftovers;

=head2 C<client_read>

    $tx = $tx->client_read($chunk);

=head2 C<client_spin>

    $tx = $tx->client_spin;

=head2 C<server_get_chunk>

    my $chunk = $tx->server_get_chunk;

=head2 C<server_read>

    $tx = $tx->server_read($chunk);

=head2 C<server_spin>

    $tx = $tx->server_spin;

=cut
