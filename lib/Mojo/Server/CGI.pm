# Copyright (C) 2008-2009, Sebastian Riedel.

package Mojo::Server::CGI;

use strict;
use warnings;

use base 'Mojo::Server';
use bytes;

use IO::Poll 'POLLIN';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 4096;

__PACKAGE__->attr(nph => 0);

# Lisa, you're a Buddhist, so you believe in reincarnation.
# Eventually, Snowball will be reborn as a higher lifeform... like a snowman.
sub run {
    my $self = shift;

    my $tx  = $self->build_tx_cb->($self);
    my $req = $tx->req;

    # Environment
    $req->parse(\%ENV);

    # Store connection information
    $tx->remote_address($ENV{REMOTE_ADDR});
    $tx->local_port($ENV{SERVER_PORT});

    # Request body
    my $poll = IO::Poll->new;
    $poll->mask(\*STDIN, POLLIN);
    while (!$req->is_finished) {
        $poll->poll(0);
        my @readers = $poll->handles(POLLIN);
        last unless @readers;
        my $read = STDIN->sysread(my $buffer, CHUNK_SIZE, 0);
        $req->parse($buffer);
    }

    # Handle
    $self->handler_cb->($self, $tx);

    my $res = $tx->res;

    # Response start line
    my $offset = 0;
    if ($self->nph) {
        while (1) {
            my $chunk = $res->get_start_line_chunk($offset);

            # No start line yet, try again
            unless (defined $chunk) {
                sleep 1;
                next;
            }

            # End of start line
            last unless length $chunk;

            # Start line
            return unless STDOUT->opened;
            my $written = STDOUT->syswrite($chunk);
            return unless defined $written;
            $offset += $written;
        }
    }

    # Status
    if (my $code = $res->code) {
        my $message = $res->message || $res->default_message;
        $res->headers->header('Status', "$code $message") unless $self->nph;
    }

    # Response headers
    $offset = 0;
    while (1) {
        my $chunk = $res->get_header_chunk($offset);

        # No headers yet, try again
        unless (defined $chunk) {
            sleep 1;
            next;
        }

        # End of headers
        last unless length $chunk;

        # Headers
        return unless STDOUT->opened;
        my $written = STDOUT->syswrite($chunk);
        return unless defined $written;
        $offset += $written;
    }

    # Response body
    $offset = 0;
    while (1) {
        my $chunk = $res->get_body_chunk($offset);

        # No content yet, try again
        unless (defined $chunk) {
            sleep 1;
            next;
        }

        # End of content
        last unless length $chunk;

        # Content
        return unless STDOUT->opened;
        my $written = STDOUT->syswrite($chunk);
        return unless defined $written;
        $offset += $written;
    }

    return $res->code;
}

1;
__END__

=head1 NAME

Mojo::Server::CGI - CGI Server

=head1 SYNOPSIS

    use Mojo::Server::CGI;
    my $cgi = Mojo::Server::CGI->new;
    $cgi->run;

=head1 DESCRIPTION

L<Mojo::Server::CGI> is a simple and portable CGI implementation.

=head1 ATTRIBUTES

L<Mojo::Server::CGI> inherits all attributes from L<Mojo::Server> and
implements the following new ones.

=head2 C<nph>

    my $nph = $cgi->nph;
    $cgi    = $cgi->nph(1);

=head1 METHODS

L<Mojo::Server::CGI> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<run>

    $cgi->run;

=cut
