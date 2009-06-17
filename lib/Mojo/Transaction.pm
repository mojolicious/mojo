# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Transaction;

use strict;
use warnings;

use base 'Mojo::Pipeline';

use Mojo;
use Mojo::Message::Request;
use Mojo::Message::Response;

__PACKAGE__->attr('continued' => (chained => 1));
__PACKAGE__->attr(
    req => (
        chained => 1,
        default => sub { Mojo::Message::Request->new }
    )
);
__PACKAGE__->attr(
    res => (
        chained => 1,
        default => sub { Mojo::Message::Response->new }
    )
);

# What's a wedding?  Webster's dictionary describes it as the act of removing
# weeds from one's garden.
sub client_connect {
    my $self = shift;

    # Connect
    $self->state('connect');

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
    my $version = $Mojo::VERSION;
    $self->req->headers->user_agent(
        "Mozilla/5.0 (compatible; Mojo/$version; Perl)")
      unless $self->req->headers->user_agent;

    return $self;
}

sub client_connected {
    my $self = shift;

    # We might have to handle 100 Continue
    $self->{_continue} = $self->continue_timeout
      if ($self->req->headers->expect || '') =~ /100-continue/;

    # Ready for next state
    $self->state('write_start_line');
    $self->{_to_write} = $self->req->start_line_length;

    return $self;
}

sub client_get_chunk {
    my $self = shift;

    my $chunk;

    # Body
    if ($self->is_state('write_body')) {
        $chunk = $self->req->get_body_chunk($self->{_offset} || 0);

        # End
        if (defined $chunk && !length $chunk) {
            $self->state('read_response');
            return undef;
        }
    }

    # Headers
    $chunk = $self->req->get_header_chunk($self->{_offset} || 0)
      if $self->is_state('write_headers');

    # Start line
    $chunk = $self->req->get_start_line_chunk($self->{_offset} || 0)
      if $self->is_state('write_start_line');

    return $chunk;
}

sub client_info {
    my $self = shift;

    my $address = $self->req->url->address;
    my $port = $self->req->url->port || 80;

    # Proxy
    if (my $proxy = $self->req->proxy) {
        $address = $proxy->address;
        $port = $proxy->port || 80;
    }

    return ($address, $port);
}

sub client_leftovers {
    my $self = shift;

    # No leftovers
    return undef unless $self->is_state('done_with_leftovers');

    # Leftovers
    my $leftovers = $self->res->leftovers;
    $self->done;

    return $leftovers;
}

sub client_read {
    my ($self, $chunk) = @_;

    # Length
    my $read = length $chunk;

    # Early response, most likely an error
    $self->state('read_response')
      if $self->is_state(qw/write_start_line write_headers write_body/);

    # Read 100 Continue
    if ($self->is_state('read_continue')) {
        $self->res->done if $read == 0;
        $self->res->parse($chunk);

        # We got a 100 Continue response
        if ($self->res->is_done && $self->res->code == 100) {
            $self->res($self->res->new);
            $self->continued(1);
            $self->{_continue} = 0;
        }

        # We got something else
        elsif ($self->res->is_done) {
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
            if ($self->res->content->is_state('body')) {

                # Leftovers?
                if ($self->res->has_leftovers) {
                    $self->res->state('done_with_leftovers');
                    $self->state('done_with_leftovers');
                }

                # Done
                else { $self->done }
            }
            return $self;
        }

        # Parse
        $self->res->parse($chunk);
        $self->done if $self->res->is_done;
        $self->state('done_with_leftovers')
          if $self->res->is_state('done_with_leftovers');
    }

    return $self;
}

