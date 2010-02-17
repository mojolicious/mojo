# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Session::Simple;

use strict;
use warnings;

use base 'Mojo::Base';

use Mojo::ByteStream 'b';
use Storable qw/freeze thaw/;

__PACKAGE__->attr(cookie_name        => 'session');
__PACKAGE__->attr(default_expiration => 3600);

# Bender, quit destroying the universe!
sub load {
    my ($self, $c) = @_;

    # Session cookie
    return unless my $value = $c->signed_cookie($self->cookie_name);

    # Decode
    $value = b($value)->b64_decode->to_string;

    # Thaw
    my $session = thaw $value;

    # Expiration
    return unless my $expires = delete $session->{expires};
    return unless $expires > time;

    # Content
    return unless keys %$session;
    $c->stash->{session} = $session;

    # Flash
    $session->{_flash} = delete $session->{flash} if $session->{flash};
}

# Emotions are dumb and should be hated.
sub store {
    my ($self, $c) = @_;

    # Session
    return unless my $session = $c->stash->{session};

    # Flash
    delete $session->{_flash};
    delete $session->{flash} unless keys %{$session->{flash}};

    # Expiration
    my $expires = $session->{expires} ||= time + $self->default_expiration;

    # Freeze
    my $value = freeze $session;

    # Encode
    $value = b($value)->b64_encode->to_string;
    $value =~ s/\n//g;

    # Session cookie
    $c->signed_cookie($self->cookie_name, $value)->expires($expires);
}

1;
__END__

=head1 NAME

MojoX::Session::Simple - Simple Sessions

=head1 SYNOPSIS

    use MojoX::Session::Simple;
    use MojoX::Session::Simple::Controller;

    my $session = MojoX::Session::Simple->new;
    my $c = MojoX::Session::Simple::Controller->new;
    $session->load($c);
    $c->session(foo => 'bar');
    $session->store($c);

=head1 DESCRIPTION

L<MojoX::Session::Simple> is a very simple signed cookie based session
implementation.
All data gets stored on the client side, but is protected from unwanted
changes with a signature.

=head2 ATTRIBUTES

L<MojoX::Session::Simple> implements the following attributes.

=head2 C<cookie_name>

    my $name = $session->cookie_name;
    $session = $session->cookie_name('session');

Name of the signed cookie used to store session data, defaults to C<session>.

=head2 C<default_expiration>

    my $time = $session->default_expiration;
    $session = $session->default_expiration(3600);

Time in seconds from now for the session to expire, defaults to C<3600>.

=head1 METHODS

L<MojoX::Session::Simple> inherits all methods from L<Mojo::Base> and
implements the follwing the ones.

=head2 C<load>

    $session->load($c);

Load session data from signed cookie.

=head2 C<store>

    $session->store($c);

Store session data in signed cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
