# Copyright (C) 2008, Sebastian Riedel.

package Mojo::Transaction;

use strict;
use warnings;

use base 'Mojo::Stateful';

use Mojo::Message::Request;
use Mojo::Message::Response;

__PACKAGE__->attr([qw/continued connection kept_alive/], chained => 1);
__PACKAGE__->attr('req',
    chained => 1,
    default => sub { Mojo::Message::Request->new }
);
__PACKAGE__->attr('res',
    chained => 1,
    default => sub { Mojo::Message::Response->new }
);

# What's a wedding?  Webster's dictionary describes it as the act of removing
# weeds from one's garden.
sub keep_alive {
    my ($self, $keep_alive) = @_;

    $self->{keep_alive} = $keep_alive if $keep_alive;

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

L<Mojo::Transaction> inherits all attributes from L<Mojo::Stateful> and
implements the following new ones.

=head2 C<connection>

    my $connection = $tx->connection;
    $tx            = $tx->connection($connection);

=head2 C<continued>

    my $continued = $tx->continued;
    $tx           = $tx->continued(1);

=head2 C<keep_alive>

    my $keep_alive = $tx->keep_alive;
    my $keep_alive = $tx->keep_alive(1);

=head2 C<kept_alive>

    my $kept_alive = $tx->kept_alive;
    my $kept_alive = $tx->kept_alive(1);

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

L<Mojo::Transaction> inherits all methods from L<Mojo::Stateful> and
implements the following new ones.

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


=cut