#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

# Disable IPv6, epoll and kqueue
BEGIN {
  $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1;
  $ENV{MOJO_MODE} = 'development';
}

use Test::More tests => 823;

# Pollution
123 =~ m/(\d+)/;

# "Wait you're the only friend I have...
#  You really want a robot for a friend?
#  Yeah ever since I was six.
#  Well, ok but I don't want people thinking we're robosexuals,
#  so if anyone asks you're my debugger."
use Mojo::ByteStream 'b';
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::Cookie::Response;
use Mojo::Date;
use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojolicious::Lite;
use Test::Mojo;

# User agent
my $ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton, app => app);

# Missing plugin
eval { plugin 'does_not_exist'; };
is $@, "Plugin \"does_not_exist\" missing, maybe you need to install it?\n",
  'right error';

# Plugin with a template
use FindBin;
use lib "$FindBin::Bin/lib";
plugin 'PluginWithTemplate';

# Default
app->defaults(default => 23);

# Test helpers
helper test_helper  => sub { shift->param(@_) };
helper test_helper2 => sub { shift->app->controller_class };
helper dead         => sub { die $_[1] || 'works!' };
is app->test_helper('foo'), undef, 'no value yet';
is app->test_helper2, 'Mojolicious::Controller', 'right value';

# Test renderer
app->renderer->add_handler(dead => sub { die 'renderer works!' });

# GET /☃
get '/☃' => sub {
  my $self = shift;
  $self->render_text($self->url_for);
};

# GET /unicode/a%E4b
get '/unicode/aäb' => sub {
  my $self = shift;
  $self->render(text => $self->url_for);
};

# GET /unicode/*
get '/unicode/:stuff' => sub {
  my $self = shift;
  $self->render(text => $self->param('stuff') . $self->url_for);
};

# GET /conditional
get '/conditional' => (
  cb => sub {
    my ($r, $c, $captures) = @_;
    $captures->{condition} = $c->req->headers->header('X-Condition');
    return unless $captures->{condition};
    1;
  }
) => {inline => '<%= $condition %>'};

# GET /
get '/' => 'root';

# DELETE /
del sub { shift->render(text => 'Hello!') };

# * /
any sub { shift->render(text => 'Bye!') };

# POST /multipart/form
post '/multipart/form' => sub {
  my $self = shift;
  my @test = $self->param('test');
  $self->render_text(join "\n", @test);
};

# Reverse "partial" alias
hook before_render => sub {
  my ($self, $args) = @_;
  $args->{partial} = 1 if $args->{laitrap};
};

# GET /reverse/render
get '/reverse/render' => sub {
  my $self = shift;
  $self->render_data(
    scalar reverse $self->render_text('lalala', laitrap => 1));
};

# Force recursion
hook before_render => sub {
  my $self = shift;
  $self->render('foo/bar') if $self->stash('before_render');
};

# GET /before/render
get '/before/render' => {before_render => 1} => sub {
  shift->render('foo/bar');
};

# GET /auto_name
get '/auto_name' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('auto_name'));
};

# GET /reserved
get '/reserved' => sub {
  my $self = shift;
  $self->render_text($self->param('data') . join(',', $self->param));
};

# GET /custom_name
get '/custom_name' => 'auto_name';

# GET /inline/exception
get '/inline/exception' => sub { shift->render(inline => '% die;') };

# GET /data/exception
get '/data/exception' => 'dies';

# GET /template/exception
get '/template/exception' => 'dies_too';

# GET /waypoint
# GET /waypoint/foo
app->routes->waypoint('/waypoint')->to(text => 'waypoints rule!')
  ->get('/foo' => {text => 'waypoints work!'});

# GET /with-format
get '/with-format' => {format => 'html'} => 'with-format';

# GET /without-format
get '/without-format' => 'without-format';

# * /json_too
any '/json_too' => {json => {hello => 'world'}};

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
  my $chunks =
    [qw/foo bar/, $self->req->url->to_abs->userinfo, $self->url_for->to_abs];
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
  my $self    = shift;
  my $url     = $self->req->url->to_abs;
  my $address = $self->tx->remote_address;
  my $number  = $self->param('number');
  $self->render_text("$url-$address-$number");
};

