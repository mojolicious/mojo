#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More tests => 664;

# Pollution
123 =~ m/(\d+)/;

# Wait you're the only friend I have...
# You really want a robot for a friend?
# Yeah ever since I was six.
# Well, ok but I don't want people thinking we're robosexuals,
# so if anyone asks you're my debugger.
use Mojo::Client;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::Cookie::Response;
use Mojo::Date;
use Mojo::JSON;
use Mojo::Transaction::HTTP;
use Mojolicious::Lite;
use Test::Mojo;

# Mojolicious::Lite and ojo
use ojo;

# Header condition plugin
plugin 'header_condition';

# Plugin with a template
use FindBin;
use lib "$FindBin::Bin/lib";
plugin 'PluginWithTemplate';

# Default
app->defaults(default => 23);

# Test helpers
app->helper(test_helper  => sub { shift->param(@_) });
app->helper(test_helper2 => sub { shift->app->controller_class });
app->helper(dead         => sub { die $_[1] || 'works!' });
is app->test_helper('foo'), undef, 'no value yet';
is app->test_helper2, 'Mojolicious::Controller', 'right value';

# Test renderer
app->renderer->add_handler(dead => sub { die 'renderer works!' });

# GET /
get '/' => 'root';

# GET /with-format
get '/with-format' => {format => 'html'} => 'with-format';

# GET /without-format
get '/without-format' => 'without-format';

# /ojo
a '/ojo' => {json => {hello => 'world'}};

# GET /null/0
get '/null/:null' => sub {
    my $self = shift;
    $self->render(text => $self->param('null'), layout => 'layout');
};

# GET /action_template
get '/action_template' => {controller => 'foo'} => sub {
    my $self = shift;
    $self->render(action => 'bar');
    $self->rendered;
};

# GET /dead
get '/dead' => sub {
    my $self = shift;
    $self->dead;
    $self->render(text => 'failed!');
};

# GET /dead_template
get '/dead_template' => 'dead_template';

# GET /dead_renderer
get '/dead_renderer' => sub { shift->render(handler => 'dead') };

# GET /dead_auto_renderer
get '/dead_auto_renderer' => {handler => 'dead'};

# GET /regex/in/template
get '/regex/in/template' => 'test(test)(\Qtest\E)(';

# GET /maybe/ajax
get '/maybe/ajax' => sub {
    my $self = shift;
    return $self->render(text => 'is ajax') if $self->req->is_xhr;
    $self->render(text => 'not ajax');
};

# GET /stream
get '/stream' => sub {
    my $self = shift;
    my $chunks = [qw/foo bar/, $self->req->url->to_abs->userinfo,
        $self->url_for->to_abs];
    $self->res->code(200);
    $self->res->headers->content_type('text/plain');
    my $cb;
    $cb = sub {
        my $self = shift;
        my $chunk = shift @$chunks || '';
        $self->write_chunk($chunk, $chunk ? $cb : undef);
    };
    $cb->($self->res);
    $self->rendered;
};

# GET /finished
my $finished;
get '/finished' => sub {
    my $self = shift;
    $self->on_finish(sub { $finished += 3 });
    $finished = 20;
    $self->render(text => 'so far so good!');
};

# GET /привет/мир
get '/привет/мир' =>
  sub { shift->render(text => 'привет мир') };

# GET /root
get '/root.html' => 'root_path';

# GET /template.txt
get '/template.txt' => 'template';

# GET /0
get ':number' => [number => qr/0/] => sub {
    my $self = shift;
    $self->render_text($self->tx->remote_address . $self->param('number'));
};

# GET /tags
get 'tags/:test' => 'tags';

# GET /selection
get 'selection' => '*';

# GET /inline/epl
get '/inline/epl' => sub { shift->render(inline => '<%= 1 + 1%>') };

# GET /inline/ep
get '/inline/ep' =>
  sub { shift->render(inline => "<%= param 'foo' %>works!", handler => 'ep') };

# GET /inline/ep/too
get '/inline/ep/too' => sub { shift->render(inline => '0', handler => 'ep') };

# GET /inline/ep/partial
get '/inline/ep/partial' => sub {
    my $self = shift;
    $self->stash(inline_template => "<%= 'just' %>");
    $self->render(
        inline  => '<%= include inline => $inline_template %>works!',
        handler => 'ep'
    );
};

# GET /source
get '/source' => sub { shift->render_static('../lite_app.t') };

# GET /foo_relaxed/*
get '/foo_relaxed/(.test)' => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# GET /foo_wildcard/*
get '/foo_wildcard/(*test)' => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# GET /with/header/condition
get '/with/header/condition' => (headers => {'X-Secret-Header' => 'bar'}) =>
  'with_header_condition';

# POST /with/header/condition
post '/with/header/condition' => (headers => {'X-Secret-Header' => 'bar'}) =>
  sub {
    my $self = shift;
    $self->render_text(
        'foo ' . $self->req->headers->header('X-Secret-Header'));
  };

# POST /with/body/and/desc
post '/with/body/and/desc' => sub {
    my $self = shift;
    return if $self->req->body ne 'body';
    $self->render_text('bar');
};

# POST /with/body/and/headers/desc
post '/with/body/and/headers/desc' => sub {
    my $self = shift;
    return
      if $self->req->headers->header('with') ne 'header'
          || $self->req->body ne 'body';
    $self->render_text('bar');
};

# GET /template_inheritance
get '/template_inheritance' => sub { shift->render('template_inheritance') };

