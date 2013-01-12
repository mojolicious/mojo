package Mojo::UserAgent::CookieJar;
use Mojo::Base -base;

use Mojo::Cookie::Request;
use Mojo::Path;

has max_cookie_size => 4096;

sub add {
  my ($self, @cookies) = @_;

  # Add cookies
  my $size = $self->max_cookie_size;
  for my $cookie (@cookies) {

    # Convert max age to expires
    if (my $age = $cookie->max_age) { $cookie->expires($age + time) }

    # Check cookie size
    next if length($cookie->value // '') > $size;

    # Replace cookie
    my $domain = $cookie->domain;
    $domain =~ s/^\.//;
    my $path = $cookie->path;
    my $name = $cookie->name;
    my $jar  = $self->{jar}{$domain} ||= [];
    @$jar = (grep({$_->path ne $path || $_->name ne $name} @$jar), $cookie);
  }

  return $self;
}

sub all {
  my $jar = shift->{jar};
  return map { @{$jar->{$_}} } sort keys %$jar;
}

sub empty { shift->{jar} = {} }

sub extract {
  my ($self, $tx) = @_;
  my $url = $tx->req->url;
  for my $cookie (@{$tx->res->cookies}) {

    # Validate domain
    my $host = lc $url->host;
    my $domain = lc($cookie->domain // $host);
    next unless $host eq $domain || $host =~ /\Q.$domain\E$/;
    $cookie->domain($domain);

    # Validate path
    my $path = $cookie->path // $url->path->to_dir->to_abs_string;
    $path = Mojo::Path->new($path)->trailing_slash(0)->to_abs_string;
    next unless _path($path, $url->path->to_abs_string);
    $self->add($cookie->path($path));
  }
}

sub find {
  my ($self, $url) = @_;

  # Look through the jar
  return unless my $domain = lc($url->ihost // '');
  my $path = $url->path->to_abs_string;
  my @found;
  while ($domain =~ /[^.]+\.[^.]+|localhost$/) {
    next unless my $old = $self->{jar}{$domain};

    # Grab cookies
    my $new = $self->{jar}{$domain} = [];
    for my $cookie (@$old) {

      # Check if cookie has expired
      my $expires = $cookie->expires;
      next if $expires && time > ($expires->epoch || 0);
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
  continue { $domain =~ s/^[^.]+\.?// }

  return @found;
}

sub inject {
  my ($self, $tx) = @_;
  return unless keys %{$self->{jar}};
  my $req = $tx->req;
  $req->cookies($self->find($req->url));
}

sub _path { $_[0] eq '/' || $_[0] eq $_[1] || $_[1] =~ m!^\Q$_[0]/! }

1;

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
  for my $cookie ($jar->find(Mojo::URL->new('http://localhost/test'))) {
    say $cookie->name;
    say $cookie->value;
  }

=head1 DESCRIPTION

L<Mojo::UserAgent::CookieJar> is a minimalistic and relaxed cookie jar used by
L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojo::UserAgent::CookieJar> implements the following attributes.

=head2 max_cookie_size

  my $size = $jar->max_cookie_size;
  $jar     = $jar->max_cookie_size(4096);

Maximum cookie size in bytes, defaults to C<4096>.

=head1 METHODS

L<Mojo::UserAgent::CookieJar> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 add

  $jar = $jar->add(@cookies);

Add multiple L<Mojo::Cookie::Response> objects to the jar.

=head2 all

  my @cookies = $jar->all;

Return all L<Mojo::Cookie::Response> objects that are currently stored in the
jar.

=head2 empty

  $jar->empty;

Empty the jar.

=head2 extract

  $jar->extract($tx);

Extract response cookies from transaction.

=head2 find

  my @cookies = $jar->find($url);

Find L<Mojo::Cookie::Request> objects in the jar for L<Mojo::URL> object.

=head2 inject

  $jar->inject($tx);

Inject request cookies into transaction.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
