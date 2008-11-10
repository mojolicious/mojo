# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Server::CGI;

use strict;
use warnings;

use base 'Mojo::Server';

use IO::Select;

__PACKAGE__->attr('nph', chained => 1, default => 0);

# Lisa, you're a Buddhist, so you believe in reincarnation.
# Eventually, Snowball will be reborn as a higher lifeform... like a snowman.
sub run {
    my $self = shift;

    my $tx  = $self->build_tx_cb->($self);
    my $req = $tx->req;

    # Environment
    $req->parse(\%ENV);

    # Request body
    $req->state('body');
    my $select = IO::Select->new(\*STDIN);
    while (!$req->is_state(qw/done error/)) {
        last unless $select->can_read(0);
        my $read = STDIN->sysread(my $buffer, 4096, 0);
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
            my $written = STDOUT->syswrite($chunk);
            $offset += $written;
        }
    }

    # Response headers
    my $code = $res->code;
    my $message = $res->message || $res->default_message;
    $res->headers->header('Status', "$code $message") unless $self->nph;
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
        my $written = STDOUT->syswrite($chunk);
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
        my $written = STDOUT->syswrite($chunk);
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