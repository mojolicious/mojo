package Mojolicious::Plugin::HeaderCondition;
use Mojo::Base 'Mojolicious::Plugin';

use re qw(is_regexp);

sub register {
  my ($self, $app) = @_;

  $app->routes->add_condition(headers => \&_headers);
  $app->routes->add_condition(agent   => sub { _headers(@_[0 .. 2], {'User-Agent' => $_[3]}) });
  $app->routes->add_condition(host    => sub { _check($_[1]->req->url->to_abs->host, $_[3]) });
}

sub _check {
  my ($value, $pattern) = @_;
  return 1 if $value && $pattern && is_regexp($pattern) && $value =~ $pattern;
  return $value && defined $pattern && $pattern eq $value;
}

sub _headers {
  my ($route, $c, $captures, $patterns) = @_;
  return undef unless $patterns && ref $patterns eq 'HASH' && keys %$patterns;

  # All headers need to match
  my $headers = $c->req->headers;
  _check($headers->header($_), $patterns->{$_}) || return undef for keys %$patterns;
  return 1;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::HeaderCondition - Header condition plugin

=head1 SYNOPSIS

  # Mojolicious
  $app->plugin('HeaderCondition');
  $app->routes->get('/:controller/:action')
    ->over(headers => {Referer => qr/example\.com/});

  # Mojolicious::Lite
  plugin 'HeaderCondition';
  get '/' => (headers => {Referer => qr/example\.com/}) => sub {...};

  # All headers need to match
  $app->routes->get('/:controller/:action')->over(headers => {
    'X-Secret-Header' => 'Foo',
    Referer => qr/example\.com/
  });

  # The "agent" condition is a shortcut for the "User-Agent" header
  get '/' => (agent => qr/Firefox/) => sub {...};

  # The "host" condition is a shortcut for the detected host
  get '/' => (host => qr/mojolicious\.org/) => sub {...};

=head1 DESCRIPTION

L<Mojolicious::Plugin::HeaderCondition> is a route condition for header-based routes.

This is a core plugin, that means it is always enabled and its code a good example for learning to build new plugins,
you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available by default.

=head1 METHODS

L<Mojolicious::Plugin::HeaderCondition> inherits all methods from L<Mojolicious::Plugin> and implements the following
new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register conditions in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
