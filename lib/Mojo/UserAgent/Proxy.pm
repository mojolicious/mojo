package Mojo::UserAgent::Proxy;
use Mojo::Base -base;

has [qw(http https not)];

sub detect {
  my $self = shift;
  $self->http($ENV{HTTP_PROXY}   || $ENV{http_proxy});
  $self->https($ENV{HTTPS_PROXY} || $ENV{https_proxy});
  return $self->not([split /,/, $ENV{NO_PROXY} || $ENV{no_proxy} || '']);
}

sub inject {
  my ($self, $tx) = @_;

  $self->detect if $ENV{MOJO_PROXY};
  my $req = $tx->req;
  my $url = $req->url;
  return if !$self->is_needed($url->host) || defined $req->proxy;

  # HTTP proxy
  my $proto = $url->protocol;
  my $http  = $self->http;
  $req->proxy($http) if $http && $proto eq 'http';

  # HTTPS proxy
  my $https = $self->https;
  $req->proxy($https) if $https && $proto eq 'https';
}

sub is_needed {
  !grep { $_[1] =~ /\Q$_\E$/ } @{$_[0]->not || []};
}

1;

=encoding utf8

=head1 NAME

Mojo::UserAgent::Proxy - User agent proxy manager

=head1 SYNOPSIS

  use Mojo::UserAgent::Proxy;

  my $proxy = Mojo::UserAgent::Proxy->new;
  $proxy->detect;
  say $proxy->http;

=head1 DESCRIPTION

L<Mojo::UserAgent::Proxy> manages proxy servers for L<Mojo::UserAgent>.

=head1 ATTRIBUTES

L<Mojo::UserAgent::Proxy> implements the following attributes.

=head2 http

  my $http = $ua->http;
  $ua      = $ua->http('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTP and WebSocket requests.

=head2 https

  my $https = $ua->https;
  $ua       = $ua->https('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTPS and WebSocket requests.

=head2 not

  my $not = $proxy->not;
  $ua     = $proxy->not([qw(localhost intranet.mojolicio.us)]);

Domains that don't require a proxy server to be used.

=head1 METHODS

L<Mojo::UserAgent::Proxy> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 detect

  $proxy = $proxy->detect;

Check environment variables HTTP_PROXY, http_proxy, HTTPS_PROXY, https_proxy,
NO_PROXY and no_proxy for proxy information. Automatic proxy detection can be
enabled with the MOJO_PROXY environment variable.

=head2 inject

  $proxy->inject(Mojo::Transaction::HTTP->new);

Inject proxy server information into transaction.

=head2 is_needed

  my $bool = $proxy->is_needed('intranet.example.com');

Check if request for domain would use a proxy server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