# DELETE /inline/epl
del '/inline/epl' => sub { shift->render(inline => '<%= 1 + 1%>') };

# GET /inline/ep
get '/inline/ep' =>
  sub { shift->render(inline => "<%= param 'foo' %>works!", handler => 'ep') };

# GET /inline/ep/too
get '/inline/ep/too' => sub { shift->render(inline => '0', handler => 'ep') };

# GET /inline/ep/partial
get '/inline/ep/partial' => sub {
  my $self = shift;
  $self->stash(inline_template => "♥<%= 'just ♥' %>");
  $self->render(
    inline  => '<%= include inline => $inline_template %>works!',
    handler => 'ep'
  );
};

# GET /source
get '/source' => sub {
  my $self = shift;
  my $file = $self->param('fail') ? 'does_not_exist.txt' : '../lite_app.t';
  $self->render_static($file)
    or $self->render_text('does not exist!', status => 404);
};

# GET /foo_relaxed/*
get '/foo_relaxed/(.test)' => sub {
  my $self = shift;
  $self->render_text(
    $self->stash('test') . ($self->req->headers->dnt ? 1 : 0));
};

# GET /foo_wildcard/*
get '/foo_wildcard/(*test)' => sub {
  my $self = shift;
  $self->render_text($self->stash('test'));
};

# GET /foo_wildcard_too/*
get '/foo_wildcard_too/*test' => sub {
  my $self = shift;
  $self->render_text($self->stash('test'));
};

# GET /with/header/condition
get '/with/header/condition' => (headers => {'X-Secret-Header' => 'bar'}) =>
  'with_header_condition';

# POST /with/header/condition
post '/with/header/condition' => sub {
  my $self = shift;
  $self->render_text('foo ' . $self->req->headers->header('X-Secret-Header'));
} => (headers => {'X-Secret-Header' => 'bar'});

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

# GET /content_for
get '/content_for';

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

# GET /localized/include
get '/localized/include' => sub {
  my $self = shift;
  $self->render('localized', test => 'foo');
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
  shift->render_text(
    'Yea baby!',
    layout  => 'layout',
    handler => 'epl',
    title   => 'Layout'
  );
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

# GET /url_for_foxy
get '/url_for_foxy' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('foxy', stuff => '#test'));
};

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
get '/autostash' => sub { shift->render(handler => 'ep', foo => 'bar') };

# GET /app
get '/app' => {layout => 'app'};

# GET /helper
get '/helper' => sub { shift->render(handler => 'ep') } => 'helper';
app->helper(agent => sub { shift->req->headers->user_agent });

# GET /eperror
get '/eperror' => sub { shift->render(handler => 'ep') } => 'eperror';

# GET /subrequest
get '/subrequest' => sub {
  my $self = shift;
  my $tx   = $self->ua->post('/template');
  $self->render_text($tx->success->body);
};

# GET /subrequest_simple
get '/subrequest_simple' => sub {
  my $self = shift;
  $self->render_text($self->ua->post('/template')->res->body);
};

# GET /subrequest_sync
get '/subrequest_sync' => sub {
  my $self = shift;
  $self->ua->post('/template');
  $self->render_text($self->ua->post('/template')->res->body);
};

# Make sure hook runs async
hook after_dispatch => sub { shift->stash->{async} = 'broken!' };

# GET /subrequest_async
my $async;
get '/subrequest_async' => sub {
  my $self = shift;
  $self->ua->post(
    '/template' => sub {
      my $tx = pop;
      $self->render_text($tx->res->body . $self->stash->{'async'});
      $async = $self->stash->{async};
    }
  );
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
};

# GET /static_render
get '/static_render' => sub {
  shift->render_static('hello.txt');
};

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
    $captures->{test} = $captures->{text} . "$num works!";
    return 1 if $c->stash->{default} == $num;
    return;
  }
);

# GET /default/condition
get '/default/:text' => (default => 23) => sub {
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
  1;
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
  undef;
};

# GET /param_auth
get '/param_auth';

# GET /param_auth/too
get '/param_auth/too' =>
  sub { shift->render_text('You could be Bender too!') };

