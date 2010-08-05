# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Transaction::HTTP;

use strict;
use warnings;

use base 'Mojo::Transaction';

use Mojo::Message::Request;
use Mojo::Message::Response;

__PACKAGE__->attr([qw/handler_cb upgrade_cb/]);
__PACKAGE__->attr(req => sub { Mojo::Message::Request->new });
__PACKAGE__->attr(res => sub { Mojo::Message::Response->new });

# What's a wedding?  Webster's dictionary describes it as the act of removing
# weeds from one's garden.
sub client_read {
    my ($self, $chunk) = @_;

    # Request and response
    my $req = $self->req;
    my $res = $self->res;

    # Length
    my $read = length $chunk;

    $self->done if $read == 0;

    # HEAD response
    if ($req->method eq 'HEAD') {
        $res->parse_until_body($chunk);
        while ($res->content->is_state('body')) {

            # Leftovers
            if ($res->has_leftovers) {
                $res->state('done_with_leftovers');
                $self->state('done_with_leftovers');
                last;
            }

            # Done
            else { $self->done and last }
        }
    }

    # Normal response
    else {

        # Parse
        $res->parse($chunk);

        # Finished
        if ($res->is_finished) {

            # Inherit state
            $self->state($res->state);
            $self->error($res->error) if $res->has_error;
        }
    }

    # Check for request/response errors
    $self->error($req->error) if $req->has_error;
    $self->error($res->error) if $res->has_error;

    return $self;
}

sub client_write {
    my $self = shift;

    # Chunk
    my $chunk = '';

    # Offsets
    my $offset = $self->{_offset} ||= 0;
    my $write  = $self->{_write}  ||= 0;

    # Request
    my $req = $self->req;

    # Writing
    my $state = $self->state;
    if ($state eq 'start') {

        # Connection header
        my $headers = $req->headers;
        unless ($headers->connection) {
            if ($self->keep_alive || $self->kept_alive) {
                $headers->connection('Keep-Alive');
            }
            else { $headers->connection('Close') }
        }

        # Ready for next state
        $state = 'write_start_line';
        $write = $req->start_line_size;
    }

    # Start line
    if ($state eq 'write_start_line') {
        my $buffer = $req->get_start_line_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $write  = $write - $written;
        $offset = $offset + $written;

        $chunk .= $buffer;

        # Done
        if ($write <= 0) {
            $state  = 'write_headers';
            $offset = 0;
            $write  = $req->header_size;
        }
    }

    # Headers
    if ($state eq 'write_headers') {
        my $buffer = $req->get_header_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $write  = $write - $written;
        $offset = $offset + $written;

        $chunk .= $buffer;

        # Done
        if ($write <= 0) {

            $state  = 'write_body';
            $offset = 0;
            $write  = $req->body_size;

            # Chunked
            $write = 1 if $req->is_chunked;
        }
    }

    # Body
    if ($state eq 'write_body') {
        my $buffer = $req->get_body_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $write  = $write - $written;
        $offset = $offset + $written;

        $chunk .= $buffer;

        # End
        $state = 'read_response' if defined $buffer && !length $buffer;

        # Chunked
        $write = 1 if $req->is_chunked;

        # Done
        $state = 'read_response' if $write <= 0;
    }
    $self->state($state);

    # Offsets
    $self->{_offset} = $offset;
    $self->{_write}  = $write;

    return $chunk;
}

sub keep_alive {
    my ($self, $keep_alive) = @_;

    # Custom
    if ($keep_alive) {
        $self->{keep_alive} = $keep_alive;
        return $self;
    }

    # Request and response
    my $req = $self->req;
    my $res = $self->res;

    # No keep alive for 0.9 and 1.0
    my $version = $req->version;
    $self->{keep_alive} ||= 0 if $req->version eq '0.9' || $version eq '1.0';
    $version = $res->version;
    $self->{keep_alive} ||= 0 if $version eq '0.9' || $version eq '1.0';

    # Connection headers
    my $reqc = $req->headers->connection || '';
    my $resc = $res->headers->connection || '';

    # Keep alive
    $self->{keep_alive} = 1
      if $reqc =~ /^keep-alive$/i || $resc =~ /^keep-alive$/i;

    # Close
    $self->{keep_alive} = 0 if $reqc =~ /^close$/i || $resc =~ /^close$/i;

    # Default
    $self->{keep_alive} = 1 unless defined $self->{keep_alive};

    return $self->{keep_alive};
}

sub server_leftovers {
    my $self = shift;

    # Request
    my $req = $self->req;

    # No leftovers
    return unless $req->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $req->leftovers;

    # Done
    $req->done;

    return $leftovers;
}

