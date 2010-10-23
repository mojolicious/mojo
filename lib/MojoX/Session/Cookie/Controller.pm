package MojoX::Session::Cookie::Controller;

use strict;
use warnings;

use base 'MojoX::Controller';

use Mojo::ByteStream;
use Mojo::Cookie::Response;
use Mojo::Transaction::HTTP;

__PACKAGE__->attr(tx => sub { Mojo::Transaction::HTTP->new });

# For the last time, I don't like lilacs!
# Your first wife was the one who liked lilacs!
# She also liked to shut up!
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
        return $self;
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

# You two make me ashamed to call myself an idiot.
sub flash {
    my $self = shift;

    # Get
    my $session = $self->stash->{'mojo.session'};
    if ($_[0] && !defined $_[1] && !ref $_[0]) {
        return unless $session && ref $session eq 'HASH';
        return unless my $flash = $session->{old_flash};
        return unless ref $flash eq 'HASH';
        return $flash->{$_[0]};
    }

    # Initialize
    $session = $self->session;
    my $flash = $session->{flash};
    $flash = {} unless $flash && ref $flash eq 'HASH';
    $session->{flash} = $flash;

    # Hash
    return $flash unless @_;

    # Set
    my $values = exists $_[1] ? {@_} : $_[0];
    $session->{flash} = {%$flash, %$values};

    return $self;
}

sub req { shift->tx->req }
sub res { shift->tx->res }

# Why am I sticky and naked? Did I miss something fun?
sub session {
    my $self = shift;

    # Get
    my $stash   = $self->stash;
    my $session = $stash->{'mojo.session'};
    if ($_[0] && !defined $_[1] && !ref $_[0]) {
        return unless $session && ref $session eq 'HASH';
        return $session->{$_[0]};
    }

    # Initialize
    $session = {} unless $session && ref $session eq 'HASH';
    $stash->{'mojo.session'} = $session;

    # Hash
    return $session unless @_;

    # Set
    my $values = exists $_[1] ? {@_} : $_[0];
    $stash->{'mojo.session'} = {%$session, %$values};

    return $self;
}

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

1;
__END__

=head1 NAME

MojoX::Session::Cookie::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'MojoX::Session::Cookie::Controller';

=head1 DESCRIPTION

L<MojoX::Session::Cookie::Controller> is a controller base class.

=head1 ATTRIBUTES

L<MojoX::Session::Cookie::Controller> inherits all attributes from
L<MojoX::Controller> and implements the following new ones.

=head2 C<tx>

    my $tx = $c->tx;

The transaction that is currently being processed, defaults to a
L<Mojo::Transaction::HTTP> object.

=head1 METHODS

L<MojoX::Session::Cookie::Controller> inherits all methods from
L<MojoX::Controller> and implements the following ones.

=head2 C<cookie>

    $c         = $c->cookie(foo => 'bar');
    $c         = $c->cookie(foo => 'bar', {path => '/'});
    my $value  = $c->cookie('foo');
    my @values = $c->cookie('foo');

Access request cookie values and create new response cookies.

=head2 C<flash>

    my $flash = $c->flash;
    my $foo   = $c->flash('foo');
    $c        = $c->flash({foo => 'bar'});
    $c        = $c->flash(foo => 'bar');

Data storage persistent for the next request, stored in the session.

    $c->flash->{foo} = 'bar';
    my $foo = $c->flash->{foo};
    delete $c->flash->{foo};

=head2 C<req>

    my $req = $c->req;

Alias for C<$c->tx->req>.
Usually refers to a L<Mojo::Message::Request> object.

=head2 C<res>

    my $res = $c->res;

Alias for C<$c->tx->res>.
Usually refers to a L<Mojo::Message::Response> object.

=head2 C<session>

    my $session = $c->session;
    my $foo     = $c->session('foo');
    $c          = $c->session({foo => 'bar'});
    $c          = $c->session(foo => 'bar');

Persistent data storage, by default stored in a signed cookie.
Note that cookies are generally limited to 4096 bytes of data.

    $c->session->{foo} = 'bar';
    my $foo = $c->session->{foo};
    delete $c->session->{foo};

=head2 C<signed_cookie>

    $c         = $c->signed_cookie(foo => 'bar');
    $c         = $c->signed_cookie(foo => 'bar', {path => '/'});
    my $value  = $c->signed_cookie('foo');
    my @values = $c->signed_cookie('foo');

Access signed request cookie values and create new signed response cookies.
Cookies failing signature verification will be automatically discarded.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