under sub {
  my $self = shift;
  $self->stash(_name => 'stash');
  $self->cookie(foo => 'cookie', {expires => (time + 60)});
  $self->signed_cookie(bar => 'signed_cookie', {expires => (time + 120)});
  $self->cookie(bad => 'bad_cookie--12345678');
  1;
};

# GET /bridge2stash
get '/bridge2stash' =>
  sub { shift->render(template => 'bridge2stash', handler => 'ep'); };

# Make sure after_dispatch can make session changes
hook after_dispatch => sub {
  my $self = shift;
  return unless $self->req->url->path =~ /^\/late\/session/;
  $self->session(late => 'works!');
};

# GET /late/session
get '/late/session' => sub {
  my $self = shift;
  my $late = $self->session('late') || 'not yet!';
  $self->render_text($late);
};

# Counter
my $under = 0;
under sub {
  shift->res->headers->header('X-Under' => ++$under);
  1;
};

# GET /with_under_count
get '/with/under/count';

# Everything gets past this
under sub {
  shift->res->headers->header('X-Possible' => 1);
  1;
};

# GET /possible
get '/possible' => 'possible';

# Nothing gets past this
under sub {
  shift->res->headers->header('X-Impossible' => 1);
  0;
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
my $t = Test::Mojo->new;

# User agent timer
my $tua = Mojo::UserAgent->new(ioloop => $ua->ioloop, app => app);
my $timer;
$tua->ioloop->timer(
  '0.1' => sub {
    my $async = '';
    $tua->get(
      '/' => sub {
        my $tx = pop;
        $timer = $tx->res->body . $async;
      }
    );
    $async = 'works!';
  }
);

# GET /☃
$t->get_ok('/☃')->status_is(200)->content_is('/%E2%98%83');

# GET /unicode/a%E4b
$t->get_ok('/unicode/a%E4b')->status_is(200)->content_is('/unicode/a%E4b');

# GET /unicode/☃
$t->get_ok('/unicode/☃')->status_is(200)
  ->content_is('☃/unicode/%E2%98%83');

# GET /unicode/a b
$t->get_ok('/unicode/a b')->status_is(200)->content_is('a b/unicode/a%20b');

# GET /unicode/a\b
$t->get_ok('/unicode/a\\b')->status_is(200)->content_is('a\\b/unicode/a%5Cb');

# GET /conditional
$t->get_ok('/conditional' => {'X-Condition' => 'Conditions rock!'})
  ->status_is(200)->content_is("Conditions rock!\n");

# GET /conditional (missing header)
$t->get_ok('/conditional')->status_is(404)->content_is("Oops!\n");

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

# DELETE /
$t->delete_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Hello!');

# POST /
$t->post_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Bye!');

# POST /multipart/form ("application/x-www-form-urlencoded")
$t->post_form_ok('/multipart/form', {test => [1 .. 5]})->status_is(200)
  ->content_is(join "\n", 1 .. 5);

# POST /multipart/form ("multipart/form-data")
$t->post_form_ok('/multipart/form',
  {test => [1 .. 5], file => {content => '123'}})->status_is(200)
  ->content_is(join "\n", 1 .. 5);

# GET /reverse/render
$t->get_ok('/reverse/render')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('alalal');

# GET /before/render
$t->get_ok('/before/render')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("controller and action!\n");

# GET /auto_name
$t->get_ok('/auto_name')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/custom_name');

# GET /reserved
$t->get_ok('/reserved?data=just-works')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('just-worksdata');

# GET /reserved
$t->get_ok('/reserved?data=just-works&json=test')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('just-worksdata,json');

# GET /inline/exception
$t->get_ok('/inline/exception')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("Died at inline template line 1.\n\n");

# GET /data/exception
$t->get_ok('/data/exception')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(qq/Died at template from DATA section "dies.html.ep" line 2/
    . qq/, near "123".\n\n/);

# GET /template/exception
$t->get_ok('/template/exception')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  qq/Died at template "dies_too.html.ep" line 2, near "321".\n\n/);

# GET /waypoint
$t->get_ok('/waypoint')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('waypoints rule!');

# GET /waypoint/foo
$t->get_ok('/waypoint/foo')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('waypoints work!');

# POST /waypoint/foo
$t->post_ok('/waypoint/foo')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)');