sub server_read {
    my ($self, $chunk) = @_;

    # Request and response
    my $req = $self->req;
    my $res = $self->res;

    # Parse
    $req->parse($chunk) unless $req->has_error;

    # Parser error
    my $handled = $self->{_handled};
    if ($req->has_error && !$handled) {

        # Write
        $self->state('write');

        # Handler callback
        $self->handler_cb->($self);

        # Close connection
        $res->headers->connection('Close');

        # Protect handler from incoming pipelined requests
        $self->{_handled} = 1;
    }

    # EOF
    elsif ((length $chunk == 0) || ($req->is_finished && !$handled)) {

        # Writing
        $self->state('write');

        # Upgrade callback
        my $ws;
        $ws = $self->upgrade_cb->($self) if $req->headers->upgrade;

        # Handler callback
        $self->handler_cb->($ws ? ($ws, $self) : $self);

        # Protect handler from incoming pipelined requests
        $self->{_handled} = 1;
    }

    # Expect 100 Continue
    elsif ($req->content->is_state('body') && !defined $self->{_continued}) {
        if (($req->headers->expect || '') =~ /100-continue/i) {

            # Writing
            $self->state('write');

            # Continue
            $res->code(100);
            $self->{_continued} = 0;
        }
    }

    return $self;
}

sub server_write {
    my $self = shift;

    # Chunk
    my $chunk = '';

    # Offsets
    my $offset = $self->{_offset} ||= 0;
    my $write  = $self->{_write}  ||= 0;

    # Request and response
    my $req = $self->req;
    my $res = $self->res;

    # Writing
    my $state = $self->state;
    if ($state eq 'write') {

        # Connection header
        my $headers = $res->headers;
        unless ($headers->connection) {
            if   ($self->keep_alive) { $headers->connection('Keep-Alive') }
            else                     { $headers->connection('Close') }
        }

        # Ready for next state
        $state = 'write_start_line';
        $write = $res->start_line_size;
    }

    # Start line
    if ($state eq 'write_start_line') {
        my $buffer = $res->get_start_line_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $write  = $write - $written;
        $offset = $offset + $written;

        # Append
        $chunk .= $buffer;

        # Done
        if ($write <= 0) {
            $state  = 'write_headers';
            $offset = 0;
            $write  = $res->header_size;
        }
    }

    # Headers
    if ($state eq 'write_headers') {
        my $buffer = $res->get_header_chunk($offset);

        # Written
        my $written = defined $buffer ? length $buffer : 0;
        $write  = $write - $written;
        $offset = $offset + $written;

        # Append
        $chunk .= $buffer;

        # Done
        if ($write <= 0) {

            # HEAD request
            if ($req->method eq 'HEAD') {

                # Don't send body if request method is HEAD
                $state =
                  $req->is_state('done_with_leftovers')
                  ? 'done_with_leftovers'
                  : 'done';
            }

            # Body
            else {
                $state  = 'write_body';
                $offset = 0;
                $write  = $res->body_size;

                # Chunked
                $write = 1 if $res->is_chunked;
            }
        }
    }

    # Body
    if ($state eq 'write_body') {

        # 100 Continue
        if ($write <= 0) {

            # Continue done
            if (defined $self->{_continued} && $self->{_continued} == 0) {
                $self->{_continued} = 1;
                $state = 'read';

                # New response after continue
                if ($res->code == 100) { $self->res($res->new) }

                # Don't continue
                else { $state = 'done' }
            }

            # Everything done
            elsif (!defined $self->{_continued}) {
                $state =
                  $req->is_state('done_with_leftovers')
                  ? 'done_with_leftovers'
                  : 'done';
            }

        }

        # Normal body
        else {
            my $buffer = $res->get_body_chunk($offset);

            # Written
            my $written = defined $buffer ? length $buffer : 0;
            $write  = $write - $written;
            $offset = $offset + $written;

            # Append
            $chunk .= $buffer;

            # Chunked
            $write = 1 if $res->is_chunked;

            # Done
            $state =
              $req->is_state('done_with_leftovers')
              ? 'done_with_leftovers'
              : 'done'
              if $write <= 0 || (defined $buffer && !length $buffer);
        }
    }
    $self->state($state);

    # Offsets
    $self->{_offset} = $offset;
    $self->{_write}  = $write;

    return $chunk;
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
transactions as described in RFC 2616.

=head1 ATTRIBUTES

L<Mojo::Transaction::HTTP> inherits all attributes from L<Mojo::Transaction>
and implements the following new ones.

=head2 C<handler_cb>

    my $cb = $tx->handler_cb;
    $tx    = $tx->handler_cb(sub {...});

Handler callback.

=head2 C<keep_alive>

    my $keep_alive = $tx->keep_alive;
    $tx            = $tx->keep_alive(1);

Connection can be kept alive.

=head2 C<req>

    my $req = $tx->req;
    $tx     = $tx->req(Mojo::Message::Request->new);

HTTP 1.1 request.

=head2 C<res>

    my $res = $tx->res;
    $tx     = $tx->res(Mojo::Message::Response->new);

HTTP 1.1 response.

=head2 C<upgrade_cb>

    my $cb = $tx->upgrade_cb;
    $tx    = $tx->upgrade_cb(sub {...});

WebSocket upgrade callback.

=head1 METHODS

L<Mojo::Transaction::HTTP> inherits all methods from L<Mojo::Transaction> and
implements the following new ones.

=head2 C<client_read>

    $tx = $tx->client_read($chunk);

Read and process client data.

=head2 C<client_write>

    my $chunk = $tx->client_write;

Write client data.

=head2 C<server_leftovers>

    my $leftovers = $tx->server_leftovers;

Leftovers from the server request, used for pipelining.

=head2 C<server_read>

    $tx = $tx->server_read($chunk);

Read and process server data.

=head2 C<server_write>

    my $chunk = $tx->server_write;

Write server data.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
