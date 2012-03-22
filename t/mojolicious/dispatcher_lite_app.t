use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 21;

# "Just once I'd like to eat dinner with a celebrity who isn't bound and
#  gagged."
use Mojo::Message::Response;
use Mojolicious::Lite;
use Test::Mojo;

# Internal redirect
hook around_dispatch => sub {
  my ($next, $self) = @_;
  $next->();
  if ($self->res->code == 404) {
    $self->req->url->path($self->param('wrap') ? '/wrap/again' : '/');
    delete $self->stash->{$_} for keys %{$self->stash};
    $self->tx->res(Mojo::Message::Response->new);
    $next->();
  }
};

# Wrap whole application
hook around_dispatch => sub {
  my ($next, $self) = @_;
  return $self->render(text => 'Wrapped again!')
    if $self->req->url->path->contains('/wrap/again');
  $next->();
};

# Wrap whole application again
hook around_dispatch => sub {
  my ($next, $self) = @_;
  return $self->render(text => 'Wrapped!')
    if $self->req->url->path->contains('/wrap');
  $next->();
};

# Custom dispatchers /custom
hook before_dispatch => sub {
  my $self = shift;
  $self->render_text($self->param('a'), status => 205)
    if $self->req->url->path->contains('/custom');
};

# Custom dispatcher /custom_too
hook after_static_dispatch => sub {
  my $self = shift;
  $self->render_text('this works too')
    if $self->req->url->path->contains('/custom_too');
};

# GET /
get '/' => sub { shift->render_text('works') };

# GET /custom (never called if custom dispatchers work)
get '/custom' => sub { shift->render_text('does not work') };

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is('works');

# GET /custom
$t->get_ok('/custom?a=works+too')->status_is(205)->content_is('works too');

# GET /custom_too
$t->get_ok('/custom_too')->status_is(200)->content_is('this works too');

# GET /wrap (first wrapper)
$t->get_ok('/wrap')->status_is(200)->content_is('Wrapped!');

# GET /wrap/again (second wrapper)
$t->get_ok('/wrap/again')->status_is(200)->content_is('Wrapped again!');

# GET /not_found (internal redirect to root)
$t->get_ok('/not_found')->status_is(200)->content_is('works');

# GET /not_found (internal redirect to second wrapper)
$t->get_ok('/not_found?wrap=1')->status_is(200)->content_is('Wrapped again!');
