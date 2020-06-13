package Mojo::UserAgent::CookieJar;
use Mojo::Base -base;

use Mojo::Cookie::Request;
use Mojo::Path;
use Scalar::Util qw(looks_like_number);

has 'ignore';
has max_cookie_size => 4096;

sub add {
  my ($self, @cookies) = @_;

  my $size = $self->max_cookie_size;
  for my $cookie (@cookies) {

    # Convert max age to expires
    my $age = $cookie->max_age;
    $cookie->expires($age <= 0 ? 0 : $age + time) if looks_like_number $age;

    # Check cookie size
    next if length($cookie->value // '') > $size;

    # Replace cookie
    next unless my $domain = lc($cookie->domain // '');
    next unless my $path   = $cookie->path;
    next unless length(my $name = $cookie->name // '');
    my $jar = $self->{jar}{$domain} ||= [];
    @$jar = (grep({ _compare($_, $path, $name, $domain) } @$jar), $cookie);
  }

  return $self;
}

sub all {
  my $jar = shift->{jar};
  return [map { @{$jar->{$_}} } sort keys %$jar];
}

sub collect {
  my ($self, $tx) = @_;

  my $url = $tx->req->url;
  for my $cookie (@{$tx->res->cookies}) {

    # Validate domain
    my $host = lc $url->ihost;
    $cookie->domain($host)->host_only(1) unless $cookie->domain;
    my $domain = lc $cookie->domain;
    if (my $cb = $self->ignore) { next if $cb->($cookie) }
    next if $host ne $domain && ($host !~ /\Q.$domain\E$/ || $host =~ /\.\d+$/);

    # Validate path
    my $path = $cookie->path // $url->path->to_dir->to_abs_string;
    $path = Mojo::Path->new($path)->trailing_slash(0)->to_abs_string;
    next unless _path($path, $url->path->to_abs_string);
    $self->add($cookie->path($path));
  }
}

sub empty { delete shift->{jar} }

sub find {
  my ($self, $url) = @_;

  my @found;
  my $domain = my $host = lc $url->ihost;
  my $path   = $url->path->to_abs_string;
  while ($domain) {
    next unless my $old = $self->{jar}{$domain};

    # Grab cookies
    my $new = $self->{jar}{$domain} = [];
    for my $cookie (@$old) {
      next if $cookie->host_only && $host ne $cookie->domain;

      # Check if cookie has expired
      if (defined(my $expires = $cookie->expires)) { next if time > $expires }
      push @$new, $cookie;

      # Taste cookie
      next if $cookie->secure && $url->protocol ne 'https';
      next unless _path($cookie->path, $path);
      my $name  = $cookie->name;
      my $value = $cookie->value;
      push @found, Mojo::Cookie::Request->new(name => $name, value => $value);
    }
  }

  # Remove another part
  continue { $domain =~ s/^[^.]*\.*// }

  return \@found;
}

sub prepare {
  my ($self, $tx) = @_;
  return unless keys %{$self->{jar}};
  my $req = $tx->req;
  $req->cookies(@{$self->find($req->url)});
}

sub _compare {
  my ($cookie, $path, $name, $domain) = @_;
  return $cookie->path ne $path || $cookie->name ne $name || $cookie->domain ne $domain;
}

sub _path { $_[0] eq '/' || $_[0] eq $_[1] || index($_[1], "$_[0]/") == 0 }

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent::CookieJar - Cookie jar for HTTP user agents

=head1 SYNOPSIS

  use Mojo::UserAgent::CookieJar;

  # Add response cookies
  my $jar = Mojo::UserAgent::CookieJar->new;
  $jar->add(
    Mojo::Cookie::Response->new(
      name   => 'foo',
      value  => 'bar',
      domain => 'localhost',
      path   => '/test'
    )
  );

  # Find request cookies
  for my $cookie (@{$jar->find(Mojo::URL->new('http://localhost/test'))}) {
    say $cookie->name;
    say $cookie->value;
  }

=head1 DESCRIPTION

L<Mojo::UserAgent::CookieJar> is a minimalistic and relaxed cookie jar used by L<Mojo::UserAgent>, based on L<RFC
6265|http://tools.ietf.org/html/rfc6265>.

=head1 ATTRIBUTES

L<Mojo::UserAgent::CookieJar> implements the following attributes.

=head2 ignore

  my $ignore = $jar->ignore;
  $jar       = $jar->ignore(sub {...});

A callback used to decide if a cookie should be ignored by L</"collect">.

  # Ignore all cookies
  $jar->ignore(sub { 1 });

  # Ignore cookies for domains "com", "net" and "org"
  $jar->ignore(sub {
    my $cookie = shift;
    return undef unless my $domain = $cookie->domain;
    return $domain eq 'com' || $domain eq 'net' || $domain eq 'org';
  });

=head2 max_cookie_size

  my $size = $jar->max_cookie_size;
  $jar     = $jar->max_cookie_size(4096);

Maximum cookie size in bytes, defaults to C<4096> (4KiB).

=head1 METHODS

L<Mojo::UserAgent::CookieJar> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 add

  $jar = $jar->add(@cookies);

Add multiple L<Mojo::Cookie::Response> objects to the jar.

=head2 all

  my $cookies = $jar->all;

Return all L<Mojo::Cookie::Response> objects that are currently stored in the jar.

  # Names of all cookies
  say $_->name for @{$jar->all};

=head2 collect

  $jar->collect(Mojo::Transaction::HTTP->new);

Collect response cookies from transaction.

=head2 empty

  $jar->empty;

Empty the jar.

=head2 find

  my $cookies = $jar->find(Mojo::URL->new);

Find L<Mojo::Cookie::Request> objects in the jar for L<Mojo::URL> object.

  # Names of all cookies found
  say $_->name for @{$jar->find(Mojo::URL->new('http://example.com/foo'))};

=head2 prepare

  $jar->prepare(Mojo::Transaction::HTTP->new);

Prepare request cookies for transaction.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