# GET /waypoint/bar
$t->get_ok('/waypoint/bar')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)');

# GET /with-format
$t->get_ok('/with-format')->content_is("/without-format\n");

# GET /without-format
$t->get_ok('/without-format')->content_is("/without-format\n");

# GET /without-format.html
$t->get_ok('/without-format.html')->content_is("/without-format\n");

# GET /json_too
$t->get_ok('/json_too')->status_is(200)->json_content_is({hello => 'world'});

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

# GET /template.txt.epl (protected DATA template)
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
$t->get_ok(
  $t->build_url->userinfo('sri:foo')->path('/stream')->query(foo => 'bar'))
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr/^foobarsri\:foohttp:\/\/localhost\:\d+\/stream$/);

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
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is('привет мир');

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

# GET /0 ("X-Forwarded-For")
$t->get_ok('/0', {'X-Forwarded-For' => '192.168.2.2, 192.168.2.1'})
  ->status_is(200)
  ->content_like(qr/http\:\/\/localhost\:\d+\/0\-127\.0\.0\.1\-0/);

# GET /0 (reverse proxy with "X-Forwarded-For")
my $backup2 = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$t->get_ok('/0', {'X-Forwarded-For' => '192.168.2.2, 192.168.2.1'})
  ->status_is(200)
  ->content_like(qr/http\:\/\/localhost\:\d+\/0\-192\.168\.2\.1\-0/);
$ENV{MOJO_REVERSE_PROXY} = $backup2;

# GET /0 ("X-Forwarded-Host")
$t->get_ok('/0', {'X-Forwarded-Host' => 'mojolicio.us:8080'})->status_is(200)
  ->content_like(qr/http\:\/\/localhost\:\d+\/0\-127\.0\.0\.1\-0/);

# GET /0 (reverse proxy with "X-Forwarded-Host")
$backup2 = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$t->get_ok('/0', {'X-Forwarded-Host' => 'mojolicio.us:8080'})->status_is(200)
  ->content_is('http://mojolicio.us:8080/0-127.0.0.1-0');
$ENV{MOJO_REVERSE_PROXY} = $backup2;

# GET /0 ("X-Forwarded-HTTPS" and "X-Forwarded-Host")
$t->get_ok('/0',
  {'X-Forwarded-HTTPS' => 1, 'X-Forwarded-Host' => 'mojolicio.us'})
  ->status_is(200)
  ->content_like(qr/http\:\/\/localhost\:\d+\/0\-127\.0\.0\.1\-0/);

# GET /0 (reverse proxy with "X-Forwarded-HTTPS" and "X-Forwarded-Host")
$backup2 = $ENV{MOJO_REVERSE_PROXY};
$ENV{MOJO_REVERSE_PROXY} = 1;
$t->get_ok('/0',
  {'X-Forwarded-HTTPS' => 1, 'X-Forwarded-Host' => 'mojolicio.us'})
  ->status_is(200)->content_is('https://mojolicio.us/0-127.0.0.1-0');
$ENV{MOJO_REVERSE_PROXY} = $backup2;

# DELETE /inline/epl
$t->delete_ok('/inline/epl')->status_is(200)->content_is("2\n");

# GET /inline/ep
$t->get_ok('/inline/ep?foo=bar')->status_is(200)->content_is("barworks!\n");

# GET /inline/ep/too
$t->get_ok('/inline/ep/too')->status_is(200)->content_is("0\n");

# GET /inline/ep/partial
$t->get_ok('/inline/ep/partial')->status_is(200)
  ->content_is("♥just ♥\nworks!\n");