sub client_spin {
    my $self = shift;

    # Check for request/response errors
    $self->error('Request error.')  if $self->req->has_error;
    $self->error('Response error.') if $self->res->has_error;

    # Make sure we don't wait longer than 5 seconds for a 100 Continue
    if ($self->{_continue}) {
        my $continue = $self->{_continue};
        $self->{_started} ||= time;
        $continue -= time - $self->{_started};
        $continue = 0 if $continue < 0;
        $self->{_continue} = $continue;
    }

    # Request start line written
    if ($self->is_state('write_start_line')) {
        if ($self->{_to_write} <= 0) {
            $self->state('write_headers');
            $self->{_offset}   = 0;
            $self->{_to_write} = $self->req->header_length;
        }
    }

    # Request headers written
    if ($self->is_state('write_headers')) {
        if ($self->{_to_write} <= 0) {

            $self->{_continue}
              ? $self->state('read_continue')
              : $self->state('write_body');
            $self->{_offset}   = 0;
            $self->{_to_write} = $self->req->body_length;

            # Chunked
            $self->{_to_write} = 1 if $self->req->is_chunked;
        }
    }

    # 100 Continue timeout
    if ($self->is_state('read_continue')) {
        $self->state('write_body') unless $self->{_continue};
    }

    # Request body written
    if ($self->is_state('write_body')) {
        $self->state('read_response') if $self->{_to_write} <= 0;
    }

    return $self;
}

