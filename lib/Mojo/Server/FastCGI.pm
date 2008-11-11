# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Server::FastCGI;

use strict;
use warnings;

use base 'Mojo::Server';
use bytes;

use IO::Select;

# Roles
my @ROLES = qw/RESPONDER  AUTHORIZER FILTER/;
my %ROLE_NUMBERS;
{
    my $i = 1;
    for my $role (@ROLES) {
        $ROLE_NUMBERS{$role} = $i;
        $i++;
    }
}

#Types
my @TYPES = qw/
    BEGIN_REQUEST
    ABORT_REQUEST
    END_REQUEST
    PARAMS
    STDIN
    STDOUT
    STDERR
    DATA
    GET_VALUES
    GET_VALUES_RESULT
    UNKNOWN_TYPE
/;
my %TYPE_NUMBERS;
{
    my $i = 1;
    for my $type (@TYPES) {
        $TYPE_NUMBERS{$type} = $i;
        $i++;
    }
}

# Wow! Homer must have got one of those robot cars!
# *Car crashes in background*
# Yeah, one of those AMERICAN robot cars.
sub accept_connection {
    my $self = shift;

    # Listen socket?
    open $self->{_listen}, '<&=0' unless $self->{_listen};

    # Accept
    my $connection = undef;
    unless (accept $connection, $self->{_listen}) {
        $self->{error} = "Can't accept connection: $!";
    }

    # Blocking sucks
    $connection->blocking(0);
    return $connection;
}

sub read_record {
    my ($self, $connection) = @_;
    return undef unless $connection;

    # Header
    my $header = $self->_read_chunk($connection, 8);
    return undef unless $header;
    my ($version, $type, $id, $clen, $plen) = unpack 'CCnnC', $header;

    # Body
    my $body = $self->_read_chunk($connection, $clen+$plen);

    # No content, just paddign bytes
    $body = undef unless $clen;

    # Ignore padding bytes
    $body = $plen ? substr($body, $clen, 0, '') : $body;

    return $self->type_name($type), $id, $body;
}

sub read_request {
    my ($self, $connection) = @_;

    # Transaction
    my $tx = $self->build_tx_cb->($self);
    $tx->connection($connection);
    my $req = $tx->req;

    # Type
    my ($type, $id, $body) = $self->read_record($connection);
    unless ($type && $type eq 'BEGIN_REQUEST') {
        $self->{error} = "First record wasn't a begin request";
        return undef;
    }
    $ENV{FCGI_ID} = $tx->{fcgi_id} = $id;

    # Role/Flags
    my ($role, $flags) = unpack 'nC', $body;
    $ENV{FCGI_ROLE} = $tx->{fcgi_role} = $self->role_name($role);

    # Slurp
    my $parambuffer = '';
    while (($type, $id, $body) = $self->read_record($connection)) {

        # Wrong id
        next unless $id == $tx->{fcgi_id};

        # Params
        if ($type eq 'PARAMS') {

            # Normal param chunk
            if ($body) {
                $parambuffer .= $body;
                next;
            }

            # Params done
            $req->state('body');
            while (length $parambuffer) {

                # Name and value length
                my $nlen = $self->_nv_length(\$parambuffer);
                my $vlen = $self->_nv_length(\$parambuffer);

                # Name and value
                my $name = substr $parambuffer, 0, $nlen, '';
                my $value = substr $parambuffer, 0, $vlen, '';

                $tx->req->parse({$name => $value});
            }
        }

        # Stdin
        elsif ($type eq 'STDIN') {

            # EOF?
            last unless $body;

            # Chunk
            $req->parse($body);
        }
    }

    return $tx;
}

sub role_name {
    my ($self, $role) = @_;
    return undef unless $role;
    return $ROLES[$role - 1];
}

sub role_number {
    my ($self, $role) = @_;
    return undef unless $role;
    return $ROLE_NUMBERS{uc $role};
}

sub run {
    my $self = shift;

    # Preload application
    $self->app;

    while (my $connection = $self->accept_connection) {
        my $tx = $self->read_request($connection);

        # Error
        next unless $tx;

        # Handle
        $self->handler_cb->($self, $tx);

        $self->write_response($tx);
    }
}