# GET /source
$t->get_ok('/source')->status_is(200)->content_like(qr/get_ok\('\/source/);

# GET /source (file does not exist)
$t->get_ok('/source?fail=1')->status_is(404)->content_is('does not exist!');

# GET / (with body and max message size)
$backup2 = $ENV{MOJO_MAX_MESSAGE_SIZE} || '';
$ENV{MOJO_MAX_MESSAGE_SIZE} = 1024;
$t->get_ok('/', '1234' x 1024)->status_is(413)
  ->content_is(
  "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");
$ENV{MOJO_MAX_MESSAGE_SIZE} = $backup2;

# GET /foo_relaxed/123
$t->get_ok('/foo_relaxed/123')->status_is(200)->content_is('1230');

# GET /foo_relaxed/123 (Do Not Track)
$t->get_ok('/foo_relaxed/123', {DNT => 1})->status_is(200)
  ->content_is('1231');

# GET /foo_relaxed
$t->get_ok('/foo_relaxed/')->status_is(404);

# GET /foo_wildcard/123
$t->get_ok('/foo_wildcard/123')->status_is(200)->content_is('123');

# GET /foo_wildcard
$t->get_ok('/foo_wildcard/')->status_is(404);

# GET /foo_wildcard_too/123
$t->get_ok('/foo_wildcard_too/123')->status_is(200)->content_is('123');

# GET /foo_wildcard_too
$t->get_ok('/foo_wildcard_too/')->status_is(404);

# GET /with/header/condition
$t->get_ok('/with/header/condition', {'X-Secret-Header' => 'bar'})
  ->status_is(200)->content_like(qr/^Test ok<base href="http:\/\/localhost/);

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

# GET /content_for
$t->get_ok('/content_for')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("This\nseems\nto\nHello    world!\n\nwork!\n");

# GET /template_inheritance
$t->get_ok('/template_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  "<title>Works!</title>\n<br>Sidebar!Hello World!\nDefault footer!");

# GET /layout_without_inheritance
$t->get_ok('/layout_without_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  "<title></title>\nDefault header!Default sidebar!Default footer!");

# GET /double_inheritance
$t->get_ok('/double_inheritance')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("<title>Works!</title>\n<br>Sidebar too!Default footer!");

# GET /plugin_with_template
$t->get_ok('/plugin_with_template')->status_is(200)
  ->content_is("layout_with_template\nwith template\n\n");

# GET /nested-includes
$t->get_ok('/nested-includes')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Nested Hello\n[\n  1,\n  2\n]\nthere<br>!\n\n\n\n");

# GET /localized/include
$t->get_ok('/localized/include')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("localized1 foo\nlocalized2 321\n\n\nfoo\n\n");

# GET /outerlayout
$t->get_ok('/outerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# GET /outerlayouttwo
$t->get_ok('/outerlayouttwo')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("layouted Hello\n[\n  1,\n  2\n]\nthere<br>!\n\n\n");

# GET /outerinnerlayout
$t->get_ok('/outerinnerlayout')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  "layouted Hello\nlayouted [\n  1,\n  2\n]\nthere<br>!\n\n\n\n");

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
  ->content_like(qr/\d+a\d+b\d+c\d+d\d+e\d+/)->content_isnt($memorized);

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
  ->content_is("LayoutYea baby! with layout\n");

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

# GET /url_for_foxy
$t->get_ok('/url_for_foxy')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/firefox/%23test');

# POST /utf8
$t->post_form_ok('/utf8', 'UTF-8' => {name => 'табак'})->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 22)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("табак ангел\n");

# POST /utf8 (multipart/form-data)
$t->post_form_ok(
  '/utf8',
  'UTF-8' => {name => 'табак'},
  {'Content-Type' => 'multipart/form-data'}
  )->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 22)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("табак ангел\n");

# POST /malformed_utf8
my $tx = Mojo::Transaction::HTTP->new;
$tx->req->method('POST');
$tx->req->url->parse('/malformed_utf8');
$tx->req->headers->content_type('application/x-www-form-urlencoded');
$tx->req->body('foo=%E1');
$ua->start($tx);
is $tx->res->code, 200, 'right status';
is scalar $tx->res->headers->server, 'Mojolicious (Perl)',
  'right "Server" value';
is scalar $tx->res->headers->header('X-Powered-By'), 'Mojolicious (Perl)',
  'right "X-Powered-By" value';
is $tx->res->body, '%E1', 'right content';

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
  ->content_is("23\n<br>\n&lt;...\n/template\n(Mojolicious (Perl))");

# GET /helper
$t->get_ok('/helper', {'User-Agent' => 'Explorer'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("23\n<br>\n&lt;...\n/template\n(Explorer)");

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

# GET /redirect_named (with redirecting enabled in user agent)
$t->max_redirects(3);
$t->get_ok('/redirect_named')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => undef)->element_exists('#foo')
  ->element_exists_not('#bar')->text_isnt('div' => 'Redirect')
  ->text_is('div' => 'Redirect works!')->text_unlike('[id="foo"]' => qr/Foo/)
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
  ->content_is('works 23 condition23 works!');

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
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!/!\n");

# GET /bridge2stash (broken session cookie)
$t->reset_session;
my $session = b("☃☃☃☃☃")->b64_encode('');
my $hmac    = $session->clone->hmac_md5_sum($t->ua->app->secret);
my $broken  = "\$Version=1; mojolicious=$session--$hmac; \$Path=/";
$t->get_ok('/bridge2stash' => {Cookie => $broken})->status_is(200)
  ->content_is("stash too!!!!!!!/!\n");

# GET /bridge2stash (fresh start)
$t->reset_session;
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!!\n");

# GET /favicon.ico (random static requests)
$t->get_ok('/favicon.ico')->status_is(200);
$t->get_ok('/mojolicious-white.png')->status_is(200);
$t->get_ok('/mojolicious-black.png')->status_is(200);
$t->get_ok('/favicon.ico')->status_is(200);

# GET /bridge2stash (with cookies, session and flash again)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!/!\n");

# GET /bridge2stash (with cookies and session but no flash)
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!/!\n");

# GET /bridge2stash (with cookies and session cleared)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is("stash too!cookie!signed_cookie!!bad_cookie--12345678!!!!\n");

# GET /late/session (late session does not affect rendering)
$t->get_ok('/late/session')->status_is(200)->content_is('not yet!');

# GET /late/session (previous late session does affect rendering)
$t->get_ok('/late/session')->status_is(200)->content_is('works!');

# GET /late/session (previous late session does affect rendering again)
$t->get_ok('/late/session')->status_is(200)->content_is('works!');

# GET /with/under/count
$t->get_ok('/with/under/count', {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is('X-Under'      => 1)->content_is("counter\n");

# GET /bridge2stash (again)
$t->get_ok('/bridge2stash', {'X-Flash' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!/!\n");

# GET /bridge2stash (with cookies, session and flash)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!/!\n");

# GET /bridge2stash (with cookies and session but no flash)
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!/!\n");

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

# User agent timer
$tua->ioloop->one_tick('0.1');
is $timer,
  "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\nworks!",
  'right content';

__DATA__
@@ with-format.html.ep
<%= url_for 'without-format' %>

@@ without-format.html.ep
<%= url_for 'without-format' %>

@@ dies.html.ep
test
% die;
123

@@ foo/bar.html.ep
controller and action!

@@ dead_template.html.ep
<%= dead 'works too!' %>

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

@@ with_header_condition.html.ep
Test ok<%= base_tag %>

@@ content_for.html.ep
This
<% content_for message => begin =%>Hello<% end %>
seems
% content_for message => begin
    world!
% end
to
<%= content_for 'message' %>
work!

@@ template_inheritance.html.ep
% layout 'template_inheritance';
% title 'Works!';
<% content header => begin =%>
<%= b('<br>') %>
<% end =%>
<% content sidebar => begin =%>
Sidebar!
<% end =%>
Hello World!

@@ layouts/template_inheritance.html.ep
<title><%= title %></title>
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

@@ localized.html.ep
% layout 'localized1';
<%= $test %>
<%= include 'localized_partial', test => 321, layout => 'localized2' %>
<%= $test %>

@@ localized_partial.html.ep
<%= $test %>

@@ layouts/localized1.html.ep
localized1 <%= content %>

@@ layouts/localized2.html.ep
localized2 <%= content %>

@@ outerlayout.html.ep
Hello
<%= include 'outermenu' %>

@@ outermenu.html.ep
% stash test => 'there';
<%= dumper [1, 2] %><%= stash 'test' %><br>!

@@ outerinnerlayout.html.ep
Hello
<%= include 'outermenu', layout => 'layout' %>

@@ not_found.html.epl
Oops!

@@ index.html.epl
Just works!\

@@ form.html.epl
<%= shift->param('name') %> ангел

@@ layouts/layout.html.epl
% my $self = shift;
<%= $self->title %><%= $self->render_content %> with layout

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
%== '<br>'
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
