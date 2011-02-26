package Mojo::CookieJar;
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
  for my $cookie (@cookies) {

    # Unique cookie id
    my $domain = $cookie->domain;
    my $path   = $cookie->path;
    my $name   = $cookie->name;

    # Convert max age to expires
    $cookie->expires($cookie->max_age + time) if $cookie->max_age;

    # Default to session cookie
    $cookie->max_age(0) unless $cookie->expires || $cookie->max_age;

    # Cookie too big
    my $value = $cookie->value;
    next if length(defined $value ? $value : '') > $self->max_cookie_size;

    # Initialize
    $self->{_jar}->{$domain} ||= [];

    # Check if we already have a similar cookie
    my @new;
    for my $old (@{$self->{_jar}->{$domain}}) {

      # Unique cookie id
      push @new, $old unless $old->path eq $path && $old->name eq $name;
    }

    # Add
    push @new, $cookie;
    $self->{_jar}->{$domain} = \@new;
  }

  return $self;
}

sub empty { shift->{_jar} = {} }

sub extract {
  my ($self, $tx) = @_;

  # URL
  my $url = $tx->req->url;

  # Fix cookies
  my @cookies = @{$tx->res->cookies};
  for my $cookie (@cookies) {

    # Domain
    $cookie->domain($url->host) unless $cookie->domain;

    # Path
    $cookie->path($url->path) unless $cookie->path;
  }

  # Store
  $self->add(@cookies);
}

sub find {
  my ($self, $url) = @_;

  # Pattern
  return unless my $domain = $url->host;
  my $path = $url->path->to_string || '/';

  # Find
  my @found;
  while ($domain =~ /[^\.]+\.[^\.]+|localhost$/) {

    # Nothing
    next unless my $jar = $self->{_jar}->{$domain};

    # Look inside
    my @new;
    for my $cookie (@$jar) {

      # Session cookie
      my $session = defined $cookie->max_age && $cookie->max_age > 0 ? 1 : 0;
      if ($cookie->expires && !$session) {

        # Expired
        next if time > ($cookie->expires->epoch || 0);
      }

      # Not expired
      push @new, $cookie;

      # Port
      my $port = $url->port || 80;
      next if $cookie->port && $port != $cookie->port;

      # Protocol
      next if $cookie->secure && $url->scheme ne 'https';

      # Path
      my $cpath = $cookie->path;
      push @found,
        Mojo::Cookie::Request->new(
        name    => $cookie->name,
        value   => $cookie->value,
        path    => $cookie->path,
        version => $cookie->version,
        secure  => $cookie->secure
        ) if $path =~ /^$cpath/;
    }
    $self->{_jar}->{$domain} = \@new;
  }

  # Remove leading dot or part
  continue { $domain =~ s/^(?:\.|[^\.]+)// }

  return @found;
}

sub inject {
  my ($self, $tx) = @_;

  # Empty jar
  return unless keys %{$self->{_jar}};

  # Request
  my $req = $tx->req;

  # URL
  my $url = $req->url->clone;
  if (my $host = $req->headers->host) { $url->host($host) }

  # Fetch
  $req->cookies($self->find($url));
}

1;
__END__

=head1 NAME

Mojo::CookieJar - Cookie Jar For HTTP 1.1 User Agents

=head1 SYNOPSIS

  use Mojo::CookieJar;
  my $jar = Mojo::CookieJar->new;

=head1 DESCRIPTION

L<Mojo::CookieJar> is a minimalistic cookie jar for HTTP 1.1 user agents.

=head1 ATTRIBUTES

L<Mojo::CookieJar> implements the following attributes.

=head2 C<max_cookie_size>

  my $max_cookie_size = $jar->max_cookie_size;
  $jar                = $jar->max_cookie_size(4096);

Maximum size of cookies in bytes.

=head1 METHODS

L<Mojo::CookieJar> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<add>

  $jar = $jar->add(@cookies);

Add multiple cookies to the jar.

=head2 C<empty>

  $jar->empty;

Empty the jar.

=head2 C<extract>

  $jar = $jar->extract($tx);

Extract cookies from transaction.

=head2 C<find>

  my @cookies = $jar->find($url);

Find cookies in the jar.

=head2 C<inject>

  $jar = $jar->inject($tx);

Inject cookies into transaction.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