sub client_written {
    my ($self, $written) = @_;

    # Written
    $self->{_to_write} -= $written;
    $self->{_offset} += $written;

    # Chunked
    $self->{_to_write} = 1
      if $self->req->is_chunked && $self->is_state('write_body');

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

sub new_delete { shift->_builder('DELETE', @_) }
sub new_get    { shift->_builder('GET',    @_) }
sub new_head   { shift->_builder('HEAD',   @_) }
sub new_post   { shift->_builder('POST',   @_) }
sub new_put    { shift->_builder('PUT',    @_) }

sub server_accept {
    my $self = shift;

    # Reading
    $self->state('read');

    return $self;
}

sub server_get_chunk {
    my $self = shift;

    my $chunk;

    # Body
    if ($self->is_state('write_body')) {
        $chunk = $self->res->get_body_chunk($self->{_offset} || 0);

        # End
        if (defined $chunk && !length $chunk) {
            $self->req->is_state('done_with_leftovers')
              ? $self->state('done_with_leftovers')
              : $self->state('done');
            return undef;
        }
    }

    # Headers
    $chunk = $self->res->get_header_chunk($self->{_offset} || 0)
      if $self->is_state('write_headers');

    # Start line
    $chunk = $self->res->get_start_line_chunk($self->{_offset} || 0)
      if $self->is_state('write_start_line');

    return $chunk;
}

sub server_handled {
    my $self = shift;

    # Handled and writing now
    $self->state('write');

    return $self;
}

sub server_read {
    my ($self, $chunk) = @_;

    # Parse
    $self->req->parse($chunk);

    # Expect 100 Continue?
    if ($self->req->content->is_state('body') && !defined $self->continued) {
        if (($self->req->headers->expect || '') =~ /100-continue/i) {
            $self->state('handle_continue');
            $self->continued(0);
        }
    }

    # EOF
    if ((length $chunk == 0) || $self->req->is_finished) {
        $self->state('handle_request');
    }

    return $self;
}

sub server_spin {

    my $self = shift;

    # Initialize
    $self->{_to_write} ||= 0;

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
        $self->{_to_write} = $self->res->start_line_length;
    }

    # Response start line
    if ($self->is_state('write_start_line') && $self->{_to_write} <= 0) {
        $self->state('write_headers');
        $self->{_offset}   = 0;
        $self->{_to_write} = $self->res->header_length;
    }

    # Response headers
    if ($self->is_state('write_headers') && $self->{_to_write} <= 0) {

        if ($self->req->method eq 'HEAD') {

            # Don't send body if request method is HEAD
            $self->req->is_state('done_with_leftovers')
              ? $self->state('done_with_leftovers')
              : $self->state('done');
        }
        else {

            $self->state('write_body');
            $self->{_offset}   = 0;
            $self->{_to_write} = $self->res->body_length;

            # Chunked
            $self->{_to_write} = 1 if $self->res->is_chunked;
        }
    }

    # Response body
    if ($self->is_state('write_body') && $self->{_to_write} <= 0) {

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

sub server_written {
    my ($self, $written) = @_;

    # Written
    $self->{_to_write} -= $written;
    $self->{_offset} += $written;

    # Chunked
    $self->{_to_write} = 1
      if $self->res->is_chunked && $self->is_state('write_body');

    # Done early
    if ($self->is_state('write_body') && $self->{_to_write} <= 0) {
        $self->req->is_state('done_with_leftovers')
          ? $self->state('done_with_leftovers')
          : $self->state('done');
    }

    return $self;
}

sub _builder {
    my $class = shift;
    my $self  = $class->new;
    my $req   = $self->req;

    # Method
    $req->method(shift);

    # URL
    $req->url->parse(shift);

    # Headers
    my $headers = ref $_[0] eq 'HASH' ? $_[0] : {@_};
    for my $name (keys %$headers) {
        $req->headers->header($name, $headers->{$name});
    }

    return $self;
}

1;
__END__

=head1 NAME

Mojo::Transaction - HTTP Transaction Container

=head1 SYNOPSIS

    use Mojo::Transaction;

    my $tx = Mojo::Transaction->new;

    my $req = $tx->req;
    my $res = $tx->res;

    my $keep_alive = $tx->keep_alive;

=head1 DESCRIPTION

L<Mojo::Transaction> is a container for HTTP transactions.

=head1 ATTRIBUTES

L<Mojo::Transaction> inherits all attributes from L<Mojo::Pipeline> and
implements the following new ones.

=head2 C<continued>

    my $continued = $tx->continued;
    $tx           = $tx->continued(1);

=head2 C<keep_alive>

    my $keep_alive = $tx->keep_alive;
    $tx            = $tx->keep_alive(1);

=head2 C<req>

    my $req = $tx->req;
    $tx     = $tx->req(Mojo::Message::Request->new);

Returns a L<Mojo::Message::Request> object if called without arguments.
Returns the invocant if called with arguments.

=head2 C<res>

    my $res = $tx->res;
    $tx     = $tx->res(Mojo::Message::Response->new);

Returns a L<Mojo::Message::Response> object if called without arguments.
Returns the invocant if called with arguments.

=head1 METHODS

L<Mojo::Transaction> inherits all methods from L<Mojo::Pipeline> and
implements the following new ones.

=head2 C<client_connect>

    $tx = $tx->client_connect;

=head2 C<client_connected>

    $tx = $tx->client_connected;

=head2 C<client_get_chunk>

    my $chunk = $tx->client_get_chunk;

=head2 C<client_info>

    my ($address, $port) = $tx->client_info;

=head2 C<client_leftovers>

    my $leftovers = $tx->client_leftovers;

=head2 C<client_read>

    $tx = $tx->client_read($chunk);

=head2 C<client_spin>

    $tx = $tx->client_spin;

=head2 C<client_written>

    $tx = $tx->client_written($length);

=head2 C<new_delete>

    my $tx = Mojo::Transaction->new_delete('http://127.0.0.1',
        User-Agent => 'Mojo'
    );
    my $tx = Mojo::Transaction->new_delete('http://127.0.0.1', {
        User-Agent => 'Mojo'
    });

=head2 C<new_get>

    my $tx = Mojo::Transaction->new_get('http://127.0.0.1',
        User-Agent => 'Mojo'
    );
    my $tx = Mojo::Transaction->new_get('http://127.0.0.1', {
        User-Agent => 'Mojo'
    });

=head2 C<new_head>

    my $tx = Mojo::Transaction->new_head('http://127.0.0.1',
        User-Agent => 'Mojo'
    );
    my $tx = Mojo::Transaction->new_head('http://127.0.0.1', {
        User-Agent => 'Mojo'
    });

=head2 C<new_post>

    my $tx = Mojo::Transaction->new_post('http://127.0.0.1',
        User-Agent => 'Mojo'
    );
    my $tx = Mojo::Transaction->new_post('http://127.0.0.1', {
        User-Agent => 'Mojo'
    });

=head2 C<new_put>

    my $tx = Mojo::Transaction->new_put('http://127.0.0.1',
        User-Agent => 'Mojo'
    );
    my $tx = Mojo::Transaction->new_put('http://127.0.0.1', {
        User-Agent => 'Mojo'
    });

=head2 C<server_accept>

    $tx = $tx->server_accept;

=head2 C<server_get_chunk>

    my $chunk = $tx->server_get_chunk;

=head2 C<server_handled>

    $tx = $tx->server_handled;

=head2 C<server_read>

    $tx = $tx->server_read($chunk);

=head2 C<server_spin>

    $tx = $tx->server_spin;

=head2 C<server_written>

    $tx = $tx->server_written($bytes);

=cut