# GET /layout_without_inheritance
get '/layout_without_inheritance' => sub {
    shift->render(
        template => 'layouts/template_inheritance',
        handler  => 'ep'
    );
};

# GET /double_inheritance
get '/double_inheritance' =>
  sub { shift->render(template => 'double_inheritance') };

# GET /nested-includes
get '/nested-includes' => sub {
    my $self = shift;
    $self->render(
        template => 'nested-includes',
        layout   => 'layout',
        handler  => 'ep'
    );
};

# GET /outerlayout
get '/outerlayout' => sub {
    my $self = shift;
    $self->render(
        template => 'outerlayout',
        layout   => 'layout',
        handler  => 'ep'
    );
};

# GET /outerlayouttwo
get '/outerlayouttwo' => {layout => 'layout'} => sub {
    my $self = shift;
    is($self->stash->{layout}, 'layout', 'right value');
    $self->render(handler => 'ep');
    is($self->stash->{layout}, 'layout', 'right value');
} => 'outerlayout';

# GET /outerinnerlayout
get '/outerinnerlayout' => sub {
    my $self = shift;
    $self->render(
        template => 'outerinnerlayout',
        layout   => 'layout',
        handler  => 'ep'
    );
};

# GET /withblocklayout
get '/withblocklayout' => sub {
    my $self = shift;
    $self->render(
        template => 'index',
        layout   => 'with_block',
        handler  => 'epl'
    );
};

# GET /session_cookie
get '/session_cookie' => sub {
    my $self = shift;
    $self->render_text('Cookie set!');
    $self->res->cookies(
        Mojo::Cookie::Response->new(
            path  => '/session_cookie',
            name  => 'session',
            value => '23'
        )
    );
};

# GET /session_cookie/2
get '/session_cookie/2' => sub {
    my $self    = shift;
    my $session = $self->req->cookie('session');
    my $value   = $session ? $session->value : 'missing';
    $self->render_text("Session is $value!");
};

# GET /foo
get '/foo' => sub {
    my $self = shift;
    $self->render_text('Yea baby!');
};

# GET /layout
get '/layout' => sub {
    shift->render_text('Yea baby!', layout => 'layout', handler => 'epl');
};

# POST /template
post '/template' => 'index';

# GET /memorized
get '/memorized' => 'memorized';

# * /something
any '/something' => sub {
    my $self = shift;
    $self->render_text('Just works!');
};

# GET|POST /something/else
any [qw/get post/] => '/something/else' => sub {
    my $self = shift;
    $self->render_text('Yay!');
};

# GET /regex/*
get '/regex/:test' => [test => qr/\d+/] => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# POST /bar/*
post '/bar/:test' => {test => 'default'} => sub {
    my $self = shift;
    $self->render_text($self->stash('test'));
};

# GET /firefox/*
get '/firefox/:stuff' => (agent => qr/Firefox/) => sub {
    my $self = shift;
    $self->render_text($self->url_for('foxy', stuff => 'foo'));
} => 'foxy';

# POST /utf8
post '/utf8' => 'form';

# POST /malformed_UTF-8
post '/malformed_utf8' => sub {
    my $c = shift;
    $c->render_text(b($c->param('foo'))->url_escape->to_string);
};

# GET /json
get '/json' =>
  sub { shift->render_json({foo => [1, -2, 3, 'b☃r']}, layout => 'layout') };

# GET /autostash
get '/autostash' => sub { shift->render(handler => 'ep', foo => 'bar') } =>
  '*';

# GET /app
get '/app' => {layout => 'app'} => '*';

# GET /helper
get '/helper' => sub { shift->render(handler => 'ep') } => 'helper';
app->helper(agent => sub { shift->req->headers->user_agent });

# GET /eperror
get '/eperror' => sub { shift->render(handler => 'ep') } => 'eperror';

# GET /subrequest
get '/subrequest' => sub {
    my $self = shift;
    $self->client->post(
        '/template' => sub {
            my $client = shift;
            $self->render_text($client->tx->success->body);
        }
    )->start;
};

# GET /subrequest_simple
get '/subrequest_simple' => sub {
    shift->render_text(p('/template')->body);
};

# GET /subrequest_sync
get '/subrequest_sync' => sub {
    my $self = shift;
    $self->client->post(
        '/template' => sub {
            my $client = shift;
            $client->post(
                '/template' => sub {
                    my $client = shift;
                    $self->render_text($client->res->body);
                }
            )->start;
        }
    )->start;
};

# Make sure hook runs async
app->hook(after_dispatch => sub { shift->stash->{async} = 'broken!' });

# GET /subrequest_async
my $async;
get '/subrequest_async' => sub {
    my $self = shift;
    $self->client->async->post(
        '/template' => sub {
            my $client = shift;
            $self->render_text($client->res->body . $self->stash->{'async'});
            $async = $self->stash->{async};
        }
    )->start;
    $self->stash->{'async'} = 'success!';
};

# GET /redirect_url
get '/redirect_url' => sub {
    shift->redirect_to('http://127.0.0.1/foo')->render_text('Redirecting!');
};

# GET /redirect_path
get '/redirect_path' => sub {
    shift->redirect_to('/foo/bar?foo=bar')->render_text('Redirecting!');
};

# GET /redirect_named
get '/redirect_named' => sub {
    shift->redirect_to('index', format => 'txt')->render_text('Redirecting!');
};

# GET /redirect_no_render
get '/redirect_no_render' => sub {
    shift->redirect_to('index', format => 'txt');
} => '*';

