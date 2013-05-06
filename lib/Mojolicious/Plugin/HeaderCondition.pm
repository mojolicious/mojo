package Mojolicious::Plugin::HeaderCondition;
use Mojo::Base 'Mojolicious::Plugin';

sub register {
  my ($self, $app) = @_;

  $app->routes->add_condition(headers => \&_headers);
  $app->routes->add_condition(
    agent => sub { _headers(@_[0 .. 2], {'User-Agent' => $_[3]}) });
  $app->routes->add_condition(
    host => sub { _check($_[1]->req->url->to_abs->host, $_[3]) });
}

sub _check {
  my ($value, $pattern) = @_;
  return 1
    if $value && $pattern && ref $pattern eq 'Regexp' && $value =~ $pattern;
  return $value && defined $pattern && $pattern eq $value ? 1 : undef;
}

sub _headers {
  my ($route, $c, $captures, $patterns) = @_;
  return undef unless $patterns && ref $patterns eq 'HASH' && keys %$patterns;

  # All headers need to match
  my $headers = $c->req->headers;
  while (my ($name, $pattern) = each %$patterns) {
    return undef unless _check(scalar $headers->header($name), $pattern);
  }
  return 1;
}

1;

=head1 NAME

Mojolicious::Plugin::HeaderCondition - Header condition plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('HeaderCondition');
  $self->routes->get('/:controller/:action')
    ->over(headers => {Referer => qr/example\.com/});

  # Mojolicious::Lite
  plugin 'HeaderCondition';
  get '/' => (headers => {Referer => qr/example\.com/}) => sub {...};

  # All headers need to match
  $self->routes->get('/:controller/:action')->over(headers => {
    'X-Secret-Header' => 'Foo',
    Referer => qr/example\.com/
  });

  # The "agent" condition is a shortcut for the "User-Agent" header
  get '/' => (agent => qr/Firefox/) => sub {...};

  # The "host" condition is a shortcut for the detected host
  get '/' => (host => qr/mojolicio\.us/) => sub {...};

=head1 DESCRIPTION

L<Mojolicious::Plugin::HeaderCondition> is a route condition for header based
routes.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

=head1 METHODS

L<Mojolicious::Plugin::HeaderCondition> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register conditions in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
