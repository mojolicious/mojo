package MojoliciousTest;

use strict;
use warnings;

use base 'Mojolicious';

sub development_mode {
    my $self = shift;

    # Static root for development
    $self->static->root($self->home->rel_dir('public_dev'));
}

# Let's face it, comedy's a dead art form. Tragedy, now that's funny.
sub startup {
    my $self = shift;

    # Plugin
    unshift @{$self->plugins->namespaces},
      $self->routes->namespace . '::Plugin';
    $self->plugin('test_plugin');

    # Templateless renderer
    $self->renderer->add_handler(
        test => sub {
            my ($self, $c, $output) = @_;
            $$output = 'Hello Mojo from a templateless renderer!';
        }
    );

    # Renderer for a different file extension
    $self->renderer->add_handler(xpl => $self->renderer->handler->{epl});

    # Session domain
    $self->session->cookie_domain('.example.com');

    # Routes
    my $r = $self->routes;

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

    # /test4 - named route for url_for
    $r->route('/test4/:something')->to('foo#something', something => 23)
      ->name('something');

    # /somethingtest - refer to another route with url_for
    $r->route('/somethingtest')->to('foo#something');

    # /something_missing - refer to a non existing route with url_for
    $r->route('/something_missing')->to('foo#url_for_missing');

    # /test3 - no class, just a namespace
    $r->route('/test3')
      ->to(namespace => 'MojoliciousTestController', method => 'index');

    # /test2 - different namespace test
    $r->route('/test2')->to(
        namespace => 'MojoliciousTest2',
        class     => 'Foo',
        method    => 'test'
    );

    # /test5 - only namespace test
    $r->route('/test5')->to(
        namespace => 'MojoliciousTest2::Foo',
        method    => 'test'
    );

    # /test6 - no namespace test
    $r->route('/test6')->to(
        namespace  => '',
        controller => 'mojolicious_test2-foo',
        action     => 'test'
    );

    # /withblock - template with blocks
    $r->route('/withblock')->to('foo#withblock');

    # /staged - authentication with bridges
    my $b =
      $r->bridge('/staged')->to(controller => 'foo', action => 'stage1');
    $b->route->to(action => 'stage2');

    # /shortcut/act
    # /shortcut/ctrl
    # /shortcut/ctrl-act - shortcuts to controller#action
    $r->route('/shortcut/ctrl-act')
      ->to('foo#config', config => {test => 'ctrl-act'});
    $r->route('/shortcut/ctrl')
      ->to('foo#', action => 'config', config => {test => 'ctrl'});
    $r->route('/shortcut/act')
      ->to('#config', controller => 'foo', config => {test => 'act'});

    # /foo/session - session cookie with domain
    $r->route('/foo/session')->to('foo#session_domain');

    # /rss.xml - mixed formats
    $r->route('/rss.xml')->to('foo#bar', format => 'rss');

    # /*/* - the default route
    $r->route('/(controller)/(action)')->to(action => 'index');
}

1;