# GET /static_render
get '/static_render' => sub {
    shift->render_static('hello.txt');
} => '*';

# GET /koi8-r
app->types->type('koi8-r' => 'text/html; charset=koi8-r');
get '/koi8-r' => sub {
    app->renderer->encoding('koi8-r');
    shift->render('encoding', format => 'koi8-r', handler => 'ep');
    app->renderer->encoding(undef);
};

# GET /hello3.txt
get '/hello3.txt' => sub { shift->render_static('hello2.txt') };

# GET /captures/*/*
get '/captures/:foo/:bar' => sub {
    my $self = shift;
    $self->render(text => $self->url_for);
};

# Default condition
app->routes->add_condition(
    default => sub {
        my ($r, $c, $captures, $num) = @_;
        $captures->{test} = "$num works!";
        return 1 if $c->stash->{default} == $num;
        return;
    }
);

# GET /default/condition
get '/default/condition' => (default => 23) => sub {
    my $self    = shift;
    my $default = $self->stash('default');
    my $test    = $self->stash('test');
    $self->render(text => "works $default $test");
};

# Redirect condition
app->routes->add_condition(
    redirect => sub {
        my ($r, $c, $captures, $active) = @_;
        return 1 unless $active;
        $c->redirect_to('index') and return
          unless $c->req->headers->header('X-Condition-Test');
        return 1;
    }
);

# GET /redirect/condition/0
get '/redirect/condition/0' => (redirect => 0) => sub {
    shift->render(text => 'condition works!');
};

# GET /redirect/condition/1
get '/redirect/condition/1' => (redirect => 1) =>
  {text => 'condition works too!'};

under sub {
    my $self = shift;
    return unless $self->req->headers->header('X-Bender');
    $self->res->headers->add('X-Under' => 23);
    $self->res->headers->add('X-Under' => 24);
    return 1;
};

# GET /with_under
get '/with_under' => sub {
    my $self = shift;
    $self->render_text('Unders are cool!');
};

# GET /with_under_too
get '/with_under_too' => sub {
    my $self = shift;
    $self->render_text('Unders are cool too!');
};

under sub {
    my $self = shift;

    # Authenticated
    my $name = $self->param('name') || '';
    return 1 if $name eq 'Bender';

    # Not authenticated
    $self->render('param_auth_denied');
    return;
};

# GET /param_auth
get '/param_auth' => '*';

# GET /param_auth/too
get '/param_auth/too' =>
  sub { shift->render_text('You could be Bender too!') };

under sub {
    my $self = shift;
    $self->stash(_name => 'stash');
    $self->cookie(foo => 'cookie', {expires => (time + 60)});
    $self->signed_cookie(bar => 'signed_cookie', {expires => (time + 120)});
    $self->cookie(bad => 'bad_cookie--12345678');
    return 1;
};

# GET /bridge2stash
get '/bridge2stash' =>
  sub { shift->render(template => 'bridge2stash', handler => 'ep'); };

# Counter
my $under = 0;
under sub {
    shift->res->headers->header('X-Under' => ++$under);
    return 1;
};

# GET /with_under_count
get '/with/under/count' => '*';

# Everything gets past this
under sub {
    shift->res->headers->header('X-Possible' => 1);
    return 1;
};

# GET /possible
get '/possible' => 'possible';

# Nothing gets past this
under sub {
    shift->res->headers->header('X-Impossible' => 1);
    return 0;
};

# GET /impossible
get '/impossible' => 'impossible';

# Prefix
under '/prefix';

# GET
get sub { shift->render(text => 'prefixed GET works!') };

# POST
post sub { shift->render(text => 'prefixed POST works!') };

# GET /prefix/works
get '/works' => sub { shift->render(text => 'prefix works!') };

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $client = app->client;
my $t      = Test::Mojo->new;

# Client timer
my $timer;
$client->ioloop->timer(
    '0.1' => sub {
        my $async = '';
        $client->async->get(
            '/' => sub {
                my $self = shift;
                $timer = $self->res->body . $async;
            }
        )->start;
        $async = 'works!';
    }
);

# GET /
$t->get_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
    "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# HEAD /
$t->head_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 55)->content_is('');

# GET / (with body)
$t->get_ok('/', '1234' x 1024)->status_is(200)
  ->content_is(
    "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# GET /with-format
$t->get_ok('/with-format')->content_is("/without-format\n");

# GET /without-format
$t->get_ok('/without-format')->content_is("/without-format\n");

# GET /without-format.html
$t->get_ok('/without-format.html')->content_is("/without-format\n");

# GET /ojo (ojo)
$t->get_ok('/ojo')->status_is(200)->json_content_is({hello => 'world'});

# GET /static.txt (static inline file)
$t->get_ok('/static.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("Just some\ntext!\n\n");

# GET /static.txt (static inline file, If-Modified-Since)
my $modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static.txt', {'If-Modified-Since' => $modified})->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("Just some\ntext!\n\n");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static.txt', {'If-Modified-Since' => $modified})->status_is(304)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# GET /static.txt (partial inline file)
$t->get_ok('/static.txt', {'Range' => 'bytes=2-5'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 4)
  ->content_is('st s');

# GET /static.txt (base 64 static inline file)
$t->get_ok('/static2.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");

# GET /static.txt (base 64 static inline file, If-Modified-Since)
$modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static2.txt', {'If-Modified-Since' => $modified})->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static2.txt', {'If-Modified-Since' => $modified})->status_is(304)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# GET /static.txt (base 64 partial inline file)
$t->get_ok('/static2.txt', {'Range' => 'bytes=2-5'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 4)
  ->content_is('st 1');

# GET /template.txt.epl (protected inline template)
$t->get_ok('/template.txt.epl')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# GET /null/0
$t->get_ok('/null/0')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/layouted 0/);

# GET /action_template
$t->get_ok('/action_template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("controller and action!\n");

# GET /dead
$t->get_ok('/dead')->status_is(500)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/works!/);

# GET /dead_renderer
$t->get_ok('/dead_renderer')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/renderer works!/);

# GET /dead_auto_renderer
$t->get_ok('/dead_auto_renderer')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/renderer works!/);

