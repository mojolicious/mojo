package Mojolicious::Sessions;
use Mojo::Base -base;

use Mojo::JSON;
use Mojo::Util qw/b64_decode b64_encode/;

has 'cookie_domain';
has cookie_name        => 'mojolicious';
has cookie_path        => '/';
has default_expiration => 3600;
has secure             => 0;

# JSON serializer
my $JSON = Mojo::JSON->new;

# "Bender, quit destroying the universe!"
sub load {
  my ($self, $c) = @_;

  # Session cookie
  return unless my $value = $c->signed_cookie($self->cookie_name);

  # Decode
  $value =~ s/\-/\=/g;
  b64_decode $value;

  # Deserialize
  return unless my $session = $JSON->decode($value);

  # Expiration
  return unless my $expires = delete $session->{expires};
  return unless $expires > time;

  # Content
  my $stash = $c->stash;
  return unless $stash->{'mojo.active_session'} = keys %$session;
  $stash->{'mojo.session'} = $session;

  # Flash
  $session->{flash} = delete $session->{new_flash} if $session->{new_flash};
}

# "Emotions are dumb and should be hated."
sub store {
  my ($self, $c) = @_;

  # Session
  my $stash = $c->stash;
  return unless my $session = $stash->{'mojo.session'};
  return unless keys %$session || $stash->{'mojo.active_session'};

  # Flash
  my $old = delete $session->{flash};
  @{$session->{new_flash}}{keys %$old} = values %$old
    if $stash->{'mojo.static'};
  delete $session->{new_flash} unless keys %{$session->{new_flash}};

  # Default to expiring session
  my $expires = 1;
  my $value   = '';

  # Actual session data
  my $default = delete $session->{expires};
  if (keys %$session) {

    # Expiration
    $expires = $session->{expires} = $default
      ||= time + $self->default_expiration;

    # Serialize
    $value = $JSON->encode($session);

    # Encode
    b64_encode $value, '';
    $value =~ s/\=/\-/g;
  }

  # Options
  my $options = {expires => $expires, path => $self->cookie_path};
  my $domain = $self->cookie_domain;
  $options->{domain} = $domain if $domain;
  $options->{secure} = 1       if $self->secure;

  # Session cookie
  $c->signed_cookie($self->cookie_name, $value, $options);
}

1;
__END__

=head1 NAME

Mojolicious::Sessions - Signed Cookie Based Sessions

=head1 SYNOPSIS

  use Mojolicious::Sessions;

=head1 DESCRIPTION

L<Mojolicious::Sessions> is a very simple signed cookie based session
implementation.
All data gets serialized with L<Mojo::JSON> and stored on the client side,
but is protected from unwanted changes with a signature.

=head1 ATTRIBUTES

L<Mojolicious::Sessions> implements the following attributes.

=head2 C<cookie_domain>

  my $domain = $session->cookie_domain;
  $session   = $session->cookie_domain('.example.com');

Domain for session cookie, not defined by default.

=head2 C<cookie_name>

  my $name = $session->cookie_name;
  $session = $session->cookie_name('session');

Name of the signed cookie used to store session data, defaults to
C<mojolicious>.

=head2 C<cookie_path>

  my $path = $session->cookie_path;
  $session = $session->cookie_path('/foo');

Path for session cookie, defaults to C</>.

=head2 C<default_expiration>

  my $time = $session->default_expiration;
  $session = $session->default_expiration(3600);

Time for the session to expire in seconds from now, defaults to C<3600>.
The expiration timeout gets refreshed for every request.

=head2 C<secure>

  my $secure = $session->secure;
  $session   = $session->secure(1);

Set the secure flag on all session cookies, so that browsers send them only
over HTTPS connections.

=head1 METHODS

L<Mojolicious::Sessions> inherits all methods from L<Mojo::Base> and
implements the following ones.

=head2 C<load>

  $session->load($c);

Load session data from signed cookie.

=head2 C<store>

  $session->store($c);

Store session data in signed cookie.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
