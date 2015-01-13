package MojoliciousTest;
use Mojo::Base 'Mojolicious';

use MojoliciousTest::Foo;

sub startup {
  my $self = shift;

  if ($self->mode eq 'development') {

    # Template and static file class with higher precedence for development
    unshift @{$self->static->classes},   'MojoliciousTest::Foo';
    unshift @{$self->renderer->classes}, 'MojoliciousTest::Foo';

    # Static root for development
    unshift @{$self->static->paths}, $self->home->rel_dir('public_dev');

    # Development namespace
    unshift @{$self->routes->namespaces}, 'MojoliciousTest3';
  }

  # Template and static file class with lower precedence for production
  push @{$self->static->classes},   'MojoliciousTest';
  push @{$self->renderer->classes}, 'MojoliciousTest';

  # Application specific commands
  push @{$self->commands->namespaces}, 'MojoliciousTest::Command';

  # Plugins in custom namespace
  unshift @{$self->plugins->namespaces},
    $self->routes->namespaces->[-1] . '::Plugin';
  $self->plugin('test-some_plugin2');
  $self->plugin('UPPERCASETestPlugin');

  # Plugin for rendering return values
  $self->plugin('AroundPlugin');

  # Templateless renderer
  $self->renderer->add_handler(
    test => sub {
      my ($renderer, $c, $output) = @_;
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
  $r->route('/exceptional_too')->inline(1)
    ->to('exceptional#this_one_might_die')->route('/:action');

  # /fun/time
  $r->fun('/time')->to('foo#fun');

  # /happy/fun/time
  $r->route('/happy')->fun('/time')->to('foo#fun');

  # /stash_config
  $r->route('/stash_config')
    ->to(controller => 'foo', action => 'config', config => {test => 123});

  # /test4 (named route for url_for)
  $r->route('/test4/:something')->to('foo#something', something => 23)
    ->name('something');

  # /somethingtest (refer to another route with url_for)
  $r->route('/somethingtest')->to('foo#something');

  # /something_missing (refer to a non-existing route with url_for)
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

  # /test7 (controller class shortcut)
  $r->route('/test7')->to('Foo::Bar#test');

  # /test8 (controller class)
  $r->route('/test8')->to(controller => 'Foo::Bar', action => 'test');

  # /test9 (controller in development namespace)
  $r->route('/test9')->to('bar#index');

  # /test10 (controller in both namespaces)
  $r->route('/test10')->to('baz#index');

  # /withblock (template with blocks)
  $r->route('/withblock')->to('foo#withBlock');

  # /staged (authentication with intermediate destination)
  my $b = $r->route('/staged')->inline(1)->to('foo#stage1', return => 1);
  $b->route->to(action => 'stage2');

  # /suspended (suspended intermediate destination)
  $r->route('/suspended')->inline(1)->to('foo#suspended')->route->inline(1)
    ->to('foo#suspended')->route->to('foo#fun');

  # /longpoll (long polling)
  $r->route('/longpoll')->to('foo#longpoll');

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