# GET /dead_template
$t->get_ok('/dead_template')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/works too!/);

# GET /regex/in/template
$t->get_ok('/regex/in/template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("test(test)(\\Qtest\\E)(\n");

# GET /stream (with basic auth)
my $port = $t->client->test_server;
$t->get_ok("sri:foo\@localhost:$port/stream?foo=bar")->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/^foobarsri\:foohttp:\/\/localhost\:\d+\/stream$/);

# GET /stream (with basic auth and ojo)
my $b = g("http://sri:foo\@localhost:$port/stream?foo=bar")->body;
like $b, qr/^foobarsri\:foohttp:\/\/localhost\:\d+\/stream$/, 'right content';

# GET /maybe/ajax (not ajax)
$t->get_ok('/maybe/ajax')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('not ajax');

# GET /maybe/ajax (is ajax)
$t->get_ok('/maybe/ajax', {'X-Requested-With' => 'XMLHttpRequest'})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('is ajax');

# GET /finished (with on_finish callback)
$t->get_ok('/finished')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('so far so good!');
is $finished, 23, 'finished';

# GET / (IRI)
$t->get_ok('/привет/мир')->status_is(200)
  ->content_type_is('text/html');
is b($t->tx->res->body)->decode('UTF-8'), 'привет мир',
  'right content';

# GET /root
$t->get_ok('/root.html')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("/\n");

# GET /.html
$t->get_ok('/.html')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
    "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# GET /0 (reverse proxy)
my $backup = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$t->get_ok('/0', {'X-Forwarded-For' => '192.168.2.2, 192.168.2.1'})
  ->status_is(200)->content_is('192.168.2.10');
$ENV{MOJO_REVERSE_PROXY} = $backup;

# GET /tags
$t->get_ok('/tags/lala?a=b&b=0&c=2&d=3&escaped=1%22+%222')->status_is(200)
  ->content_is(<<EOF);
<foo />
<foo bar="baz" />
<foo one="two" three="four">Hello</foo>
<a href="/path">Path</a>
<a href="http://example.com/" title="Foo">Foo</a>
<a href="http://example.com/">Example</a>
<a href="/template">Home</a>
<a href="/tags/23" title="Foo">Foo</a>
<form action="/template" method="post">
    <input name="foo" />
</form>
<form action="/tags/24" method="post">
    <input name="foo" />
    <input name="foo" type="checkbox" value="1" />
    <input checked="checked" name="a" type="checkbox" value="2" />
    <input name="b" type="radio" value="1" />
    <input checked="checked" name="b" type="radio" value="0" />
    <input name="c" type="hidden" value="foo" />
    <input name="d" type="file" />
    <textarea cols="40" name="e" rows="50">
        default!
    </textarea>
    <textarea name="f"></textarea>
    <input name="g" type="password" />
    <input id="foo" name="h" type="password" />
    <input type="submit" value="Ok!" />
    <input id="bar" type="submit" value="Ok too!" />
</form>
<form action="/">
    <input name="foo" />