sub type_name {
    my ($self, $type) = @_;
    return undef unless $type;
    return $TYPES[$type - 1];
}

sub type_number {
    my ($self, $type) = @_;
    return undef unless $type;
    return $TYPE_NUMBERS{uc $type};
}

sub write_records {
    my ($self, $connection, $type, $id, $body) = @_;

    # Required
    return undef unless defined $connection && defined $type && defined $id;

    # Defaults
    $body ||= '';
    my $length = length $body;

    # Write records
    my $empty = 1 unless $body;
    my $offset = 0;
    while (($length > 0) || $empty) {

        # Need to split content?
        my $len = $length > 32*1024 ? 32*1024 : $length;
	    my $padlen = (8 - ($len % 8)) % 8;

        # FCGI version 1 record
        my $template = "CCnnCxa${len}x$padlen";
        my $record = pack $template, 1, $self->type_number($type), $id, $len, $padlen,
          substr($body, $offset, $len);

        my $woffset = 0;
        while ($woffset < length $record) {
            my $written = $connection->syswrite($record, undef, $woffset);
            $woffset += $written;
        }

        $length -= $len;
        $offset += $len;

        last if $empty;
    }
}

sub write_response {
    my ($self, $tx) = @_;
    my $connection = $tx->connection;
    my $res = $tx->res;

    # Status
    my $code = $res->code;
    my $message = $res->message || $res->default_message;
    $res->headers->status("$code $message") unless $res->headers->status;

    # Headers
    my $offset = 0;
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
        $offset += length $chunk;
        $self->write_records($connection, 'STDOUT', $tx->{fcgi_id}, $chunk);
    }

    # Body
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
        $offset += length $chunk;
        $self->write_records($connection, 'STDOUT', $tx->{fcgi_id}, $chunk);
    }

    # The end
    $self->write_records($connection, 'STDOUT', $tx->{fcgi_id}, undef);
    $self->write_records($connection, 'END_REQUEST', $tx->{fcgi_id}, undef);
}

sub _nv_length {
    my ($self, $bodyref) = @_;

    # Try first byte
    my $len = unpack 'C', substr($$bodyref, 0, 1, '');

    # 4 byte length
    if ($len & 0x80) {
        $len = pack 'C', $len & 0x7F;
        substr $len, 1, 0, substr($$bodyref, 0, 3, '');
        $len = unpack 'N', $len;
    }

    return $len;
}

sub _read_chunk {
    my ($self, $connection, $length) = @_;

    # Read
    my $chunk = '';
    while (length $chunk < $length) {

        # We don't wait forever
        return undef unless IO::Select->new($connection)->can_read(1);

        # Slurp
        $connection->sysread(my $buffer, $length - length $chunk, 0);
        $chunk .= $buffer;
    }

    return $chunk;
}

1;
__END__

=head1 NAME

Mojo::Server::FastCGI - FastCGI Server

=head1 SYNOPSIS

    use Mojo::Server::FastCGI;
    my $fcgi = Mojo::Server::FastCGI->new;
    $fcgi->run;

=head1 DESCRIPTION

L<Mojo::Server::FastCGI> is a portable pure-Perl FastCGI implementation.

=head1 ATTRIBUTES

L<Mojo::Server::FastCGI> inherits all attributes from L<Mojo::Server>.

=head1 METHODS

L<Mojo::Server::FastCGI> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<accept_connection>

    my $connection = $fcgi->accept_connection;

=head2 C<read_record>

    my ($type, $id, $body) = $fcgi->read_record($connection);

=head2 C<read_request>

    my $tx = $fcgi->read_request($connection);

=head2 C<role_name>

    my $name = $fcgi->role_name(3);

=head2 C<role_number>

    my $number = $fcgi->role_number('FILTER');

=head2 C<run>

    $fcgi->run;

=head2 C<type_name>

    my $name = $fcgi->type_name(5);

=head2 C<type_number>

    my $number = $fcgi->type_number('STDIN');

=head2 C<write_records>

    $fcgi->write_record($connection, 'STDOUT', $id, 'HTTP/1.1 200 OK');

=head2 C<write_response>

    $fcgi->write_response($tx);

=cut
