package Mojo::UserAgent::Proxy;
use Mojo::Base -base;

use Mojo::URL;

has [qw(http https not)];

sub detect {
  my $self = shift;
  $self->http($ENV{HTTP_PROXY}   || $ENV{http_proxy});
  $self->https($ENV{HTTPS_PROXY} || $ENV{https_proxy});
  return $self->not([split ',', $ENV{NO_PROXY} || $ENV{no_proxy} || '']);
}

sub is_needed {
  !grep { $_[1] =~ /\Q$_\E$/ } @{$_[0]->not || []};
}

sub prepare {
  my ($self, $tx) = @_;

  $self->detect if $ENV{MOJO_PROXY};
  my $req = $tx->req;
  my $url = $req->url;
  return unless $self->is_needed($url->host);

  # HTTP proxy
  my $proto = $url->protocol;
  my $http  = $self->http;
  $req->proxy(Mojo::URL->new($http)) if $http && $proto eq 'http';

  # HTTPS proxy
  my $https = $self->https;
  $req->proxy(Mojo::URL->new($https)) if $https && $proto eq 'https';
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

  my $http = $proxy->http;
  $proxy   = $proxy->http('socks://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTP and WebSocket requests.

=head2 https

  my $https = $proxy->https;
  $proxy    = $proxy->https('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTPS and WebSocket requests.

=head2 not

  my $not = $proxy->not;
  $proxy  = $proxy->not(['localhost', 'intranet.mojolicious.org']);

Domains that don't require a proxy server to be used.

=head1 METHODS

L<Mojo::UserAgent::Proxy> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 detect

  $proxy = $proxy->detect;

Check environment variables C<HTTP_PROXY>, C<http_proxy>, C<HTTPS_PROXY>,
C<https_proxy>, C<NO_PROXY> and C<no_proxy> for proxy information. Automatic
proxy detection can be enabled with the C<MOJO_PROXY> environment variable.

=head2 is_needed

  my $bool = $proxy->is_needed('intranet.example.com');

Check if request for domain would use a proxy server.

=head2 prepare

  $proxy->prepare(Mojo::Transaction::HTTP->new);

Prepare proxy server information for transaction.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
