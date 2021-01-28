use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::File qw(curfile);
use Mojolicious::Lite;
use Test::Mojo;

# Custom secret
app->secrets(['very secr3t!']);

# Mount full external application a few times
my $external = curfile->sibling('external', 'script', 'my_app');
plugin Mount => {'/x/1' => $external};
plugin(Mount => ('/x/♥' => $external));
plugin Mount => {'MOJOLICIOUS.ORG/' => $external};
plugin(Mount => ('*.foo-bar.de/♥/123' => $external));

# Make sure session can be modified from both apps
hook before_routes => sub {
  my $c = shift;
  return unless $c->req->url->path->contains('/x/1/secondary');
  $c->session->{secondary} += 10;
};

get '/hello' => 'works';

get '/primary' => sub {
  my $c = shift;
  $c->render(text => ++$c->session->{primary});
};

my $t = Test::Mojo->new;

subtest 'Normal request' => sub {
  $t->get_ok('/hello')->status_is(200)->content_is("Hello from the main app!\n");
};

subtest 'Session' => sub {
  $t->get_ok('/primary')->status_is(200)->content_is(1);
  $t->get_ok('/primary')->status_is(200)->content_is(2);
};

subtest 'Session in external app' => sub {
  $t->get_ok('/x/1/secondary')->status_is(200)->content_is(11);
};

subtest 'Session again' => sub {
  $t->get_ok('/primary')->status_is(200)->content_is(3);
};

subtest 'Session in external app again' => sub {
  $t->get_ok('/x/1/secondary')->status_is(200)->content_is(22);
};

subtest 'External app' => sub {
  $t->get_ok('/x/1')->status_is(200)->content_is('too%21');
};

subtest 'Static file from external app' => sub {
  $t->get_ok('/x/1/index.html')->status_is(200)->content_is("External static file!\n");
};

subtest 'External app with different prefix' => sub {
  $t->get_ok('/x/1/test')->status_is(200)->content_is('works%21');
};

subtest 'External app with Unicode prefix' => sub {
  $t->get_ok('/x/♥')->status_is(200)->content_is('too%21');
};

subtest 'Static file from external app with Unicode prefix' => sub {
  $t->get_ok('/x/♥/index.html')->status_is(200)->content_is("External static file!\n");
};

subtest 'External app with Unicode prefix again' => sub {
  $t->get_ok('/x/♥/test')->status_is(200)->content_is('works%21');
};

subtest 'External app with domain' => sub {
  $t->get_ok('/' => {Host => 'mojolicious.org'})->status_is(200)->content_is('too%21');
};

subtest 'Static file from external app with domain' => sub {
  $t->get_ok('/index.html' => {Host => 'mojolicious.org'})->status_is(200)->content_is("External static file!\n");
};

subtest 'External app with domain again' => sub {
  $t->get_ok('/test' => {Host => 'mojolicious.org'})->status_is(200)->content_is('works%21');
};

subtest 'External app with a bit of everything' => sub {
  $t->get_ok('/♥/123/' => {Host => 'test.foo-bar.de'})->status_is(200)->content_is('too%21');
};

subtest 'Static file from external app with a bit of everything' => sub {
  $t->get_ok('/♥/123/index.html' => {Host => 'test.foo-bar.de'})->status_is(200)->content_is("External static file!\n");
};

subtest 'External app with a bit of everything again' => sub {
  $t->get_ok('/♥/123/test' => {Host => 'test.foo-bar.de'})->status_is(200)->content_is('works%21');
};

done_testing();

__DATA__

@@ works.html.ep
Hello from the main app!
