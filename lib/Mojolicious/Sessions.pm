package Mojolicious::Sessions;
use Mojo::Base -base;

use Mojo::JSON;
use Mojo::Util qw(b64_decode b64_encode);

has [qw(cookie_domain secure)];
has cookie_name        => 'mojolicious';
has cookie_path        => '/';
has default_expiration => 3600;

sub load {
  my ($self, $c) = @_;

  return unless my $value = $c->signed_cookie($self->cookie_name);
  $value =~ s/-/=/g;
  return unless my $session = Mojo::JSON->new->decode(b64_decode $value);

  # "expiration" value is inherited
  my $expiration = $session->{expiration} // $self->default_expiration;
  return if !(my $expires = delete $session->{expires}) && $expiration;
  return if defined $expires && $expires <= time;

  my $stash = $c->stash;
  return unless $stash->{'mojo.active_session'} = keys %$session;
  $stash->{'mojo.session'} = $session;
  $session->{flash} = delete $session->{new_flash} if $session->{new_flash};
}

sub store {
  my ($self, $c) = @_;

  # Make sure session was active
  my $stash = $c->stash;
  return unless my $session = $stash->{'mojo.session'};
  return unless keys %$session || $stash->{'mojo.active_session'};

  # Don't reset flash for static files
  my $old = delete $session->{flash};
  @{$session->{new_flash}}{keys %$old} = values %$old
    if $stash->{'mojo.static'};
  delete $session->{new_flash} unless keys %{$session->{new_flash}};

  # Generate "expires" value from "expiration" if necessary
  my $expiration = $session->{expiration} // $self->default_expiration;
  my $default = delete $session->{expires};
  $session->{expires} = $default || time + $expiration
    if $expiration || $default;

  my $value = b64_encode(Mojo::JSON->new->encode($session), '');
  $value =~ s/=/-/g;
  my $options = {
    domain   => $self->cookie_domain,
    expires  => $session->{expires},
    httponly => 1,
    path     => $self->cookie_path,
    secure   => $self->secure
  };
  $c->signed_cookie($self->cookie_name, $value, $options);
}

1;

=head1 NAME

Mojolicious::Sessions - Signed cookie based session manager

=head1 SYNOPSIS

  use Mojolicious::Sessions;

  my $sessions = Mojolicious::Sessions->new;
  $sessions->cookie_name('myapp');
  $sessions->default_expiration(86400);

=head1 DESCRIPTION

L<Mojolicious::Sessions> manages simple signed cookie based sessions for
L<Mojolicious>. All data gets serialized with L<Mojo::JSON> and stored
C<Base64> encoded on the client-side, but is protected from unwanted changes
with a C<HMAC-SHA1> signature.

=head1 ATTRIBUTES

L<Mojolicious::Sessions> implements the following attributes.

=head2 cookie_domain

  my $domain = $sessions->cookie_domain;
  $sessions  = $sessions->cookie_domain('.example.com');

Domain for session cookies, not defined by default.

=head2 cookie_name

  my $name  = $sessions->cookie_name;
  $sessions = $sessions->cookie_name('session');

Name for session cookies, defaults to C<mojolicious>.

=head2 cookie_path

  my $path  = $sessions->cookie_path;
  $sessions = $sessions->cookie_path('/foo');

Path for session cookies, defaults to C</>.

=head2 default_expiration

  my $time  = $sessions->default_expiration;
  $sessions = $sessions->default_expiration(3600);

Default time for sessions to expire in seconds from now, defaults to C<3600>.
The expiration timeout gets refreshed for every request. Setting the value to
C<0> will allow sessions to persist until the browser window is closed, this
can have security implications though. For more control you can also use the
C<expiration> and C<expires> session values.

  # Expiration date in seconds from now (persists between requests)
  $c->session(expiration => 604800);

  # Expiration date as absolute epoch time (only valid for one request)
  $c->session(expires => time + 604800);

  # Delete whole session by setting an expiration date in the past
  $c->session(expires => 1);

=head2 secure

  my $secure = $sessions->secure;
  $sessions  = $sessions->secure(1);

Set the secure flag on all session cookies, so that browsers send them only
over HTTPS connections.

=head1 METHODS

L<Mojolicious::Sessions> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 load

  $sessions->load(Mojolicious::Controller->new);

Load session data from signed cookie.

=head2 store

  $sessions->store(Mojolicious::Controller->new);

Store session data in signed cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
