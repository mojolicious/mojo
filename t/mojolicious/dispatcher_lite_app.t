use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
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

# Custom dispatcher /hello.txt
hook before_dispatch => sub {
  my $self = shift;
  $self->render_text('Custom static file works!')
    if $self->req->url->path->contains('/hello.txt');
};

# Custom dispatcher /custom
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

# Cleared response for /res.txt
hook after_static_dispatch => sub {
  my $self = shift;
  return
    unless $self->req->url->path->contains('/res.txt')
    && $self->param('route');
  $self->tx->res(Mojo::Message::Response->new);
};

# Response generating condition "res" for /res.txt
app->routes->add_condition(
  res => sub {
    my ($route, $c) = @_;
    return 1 unless $c->param('res');
    $c->tx->res(
      Mojo::Message::Response->new(code => 201)->body('Conditional response!')
    );
    $c->rendered and return undef;
  }
);

# GET /
get '/' => sub { shift->render_text('works') };

# GET /custom (never called if custom dispatchers work)
get '/custom' => sub { shift->render_text('does not work') };

# GET /res.txt (custom response)
get '/res.txt' => (res => 1) => sub {
  my $self = shift;
  my $res
    = Mojo::Message::Response->new(code => 202)->body('Custom response!');
  $self->tx->res($res);
  $self->rendered;
};

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is('works');

# GET /hello.txt (override static file)
$t->get_ok('/hello.txt')->status_is(200)
  ->content_is('Custom static file works!');

# GET /custom
$t->get_ok('/custom?a=works+too')->status_is(205)->content_is('works too');

# GET /res.txt (static file)
$t->get_ok('/res.txt')->status_is(200)->content_is("Static response!\n");

# GET /res.txt?route=1 (custom response)
$t->get_ok('/res.txt?route=1')->status_is(202)->content_is('Custom response!');

# GET /res.txt?route=1&res=1 (conditional response)
$t->get_ok('/res.txt?route=1&res=1')->status_is(201)
  ->content_is('Conditional response!');

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

done_testing();

__DATA__
@@ res.txt
Static response!
