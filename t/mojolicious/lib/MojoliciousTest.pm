package MojoliciousTest;
use Mojo::Base 'Mojolicious';

use MojoliciousTest::Foo;

sub development_mode {
  my $self = shift;

  # Template and static file class with higher precedence for development
  unshift @{$self->static->classes},   'MojoliciousTest::Foo';
  unshift @{$self->renderer->classes}, 'MojoliciousTest::Foo';

  # Static root for development
  unshift @{$self->static->paths}, $self->home->rel_dir('public_dev');
}

# "Let's face it, comedy's a dead art form. Tragedy, now that's funny."
sub startup {
  my $self = shift;

  # Template and static file class with lower precedence for production
  push @{$self->static->classes},   'MojoliciousTest';
  push @{$self->renderer->classes}, 'MojoliciousTest';

  # Plugins in custom namespace
  unshift @{$self->plugins->namespaces}, $self->routes->namespace . '::Plugin';
  $self->plugin('test-some_plugin2');
  $self->plugin('UPPERCASETestPlugin');

  # Templateless renderer
  $self->renderer->add_handler(
    test => sub {
      my ($self, $c, $output) = @_;
      $$output = 'Hello Mojo from a templateless renderer!';
    }
  );

  # Renderer for a different file extension
  $self->renderer->add_handler(xpl => $self->renderer->handlers->{epl});

  # Shortcut for "/fun*" routes
  $self->routes->add_shortcut(
    fun => sub {
      my ($r, $append) = @_;
      $r->route("/fun$append");
    }
  );

  # Session
  $self->sessions->cookie_domain('.example.com');
  $self->sessions->cookie_path('/bar');

  # /plugin/upper_case
  # /plugin/camel_case (plugins loaded correctly)
  my $r = $self->routes;
  $r->route('/plugin/upper_case')->to('foo#plugin_upper_case');
  $r->route('/plugin/camel_case')->to('foo#plugin_camel_case');

  # /exceptional/*
  $r->route('/exceptional/:action')->to('exceptional#');

  # /exceptional_too/*
  $r->bridge('/exceptional_too')->to('exceptional#this_one_might_die')
    ->route('/:action');

  # /fun/time
  $r->fun('/time')->to('foo#fun');

  # /happy/fun/time
  $r->route('/happy')->fun('/time')->to('foo#fun');

  # /auth (authentication bridge)
  my $auth = $r->bridge('/auth')->to(
    cb => sub {
      return 1 if shift->req->headers->header('X-Bender');
      return;
    }
  );

  # /auth/authenticated
  $auth->route('/authenticated')->to('foo#authenticated');

  # /stash_config
  $r->route('/stash_config')
    ->to(controller => 'foo', action => 'config', config => {test => 123});

  # /test4 (named route for url_for)
  $r->route('/test4/:something')->to('foo#something', something => 23)
    ->name('something');

  # /somethingtest (refer to another route with url_for)
  $r->route('/somethingtest')->to('foo#something');

  # /something_missing (refer to a non existing route with url_for)
  $r->route('/something_missing')->to('foo#url_for_missing');

  # /test3 (no class, just a namespace)
  $r->route('/test3')
    ->to(namespace => 'MojoliciousTestController', action => 'index');

  # /test2 (different namespace test)
  $r->route('/test2')->to(
    namespace  => 'MojoliciousTest2',
    controller => 'Foo',
    action     => 'test'
  );

  # /test5 (only namespace test)
  $r->route('/test5')
    ->to(namespace => 'MojoliciousTest2::Foo', action => 'test');

  # /test6 (no namespace test)
  $r->route('/test6')->to(
    namespace  => '',
    controller => 'mojolicious_test2-foo',
    action     => 'test'
  );

  # /withblock (template with blocks)
  $r->route('/withblock')->to('foo#withblock');

  # /staged (authentication with bridges)
  my $b = $r->bridge('/staged')->to(controller => 'foo', action => 'stage1');
  $b->route->to(action => 'stage2');

  # /shortcut/act
  # /shortcut/ctrl
  # /shortcut/ctrl-act (shortcuts to controller#action)
  $r->route('/shortcut/ctrl-act')
    ->to('foo#config', config => {test => 'ctrl-act'});
  $r->route('/shortcut/ctrl')
    ->to('foo#', action => 'config', config => {test => 'ctrl'});
  $r->route('/shortcut/act')
    ->to('#config', controller => 'foo', config => {test => 'act'});

  # /foo/session (session cookie with domain)
  $r->route('/foo/session')->to('foo#session_domain');

  # /rss.xml (mixed formats)
  $r->route('/rss.xml')->to('foo#bar', format => 'rss');

  # /*/* (the default route)
  $r->route('/(controller)/(action)')->to(action => 'index');

  # /just/some/template (embedded template)
  $r->route('/just/some/template')->to(template => 'just/some/template');
}

1;
__DATA__

@@ some/static/file.txt
Production static file with low precedence.

@@ just/some/template.html.ep
Production template with low precedence.