</form>
<input name="escaped" value="1&quot; &quot;2" />
<input name="a" value="b" />
<input name="a" value="b" />
<script src="script.js" type="text/javascript" />
<script type="text/javascript"><![CDATA[
    var a = 'b';
]]></script>
<script type="foo"><![CDATA[
    var a = 'b';
]]></script>
<link href="foo.css" media="screen" rel="stylesheet" type="text/css" />
<style type="text/css"><![CDATA[
    body {color: #000}
]]></style>
<style type="foo"><![CDATA[
    body {color: #000}
]]></style>
EOF

# GET /tags (alternative)
$t->get_ok('/tags/lala?c=b&d=3&e=4&f=5')->status_is(200)->content_is(<<EOF);
<foo />
<foo bar="baz" />
<foo one="two" three="four">Hello</foo>
<a href="/path">Path</a>
<a href="http://example.com/" title="Foo">Foo</a>
<a href="http://example.com/">Example</a>
<a href="/template">Home</a>
<a href="/tags/23" title="Foo">Foo</a>
<form action="/template" method="post">
    <input name="foo" />
</form>
<form action="/tags/24" method="post">
    <input name="foo" />
    <input name="foo" type="checkbox" value="1" />
    <input name="a" type="checkbox" value="2" />
    <input name="b" type="radio" value="1" />
    <input name="b" type="radio" value="0" />
    <input name="c" type="hidden" value="foo" />
    <input name="d" type="file" />
    <textarea cols="40" name="e" rows="50">4</textarea>
    <textarea name="f">5</textarea>
    <input name="g" type="password" />
    <input id="foo" name="h" type="password" />
    <input type="submit" value="Ok!" />
    <input id="bar" type="submit" value="Ok too!" />
</form>
<form action="/">
    <input name="foo" />
</form>
<input name="escaped" />
<input name="a" />
<input name="a" value="c" />
<script src="script.js" type="text/javascript" />
<script type="text/javascript"><![CDATA[
    var a = 'b';
]]></script>
<script type="foo"><![CDATA[
    var a = 'b';
]]></script>
<link href="foo.css" media="screen" rel="stylesheet" type="text/css" />
<style type="text/css"><![CDATA[
    body {color: #000}
]]></style>
<style type="foo"><![CDATA[
    body {color: #000}
]]></style>
EOF

# GET /selection (empty)
$t->get_ok('/selection')->status_is(200)
  ->content_is("<form action=\"/selection\">\n    "
      . '<select name="a">'
      . '<option value="b">b</option>'
      . '<optgroup label="c">'
      . '<option value="d">d</option>'
      . '<option value="e">E</option>'
      . '<option value="f">f</option>'
      . '</optgroup>'
      . '<option value="g">g</option>'
      . '</select>'
      . "\n    "
      . '<select multiple="multiple" name="foo">'
      . '<option value="bar">bar</option>'
      . '<option value="baz">baz</option>'
      . '</select>'
      . "\n    "
      . '<input type="submit" value="Ok" />' . "\n"
      . '</form>'
      . "\n");

# GET /selection (values)
$t->get_ok('/selection?a=e&foo=bar')->status_is(200)
  ->content_is("<form action=\"/selection\">\n    "
      . '<select name="a">'
      . '<option value="b">b</option>'
      . '<optgroup label="c">'
      . '<option value="d">d</option>'
      . '<option selected="selected" value="e">E</option>'
      . '<option value="f">f</option>'
      . '</optgroup>'
      . '<option value="g">g</option>'
      . '</select>'
      . "\n    "
      . '<select multiple="multiple" name="foo">'
      . '<option selected="selected" value="bar">bar</option>'
      . '<option value="baz">baz</option>'
      . '</select>'
      . "\n    "
      . '<input type="submit" value="Ok" />' . "\n"
      . '</form>'
      . "\n");

# GET /selection (multiple values)
$t->get_ok('/selection?foo=bar&a=e&foo=baz')->status_is(200)
  ->content_is("<form action=\"/selection\">\n    "
      . '<select name="a">'
      . '<option value="b">b</option>'
      . '<optgroup label="c">'
      . '<option value="d">d</option>'
      . '<option selected="selected" value="e">E</option>'
      . '<option value="f">f</option>'
      . '</optgroup>'
      . '<option value="g">g</option>'
      . '</select>'
      . "\n    "
      . '<select multiple="multiple" name="foo">'
      . '<option selected="selected" value="bar">bar</option>'
      . '<option selected="selected" value="baz">baz</option>'
      . '</select>'
      . "\n    "
      . '<input type="submit" value="Ok" />' . "\n"
      . '</form>'
      . "\n");

# GET /inline/epl
$t->get_ok('/inline/epl')->status_is(200)->content_is("2\n");

# GET /inline/ep
$t->get_ok('/inline/ep?foo=bar')->status_is(200)->content_is("barworks!\n");

# GET /inline/ep/too
$t->get_ok('/inline/ep/too')->status_is(200)->content_is("0\n");

# GET /inline/ep/partial
$t->get_ok('/inline/ep/partial')->status_is(200)
  ->content_is("just\nworks!\n");

# GET /source
$t->get_ok('/source')->status_is(200)->content_like(qr/get_ok\('\/source/);

# GET / (with body and max message size)
$backup = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1024;
$t->get_ok('/', '1234' x 1024)->status_is(413)
  ->content_is(
    "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup;

# GET /foo_relaxed/123
$t->get_ok('/foo_relaxed/123')->status_is(200)->content_is('123');

# GET /foo_relaxed
$t->get_ok('/foo_relaxed/')->status_is(404);

# GET /foo_wildcard/123
$t->get_ok('/foo_wildcard/123')->status_is(200)->content_is('123');

# GET /foo_wildcard
$t->get_ok('/foo_wildcard/')->status_is(404);

# GET /with/header/condition
$t->get_ok('/with/header/condition', {'X-Secret-Header' => 'bar'})
  ->status_is(200)->content_like(qr/^Test ok/);

# GET /with/header/condition (not found)
$t->get_ok('/with/header/condition')->status_is(404)->content_like(qr/Oops!/);

# POST /with/header/condition
$t->post_ok('/with/header/condition', {'X-Secret-Header' => 'bar'}, 'bar')
  ->status_is(200)->content_is('foo bar');

# POST /with/header/condition (not found)
$t->post_ok('/with/header/condition', {}, 'bar')->status_is(404)
  ->content_like(qr/Oops!/);

# POST /with/body/and/desc
$t->post_ok('/with/body/and/desc', 'body', 'desc')->status_is(200)
  ->content_is('bar');

# POST /with/body/and/headers/and/desc
$t->post_ok('/with/body/and/headers/desc', {with => 'header'}, 'body', 'desc')
  ->status_is(200)->content_is('bar');

# GET /template_inheritance
$t->get_ok('/template_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("<title>Welcome</title>Sidebar!Hello World!\nDefault footer!");

# GET /layout_without_inheritance
$t->get_ok('/layout_without_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Default header!Default sidebar!Default footer!');

# GET /double_inheritance
$t->get_ok('/double_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('<title>Welcome</title>Sidebar too!Default footer!');

# GET /plugin_with_template
$t->get_ok('/plugin_with_template')->status_is(200)
  ->content_is("layout_with_template\nwith template\n\n");

# GET /nested-includes
$t->get_ok('/nested-includes')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Nested Hello\n[\n  1,\n  2\n]\nthere<br/>!\n\n\n\n");

# GET /outerlayout
$t->get_ok('/outerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br/>!\n\n\n");

# GET /outerlayouttwo
$t->get_ok('/outerlayouttwo')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br/>!\n\n\n");

# GET /outerinnerlayout
$t->get_ok('/outerinnerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
    "layouted Hello\nlayouted [\n  1,\n  2\n]\nthere<br/>!\n\n\n\n");

# GET /withblocklayout
$t->get_ok('/withblocklayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("\nwith_block \n\nOne: one\nTwo: two\n\n");

# GET /session_cookie
$t->get_ok('/session_cookie')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Cookie set!');

# GET /session_cookie/2
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Session is 23!');

# GET /session_cookie/2 (retry)
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Session is 23!');

# GET /session_cookie/2 (session reset)
$t->reset_session;
ok !$t->tx, 'session reset';
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Session is missing!');

# GET /foo
$t->get_ok('/foo')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Yea baby!');

# POST /template
$t->post_ok('/template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /memorized
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/\d+a\d+b\d+c\d+d\d+e\d+/);
my $memorized = $t->tx->res->body;

# GET /memorized
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is($memorized);

# GET /memorized
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is($memorized);

# GET /memorized (expired)
sleep 2;
$t->get_ok('/memorized')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/\d+a\d+b\d+c\d+d\d+e\d+/);
isnt($memorized, $t->tx->res->body, 'memorized blocks expired');

# GET /something
$t->get_ok('/something')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# POST /something
$t->post_ok('/something')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# DELETE /something
$t->delete_ok('/something')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /something/else
$t->get_ok('/something/else')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Yay!');

# POST /something/else
$t->post_ok('/something/else')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Yay!');

# DELETE /something/else
$t->delete_ok('/something/else')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# GET /regex/23
$t->get_ok('/regex/23')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('23');

# GET /regex/foo
$t->get_ok('/regex/foo')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# POST /bar
$t->post_ok('/bar')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('default');

# POST /bar/baz
$t->post_ok('/bar/baz')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('baz');

# GET /layout
$t->get_ok('/layout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Yea baby! with layout\n");

# GET /firefox
$t->get_ok('/firefox/bar', {'User-Agent' => 'Firefox'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/firefox/foo');

# GET /firefox
$t->get_ok('/firefox/bar', {'User-Agent' => 'Explorer'})->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# POST /utf8
$t->post_form_ok('/utf8', 'UTF-8' => {name => 'Вячеслав'})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 40)->content_type_is('text/html')
  ->content_is(b("Вячеслав Тихановский\n")->encode('UTF-8')
      ->to_string);

# POST /utf8 (multipart/form-data)
$t->post_form_ok(
    '/utf8',
    'UTF-8' => {name => 'Вячеслав'},
    {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 40)->content_type_is('text/html')
  ->content_is(b("Вячеслав Тихановский\n")->encode('UTF-8')
      ->to_string);

# POST /malformed_utf8
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/malformed_utf8');
$tx->req->headers->content_type('application/x-www-form-urlencoded');
$tx->req->body('foo=%E1');
my ($code, $server, $powered, $body);
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        $code    = $tx->res->code;
        $server  = $tx->res->headers->server;
        $powered = $tx->res->headers->header('X-Powered-By');
        $body    = $tx->res->body;
    }
)->start;
is $code,    200,                  'right status';
is $server,  'Mojolicious (Perl)', 'right "Server" value';
is $powered, 'Mojolicious (Perl)', 'right "X-Powered-By" value';
is $body,    '%E1',                'right content';

# GET /json
$t->get_ok('/json')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('application/json')
  ->json_content_is({foo => [1, -2, 3, 'b☃r']});

# GET /autostash
$t->get_ok('/autostash?bar=23')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted bar\n23\n42\nautostash\n\n");

# GET /app
$t->get_ok('/app')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("app layout app23\ndevelopment\n");

# GET /helper
$t->get_ok('/helper')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("23\n<br/>\n&lt;...\n/template\n(Mojolicious (Perl))");

# GET /helper
$t->get_ok('/helper', {'User-Agent' => 'Explorer'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("23\n<br/>\n&lt;...\n/template\n(Explorer)");

# GET /eperror
$t->get_ok('/eperror')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_like(qr/\$c/);

# GET /subrequest
$t->get_ok('/subrequest')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_simple
$t->get_ok('/subrequest_simple')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_sync
$t->get_ok('/subrequest_sync')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_async
$t->get_ok('/subrequest_async')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!success!');
is $async, 'broken!', 'right text';

# GET /redirect_url
$t->get_ok('/redirect_url')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_is(Location => 'http://127.0.0.1/foo')->content_is('Redirecting!');

# GET /redirect_path
$t->get_ok('/redirect_path')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_like(Location => qr/\/foo\/bar\?foo=bar$/)
  ->content_is('Redirecting!');

# GET /redirect_named
$t->get_ok('/redirect_named')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_like(Location => qr/\/template.txt$/)->content_is('Redirecting!');

# GET /redirect_no_render
$t->get_ok('/redirect_no_render')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 0)
  ->header_like(Location => qr/\/template.txt$/)->content_is('');

# GET /static_render
$t->get_ok('/static_render')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 30)
  ->content_is('Hello Mojo from a static file!');

# GET /redirect_named (with redirecting enabled in client)
$t->max_redirects(3);
$t->get_ok('/redirect_named')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => undef)->element_exists('#foo')
  ->text_is('div' => 'Redirect works!')
  ->text_like('[id="foo"]' => qr/^Redirect/);
$t->max_redirects(0);
Test::Mojo->new(tx => $t->tx->previous)->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_like(Location => qr/\/template.txt$/)->content_is('Redirecting!');

# GET /koi8-r
my $koi8 =
    'Этот человек наполняет меня надеждой.'
  . ' Ну, и некоторыми другими глубокими и приводящими в'
  . ' замешательство эмоциями.';
$t->get_ok('/koi8-r')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/html; charset=koi8-r')->content_like(qr/^$koi8/);

# GET /with_under
$t->get_ok('/with_under', {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Under' => '23, 24')->header_like('X-Under' => qr/23, 24/)
  ->content_is('Unders are cool!');

# GET /with_under_too
$t->get_ok('/with_under_too', {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Under' => '23, 24')->header_like('X-Under' => qr/23, 24/)
  ->content_is('Unders are cool too!');

# GET /with_under_too
$t->get_ok('/with_under_too')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/Oops!/);

# GET /param_auth
$t->get_ok('/param_auth')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Not Bender!\n");

# GET /param_auth?name=Bender
$t->get_ok('/param_auth?name=Bender')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Bender!\n");

# GET /param_auth/too
$t->get_ok('/param_auth/too')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Not Bender!\n");

# GET /param_auth/too?name=Bender
$t->get_ok('/param_auth/too?name=Bender')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('You could be Bender too!');

# GET /hello.txt (static file)
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 30)
  ->content_is('Hello Mojo from a static file!');

# GET /hello.txt (partial static file)
$t->get_ok('/hello.txt', {'Range' => 'bytes=2-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 7)
  ->content_is('llo Moj');

# GET /hello.txt (partial static file, starting at first byte)
$t->get_ok('/hello.txt', {'Range' => 'bytes=0-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 9)
  ->content_is('Hello Moj');

# GET /hello.txt (partial static file, first byte)
$t->get_ok('/hello.txt', {'Range' => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('H');

# GET /hello3.txt (render_static and single byte file)
$t->get_ok('/hello3.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('X');

# GET /hello3.txt (render_static and partial single byte file)
$t->get_ok('/hello3.txt', {'Range' => 'bytes=0-0'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 1)
  ->content_is('X');

# GET /default/condition
$t->get_ok('/default/condition')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('works 23 23 works!');

# GET /redirect/condition/0
$t->get_ok('/redirect/condition/0')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('condition works!');

# GET /redirect/condition/1
$t->get_ok('/redirect/condition/1')->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_like('Location' => qr/\/template$/)->content_is('');

# GET /redirect/condition/1 (with condition header)
$t->get_ok('/redirect/condition/1' => {'X-Condition-Test' => 1})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('condition works too!');

# GET /bridge2stash
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!!\n");

# GET /bridge2stash (with cookies, session and flash)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
    "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!/!\n"
  );

# GET /bridge2stash (with cookies and session but no flash)
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
    "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!/!\n");

# GET /bridge2stash (with cookies and session cleared)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is("stash too!cookie!signed_cookie!!bad_cookie--12345678!!!!\n");

# GET /with/under/count
$t->get_ok('/with/under/count', {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Under'      => 1)->content_is("counter\n");

# GET /possible
$t->get_ok('/possible')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Possible'   => 1)->header_is('X-Impossible' => undef)
  ->content_is("Possible!\n");

# GET /impossible
$t->get_ok('/impossible')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Possible'   => undef)->header_is('X-Impossible' => 1)
  ->content_is("Oops!\n");

# GET /prefix
$t->get_ok('/prefix')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('prefixed GET works!');

# POST /prefix
$t->post_ok('/prefix')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('prefixed POST works!');

# GET /prefix/works
$t->get_ok('/prefix/works')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('prefix works!');

# GET /captures/foo/bar
$t->get_ok('/captures/foo/bar')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/captures/foo/bar');

# GET /captures/bar/baz
$t->get_ok('/captures/bar/baz')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/captures/bar/baz');

# GET /captures/♥/☃
$t->get_ok('/captures/♥/☃')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/captures/%E2%99%A5/%E2%98%83');
is b($t->tx->res->body)->url_unescape->decode('UTF-8'),
  '/captures/♥/☃', 'right result';

# Client timer
$client->ioloop->one_tick('0.1');
is $timer,
  "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\nworks!",
  'right content';

__DATA__
@@ with-format.html.ep
<%= url_for 'without-format' %>

@@ without-format.html.ep
<%= url_for 'without-format' %>

@@ foo/bar.html.ep
controller and action!

@@ dead_template.html.ep
<%= dead 'works too!' %>

@@ tags.html.ep
<%= tag 'foo' %>
<%= tag 'foo', bar => 'baz' %>
<%= tag 'foo', one => 'two', three => 'four' => begin %>Hello<% end %>
<%= link_to Path => '/path' %>
<%= link_to 'http://example.com/', title => 'Foo', sub { 'Foo' } %>
<%= link_to 'http://example.com/' => begin %>Example<% end %>
<%= link_to Home => 'index' %>
<%= link_to Foo => 'tags', {test => 23}, title => 'Foo' %>
<%= form_for 'index', method => 'post' => begin %>
    <%= input_tag 'foo' %>
<% end %>
%= form_for 'tags', {test => 24}, method => 'post' => begin
    %= text_field 'foo'
    %= check_box foo => 1
    %= check_box a => 2
    %= radio_button b => '1'
    %= radio_button b => '0'
    %= hidden_field c => 'foo'
    %= file_field 'd'
    %= text_area e => (cols => 40, rows => 50) => begin
        default!
    %= end
    %= text_area 'f'
    %= password_field 'g'
    %= password_field 'h', id => 'foo'
    %= submit_button 'Ok!'
    %= submit_button 'Ok too!', id => 'bar'
%= end
<%= form_for '/' => begin %>
    <%= input_tag 'foo' %>
<% end %>
<%= input_tag 'escaped' %>
<%= input_tag 'a' %>
<%= input_tag 'a', value => 'c' %>
<%= javascript 'script.js' %>
<%= javascript begin %>
    var a = 'b';
<% end %>
<%= javascript type => 'foo' => begin %>
    var a = 'b';
<% end %>
<%= stylesheet 'foo.css' %>
<%= stylesheet begin %>
    body {color: #000}
<% end %>
<%= stylesheet type => 'foo' => begin %>
    body {color: #000}
<% end %>

@@ selection.html.ep
%= form_for selection => begin
    %= select_field a => ['b', [c => ['d', [ E => 'e'], 'f']], 'g']
    %= select_field foo => [qw/bar baz/], multiple => 'multiple'
    %= submit_button
%= end

@@ static.txt
Just some
text!

@@ template.txt.epl
<div id="foo">Redirect works!</div>

@@ memorized.html.ep
<%= memorize begin =%>
<%= time =%>
<% end =%>
<%= memorize begin =%>
    <%= 'a' . int(rand(999)) =%>
<% end =%><%= memorize begin =%>
<%= 'b' . int(rand(999)) =%>
<% end =%>
<%= memorize test => begin =%>
<%= 'c' . time . int(rand(999)) =%>
<% end =%>
<%= memorize expiry => {expires => time + 1} => begin %>
<%= 'd' . time . int(rand(999)) =%>
<% end =%>
<%= memorize {expires => time + 1} => begin %>
<%= 'e' . time . int(rand(999)) =%>
<% end =%>

@@ test(test)(\Qtest\E)(.html.ep
<%= $self->match->endpoint->name %>

@@ static2.txt (base64)
dGVzdCAxMjMKbGFsYWxh

@@ with_header_condition.html.epl
Test ok

@@ template_inheritance.html.ep
% layout 'template_inheritance';
<% content header => begin =%>
<%= b('<title>Welcome</title>') %>
<% end =%>
<% content sidebar => begin =%>
Sidebar!
<% end =%>
Hello World!

@@ layouts/template_inheritance.html.ep
% stash foo => 'Default';
<%= content header => begin =%>
Default header!
<% end =%>
<%= content sidebar => begin =%>
<%= stash 'foo' %> sidebar!
<% end =%>
%= content
<%= content footer => begin =%>
Default footer!
<% end =%>

@@ double_inheritance.html.ep
% extends 'template_inheritance';
<% content sidebar => begin =%>
Sidebar too!
<% end =%>

@@ layouts/plugin_with_template.html.ep
layout_with_template
<%= content %>

@@ nested-includes.html.ep
Nested <%= include 'outerlayout' %>

@@ param_auth.html.epl
Bender!

@@ param_auth_denied.html.epl
Not Bender!

@@ root.html.epl
% my $self = shift;
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')

@@ root_path.html.epl
%== shift->url_for('root');

@@ outerlayout.html.ep
Hello
<%= include 'outermenu' %>

@@ outermenu.html.ep
% stash test => 'there';
<%= dumper [1, 2] %><%= stash 'test' %><br/>!

@@ outerinnerlayout.html.ep
Hello
<%= include 'outermenu', layout => 'layout' %>

@@ not_found.html.epl
Oops!

@@ index.html.epl
Just works!\

@@ form.html.epl
<%= shift->param('name') %> Тихановский

@@ layouts/layout.html.epl
<%= shift->render_inner %> with layout

@@ autostash.html.ep
% $self->layout('layout');
%= $foo
%= $self->test_helper('bar')
% my $foo = 42;
%= $foo
%= $self->match->endpoint->name;

@@ layouts/layout.html.ep
layouted <%== content %>

@@ layouts/with_block.html.epl
<% my $block = begin %>
<% my ($one, $two) = @_; %>
One: <%= $one %>
Two: <%= $two %>
<% end %>
with_block <%= $block->('one', 'two') %>

@@ layouts/app23.html.ep
app layout <%= content %><%= app->mode %>

@@ app.html.ep
<% layout layout . 23; %><%= layout %>

@@ helper.html.ep
%= $default
%== '<br/>'
%= '<...'
%= url_for 'index'
(<%= agent %>)\

@@ eperror.html.ep
%= $c->foo('bar');

@@ bridge2stash.html.ep
% my $cookie = $self->req->cookie('mojolicious');
<%= stash('_name') %> too!<%= $self->cookie('foo') %>!\
<%= $self->signed_cookie('bar')%>!<%= $self->signed_cookie('bad')%>!\
<%= $self->cookie('bad') %>!<%= session 'foo' %>!\
<%= flash 'foo' %>!<%= $cookie->path if $cookie %>!
% $self->session(foo => 'session');
% my $headers = $self->req->headers;
% $self->flash(foo => 'flash') if $headers->header('X-Flash');
% $self->session(expires => 1) if $headers->header('X-Flash2');

@@ withundercount.html.ep
counter

@@ possible.html.ep
Possible!

@@ impossible.html.ep
Impossible

__END__
This is not a template!
lalala
test
