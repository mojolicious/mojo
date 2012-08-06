package Mojo::UserAgent::CookieJar;
use Mojo::Base -base;

use Mojo::Cookie::Request;

has max_cookie_size => 4096;

# "I can't help but feel this is all my fault.
#  It was those North Korean fortune cookies - they were so insulting.
#  'You are a coward'
#  Nobody wants to hear that after a nice meal.
#  Marge, you can't keep blaming yourself.
#  Just blame yourself once, then move on."
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

sub empty { shift->{jar} = {} }

sub extract {
  my ($self, $tx) = @_;
  my $url = $tx->req->url;
  for my $cookie (@{$tx->res->cookies}) {
    $cookie->domain($url->host) unless $cookie->domain;
    $cookie->path($url->path)   unless $cookie->path;
    $self->add($cookie);
  }
}

# "Dear Homer, IOU one emergency donut.
#  Signed Homer.
#  Bastard!
#  He's always one step ahead."
sub find {
  my ($self, $url) = @_;

  # Look through the jar
  return unless my $domain = $url->host;
  my $path = $url->path->to_string || '/';
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
      next if $cookie->secure && $url->scheme ne 'https';
      next unless $path =~ /^\Q@{[$cookie->path]}/;
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

L<Mojo::UserAgent::CookieJar> is a minimalistic and relaxed cookie jar for
HTTP user agents.

=head1 ATTRIBUTES

L<Mojo::UserAgent::CookieJar> implements the following attributes.

=head2 C<max_cookie_size>

  my $max_cookie_size = $jar->max_cookie_size;
  $jar                = $jar->max_cookie_size(4096);

Maximum cookie size in bytes, defaults to C<4096>.

=head1 METHODS

L<Mojo::UserAgent::CookieJar> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<add>

  $jar = $jar->add(@cookies);

Add multiple L<Mojo::Cookie::Response> objects to the jar.

=head2 C<empty>

  $jar->empty;

Empty the jar.

=head2 C<extract>

  $jar = $jar->extract($tx);

Extract response cookies from transaction.

=head2 C<find>

  my @cookies = $jar->find($url);

Find L<Mojo::Cookie::Request> objects in the jar for L<Mojo::URL> object.

=head2 C<inject>

  $jar = $jar->inject($tx);

Inject request cookies into transaction.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
