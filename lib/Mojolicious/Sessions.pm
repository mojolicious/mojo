package Mojolicious::Sessions;
use Mojo::Base -base;

use Mojo::JSON;
use Mojo::Util qw(b64_decode b64_encode);

has [qw(cookie_domain encrypted partitioned secure)];
has cookie_name        => 'mojolicious';
has cookie_path        => '/';
has default_expiration => 3600;
has deserialize        => sub { \&_deserialize };
has samesite           => 'Lax';
has serialize          => sub { \&_serialize };

sub load {
  my ($self, $c) = @_;

  my $method = $self->encrypted ? 'encrypted_cookie' : 'signed_cookie';
  return unless my $value = $c->$method($self->cookie_name);
  $value =~ y/-/=/;
  return unless my $session = $self->deserialize->(b64_decode $value);

  # "expiration" value is inherited
  my $expiration = $session->{expiration} // $self->default_expiration;
  return if !(my $expires = delete $session->{expires}) && $expiration;
  return if defined $expires                            && $expires <= time;

  my $stash = $c->stash;
  return unless $stash->{'mojo.active_session'} = keys %$session;
  $stash->{'mojo.session'} = $session;
  $session->{flash}        = delete $session->{new_flash} if $session->{new_flash};
}

sub store {
  my ($self, $c) = @_;

  # Make sure session was active
  my $stash = $c->stash;
  return unless my $session = $stash->{'mojo.session'};
  return unless keys %$session || $stash->{'mojo.active_session'};

  # Don't reset flash for static files
  my $old = delete $session->{flash};
  $session->{new_flash} = $old if $stash->{'mojo.static'};
  delete $session->{new_flash} unless keys %{$session->{new_flash}};

  # Generate "expires" value from "expiration" if necessary
  my $expiration = $session->{expiration} // $self->default_expiration;
  my $default    = delete $session->{expires};
  $session->{expires} = $default || time + $expiration if $expiration || $default;

  my $value = b64_encode $self->serialize->($session), '';
  $value =~ y/=/-/;
  my $options = {
    domain      => $self->cookie_domain,
    expires     => $session->{expires},
    httponly    => 1,
    partitioned => $self->partitioned,
    path        => $self->cookie_path,
    samesite    => $self->samesite,
    secure      => $self->secure,
  };
  my $method = $self->encrypted ? 'encrypted_cookie' : 'signed_cookie';
  $c->$method($self->cookie_name, $value, $options);
}

# DEPRECATED! (Remove once old sessions with padding are no longer a concern)
sub _deserialize { Mojo::JSON::decode_json($_[0] =~ s/\}\KZ*$//r) }

sub _serialize { Mojo::JSON::encode_json($_[0]) }

1;

=encoding utf8

=head1 NAME

Mojolicious::Sessions - Session manager based on signed cookies

=head1 SYNOPSIS

  use Mojolicious::Sessions;

  my $sessions = Mojolicious::Sessions->new;
  $sessions->cookie_name('myapp');
  $sessions->default_expiration(86400);

=head1 DESCRIPTION

L<Mojolicious::Sessions> manages sessions based on signed cookies for L<Mojolicious>. All data gets serialized with
L<Mojo::JSON> and stored Base64 encoded on the client-side, but is protected from unwanted changes with a HMAC-SHA256
signature.

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

Default time for sessions to expire in seconds from now, defaults to C<3600>. The expiration timeout gets refreshed for
every request. Setting the value to C<0> will allow sessions to persist until the browser window is closed, this can
have security implications though. For more control you can also use the C<expiration> and C<expires> session values.

  # Expiration date in seconds from now (persists between requests)
  $c->session(expiration => 604800);

  # Expiration date as absolute epoch time (only valid for one request)
  $c->session(expires => time + 604800);

  # Delete whole session by setting an expiration date in the past
  $c->session(expires => 1);

=head2 deserialize

  my $cb    = $sessions->deserialize;
  $sessions = $sessions->deserialize(sub ($bytes) {...});

A callback used to deserialize sessions, defaults to L<Mojo::JSON/"j">.

  $sessions->deserialize(sub ($bytes) { return {} });

=head2 encrypted

  my $bool  = $sessions->encrypted;
  $sessions = $sessions->encrypted($bool);

Use encrypted session cookies instead of merely cryptographically signed ones. Note that this attribute is
B<EXPERIMENTAL> and might change without warning!

=head2 partitioned

  my $bool  = $sessions->partitioned;
  $sessions = $sessions->partitioned($bool);

Partitioned flag, this is to be used in accordance to the CHIPS amendment to RFC 6265.
Note that this attribute is B<EXPERIMENTAL> because even though most commonly used browsers support the
feature, there is no specification yet besides L<this
draft|https://www.ietf.org/archive/id/draft-cutler-httpbis-partitioned-cookies-00.html>.

Partitioned cookies are held within a separate cookie jar per top-level site.

=head2 samesite

  my $samesite = $sessions->samesite;
  $sessions    = $sessions->samesite('Strict');

Set the SameSite value on all session cookies, defaults to C<Lax>. Note that this attribute is B<EXPERIMENTAL> because
even though most commonly used browsers support the feature, there is no specification yet besides L<this
draft|https://tools.ietf.org/html/draft-west-first-party-cookies-07>.

  # Disable SameSite feature
  $sessions->samesite(undef);

=head2 secure

  my $bool  = $sessions->secure;
  $sessions = $sessions->secure($bool);

Set the secure flag on all session cookies, so that browsers send them only over HTTPS connections.

=head2 serialize

  my $cb    = $sessions->serialize;
  $sessions = $sessions->serialize(sub ($hash) {...});

A callback used to serialize sessions, defaults to L<Mojo::JSON/"encode_json">.

  $sessions->serialize(sub ($hash) { return '' });

=head1 METHODS

L<Mojolicious::Sessions> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 load

  $sessions->load(Mojolicious::Controller->new);

Load session data from signed cookie.

=head2 store

  $sessions->store(Mojolicious::Controller->new);

Store session data in signed cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
