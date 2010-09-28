package Mojo::Server::PSGI;

use strict;
use warnings;

use base 'Mojo::Server';

use constant CHUNK_SIZE => $ENV{MOJO_CHUNK_SIZE} || 262144;

# Things aren't as happy as they used to be down here at the unemployment
# office.
# Joblessness is no longer just for philosophy majors.
# Useful people are starting to feel the pinch.
sub run {
    my ($self, $env) = @_;

    my $tx  = $self->on_build_tx->($self);
    my $req = $tx->req;

    # Environment
    $req->parse($env);

    # Store connection information
    $tx->remote_address($env->{REMOTE_ADDR});
    $tx->local_port($env->{SERVER_PORT});

    # Request body
    while (!$req->is_done) {
        my $read = $env->{'psgi.input'}->read(my $buffer, CHUNK_SIZE, 0);
        last if $read == 0;
        $req->parse($buffer);
    }

    # Handle
    $self->on_handler->($self, $tx);

    my $res = $tx->res;

    # Status
    my $status = $res->code;

    # Response headers
    $res->fix_headers;
    my $headers = $res->content->headers;
    my @headers;
    for my $name (@{$headers->names}) {
        my $value = $headers->header($name);
        push @headers, $name => $value;
    }

    # Response body
    my $body = Mojo::Server::PSGI::_Handle->new(_res => $res);

    # Finish transaction
    $tx->on_finish->($tx);

    return [$status, \@headers, $body];
}

package Mojo::Server::PSGI::_Handle;

use strict;
use warnings;

use base 'Mojo::Base';

__PACKAGE__->attr(_offset => 0);
__PACKAGE__->attr('_res');

sub close { }

sub getline {
    my $self = shift;

    # Blocking read
    my $offset = $self->_offset;
    while (1) {
        my $chunk = $self->_res->get_body_chunk($offset);

        # No content yet, try again
        unless (defined $chunk) {
            sleep 1;
            next;
        }

        # End of content
        last unless length $chunk;

        # Content
        $offset += length $chunk;
        $self->_offset($offset);
        return $chunk;
    }

    return;
}

1;
__END__

=head1 NAME

Mojo::Server::PSGI - PSGI Server

=head1 SYNOPSIS

    # myapp.psgi
    use Mojo::Server::PSGI;
    my $psgi = Mojo::Server::PSGI->new(app_class => 'MyApp');
    my $app  = sub { $psgi->run(@_) };

=head1 DESCRIPTION

L<Mojo::Server::PSGI> allows L<Mojo> applications to run on all PSGI
compatible servers.

=head1 METHODS

L<Mojo::Server::PSGI> inherits all methods from L<Mojo::Server> and
implements the following new ones.

=head2 C<run>

    my $res = $psgi->run($env);

Start PSGI.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
