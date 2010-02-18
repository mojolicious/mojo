# Copyright (C) 2008-2010, Sebastian Riedel.

package MojoX::Controller;

use strict;
use warnings;

# Scalpel... blood bucket... priest.
use base 'Mojo::Base';

use Mojo::ByteStream;
use Mojo::Cookie::Response;

__PACKAGE__->attr([qw/app tx/]);

# If we don't go back there and make that event happen,
# the entire universe will be destroyed...
# And as an environmentalist, I'm against that.
sub cookie {
    my ($self, $name, $value, $options) = @_;

    # Shortcut
    return unless $name;

    # Response cookie
    if (defined $value) {

        # Cookie too big
        $self->app->log->error(qq/Cookie "$name" is bigger than 4096 bytes./)
          if length $value > 4096;

        # Create new cookie
        $options ||= {};
        my $cookie = Mojo::Cookie::Response->new(
            name  => $name,
            value => $value,
            %$options
        );
        $self->res->cookies($cookie);
        return $cookie;
    }

    # Request cookie
    unless (wantarray) {
        return unless my $cookie = $self->req->cookie($name);
        return $cookie->value;
    }

    # Request cookies
    my @cookies = $self->req->cookie($name);
    return map { $_->value } @cookies;
}

sub req { shift->tx->req }
sub res { shift->tx->res }

sub signed_cookie {
    my ($self, $name, $value, $options) = @_;

    # Shortcut
    return unless $name;

    # Secret
    my $secret = $self->app->secret;

    # Response cookie
    if (defined $value) {

        # Sign value
        my $signature =
          Mojo::ByteStream->new($value)->hmac_md5_sum($secret)->to_string;
        $value = $value .= "--$signature";

        # Create cookie
        my $cookie = $self->cookie($name, $value, $options);
        return $cookie;
    }

    # Request cookies
    my @values = $self->cookie($name);
    my @results;
    for my $value (@values) {

        # Check signature
        if ($value =~ s/\-\-([^\-]+)$//) {
            my $signature = $1;
            my $check =
              Mojo::ByteStream->new($value)->hmac_md5_sum($secret)->to_string;

            # Verified
            if ($signature eq $check) { push @results, $value }

            # Bad cookie
            else {
                $self->app->log->debug(
                    qq/Bad signed cookie "$name", possible hacking attempt./);
            }
        }

        # Not signed
        else { $self->app->log->debug(qq/Cookie "$name" not signed./) }
    }

    return wantarray ? @results : $results[0];
}

sub stash {
    my $self = shift;

    # Initialize
    $self->{stash} ||= {};

    # Hash
    return $self->{stash} unless @_;

    # Get
    return $self->{stash}->{$_[0]} unless defined $_[1] || ref $_[0];

    # Set
    my $values = exists $_[1] ? {@_} : $_[0];
    $self->{stash} = {%{$self->{stash}}, %$values};

    return $self;
}

1;
__END__

=head1 NAME

MojoX::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'MojoX::Controller';

=head1 DESCRIPTION

L<MojoX::Controller> is an abstract controllers base class.

=head2 ATTRIBUTES

L<MojoX::Controller> implements the following attributes.

=head2 C<app>

    my $app = $c->app;
    $c      = $c->app(MojoSubclass->new);

A reference back to the application that dispatched to this controller.

=head2 C<tx>

    my $tx = $c->tx;

The transaction that is currently being processed.

=head1 METHODS

L<MojoX::Controller> inherits all methods from L<Mojo::Base> and implements
the following new ones.

=head2 C<cookie>

    my $c      = $c->cookie(foo => 'bar');
    $c         = $c->cookie(foo => 'bar', {path => '/'});
    my $value  = $c->cookie('foo');
    my @values = $c->cookie('foo');

Access request cookie values and create new response cookies.

=head2 C<req>

    my $req = $c->req;

Alias for C<$c->tx->req>.
Usually refers to a L<Mojo::Message::Request> object.

=head2 C<res>

    my $res = $c->res;

Alias for C<$c->tx->res>.
Usually refers to a L<Mojo::Message::Response> object.

=head2 C<signed_cookie>

    $c         = $c->signed_cookie(foo => 'bar');
    $c         = $c->signed_cookie(foo => 'bar', {path => '/'});
    my $value  = $c->signed_cookie('foo');
    my @values = $c->signed_cookie('foo');

Access signed request cookie values and create new signed response cookies.

=head2 C<stash>

    my $stash = $c->stash;
    my $foo   = $c->stash('foo');
    $c        = $c->stash({foo => 'bar'});
    $c        = $c->stash(foo => 'bar');

Non persistent data storage and exchange.

    $c->stash->{foo} = 'bar';
    my $foo = $c->stash->{foo};
    delete $c->stash->{foo};

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Book>, L<http://mojolicious.org>.

=cut
