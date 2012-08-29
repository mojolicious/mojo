use Mojo::Base -strict;

use utf8;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 704;

use Mojo::ByteStream 'b';
use Mojo::Cookie::Response;
use Mojo::Date;
use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::Transaction::HTTP;
use Mojolicious::Lite;
use Test::Mojo;

# Missing plugin
eval { plugin 'does_not_exist' };
is $@, qq{Plugin "does_not_exist" missing, maybe you need to install it?\n},
  'right error';

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

# UTF-8 text
app->types->type(txt => 'text/plain;charset=UTF-8');

# GET /☃
get '/☃' => sub {
  my $self = shift;
  $self->render_text($self->url_for . $self->url_for('current'));
};

# GET /uni/a%E4b
get '/uni/aäb' => sub {
  my $self = shift;
  $self->render(text => $self->url_for);
};

# GET /unicode/*
get '/unicode/:stuff' => sub {
  my $self = shift;
  $self->render(text => $self->param('stuff') . $self->url_for);
};

# GET /
get '/' => 'root';

# GET /alternatives/☃
# GET /alternatives/♥
get '/alternatives/:char' => [char => [qw(☃ ♥)]] => sub {
  my $self = shift;
  $self->render_text($self->url_for);
};

# GET /alterformat
# GET /alterformat.json
get '/alterformat' => [format => ['json']] => {format => 'json'} => sub {
  my $self = shift;
  $self->render_text($self->stash('format'));
};

# GET /noformat
get '/noformat' => [format => 0] => {format => 'xml'} => sub {
  my $self = shift;
  $self->render_text($self->stash('format') . $self->url_for);
};

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

# GET /auto_name
get '/auto_name' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('auto_name'));
};

# GET /query_string
get '/query_string' => sub {
  my $self = shift;
  $self->render_text(b($self->req->url->query)->url_unescape);
};

# GET /multi/*
get '/multi/:bar' => sub {
  my $self = shift;
  my ($foo, $bar, $baz) = $self->param([qw(foo bar baz)]);
  $self->render(
    data => join('', map { $_ // '' } $foo, $bar, $baz),
    test => $self->param(['yada'])
  );
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
  my $chunks
    = [qw(foo bar), $self->req->url->to_abs->userinfo, $self->url_for->to_abs];
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
  $self->on(finish => sub { $finished += 2 });
  $finished = 1;
  $self->render(text => 'so far so good!');
};

# GET /привет/мир
get '/привет/мир' =>
  sub { shift->render(text => 'привет мир') };

# GET /root.html
get '/root.html' => 'root_path';

# GET /root
get '/root' => sub { shift->render_text('root fallback!') };

# GET /template.txt
get '/template.txt' => {template => 'template', format => 'txt'};

# GET /0
get ':number' => [number => qr/0/] => sub {
  my $self    = shift;
  my $url     = $self->req->url->to_abs;
  my $address = $self->tx->remote_address;
  my $number  = $self->param('number');
  $self->render_text("$url-$address-$number");
};

# DELETE /inline/epl
del '/inline/epl' => sub { shift->render(inline => '<%= 1 + 1 %> ☃') };

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
  $self->render('this_does_not_ever_exist')
    or $self->render_static($file)
    or $self->render_text('does not exist!', status => 404);
};

# GET /foo_relaxed/*
get '/foo_relaxed/#test' => sub {
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
get '/with/header/condition' => (
  headers => {'X-Secret-Header'  => 'bar'},
  headers => {'X-Another-Header' => 'baz'}
) => 'with_header_condition';

# POST /with/header/condition
post '/with/header/condition' => sub {
  my $self = shift;
  $self->render_text('foo ' . $self->req->headers->header('X-Secret-Header'));
} => (headers => {'X-Secret-Header' => 'bar'});

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

# * /something
any '/something' => sub {
  my $self = shift;
  $self->render_text('Just works!');
};

# GET|POST /something/else
any [qw(get post)] => '/something/else' => sub {
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

# PATCH /firefox/*
patch '/firefox/:stuff' => (agent => qr/Firefox/) => sub {
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
  my $self = shift;
  $self->render_text(b($self->param('foo'))->url_escape->to_string);
};

# GET /json
get '/json' =>
  sub { shift->render_json({foo => [1, -2, 3, 'b☃r']}, layout => 'layout') };

# GET /autostash
get '/autostash' => sub { shift->render(handler => 'ep', foo => 'bar') };

# GET /app
get app => {layout => 'app'};

# GET /helper
get '/helper' => sub { shift->render(handler => 'ep') } => 'helper';
app->helper(agent => sub { shift->req->headers->user_agent });

# GET /eperror
get '/eperror' => sub { shift->render(handler => 'ep') } => 'eperror';

# GET /subrequest
get '/subrequest' => sub {
  my $self = shift;
  $self->render_text($self->ua->post('/template')->success->body);
};

# Make sure hook runs non-blocking
hook after_dispatch => sub { shift->stash->{nb} = 'broken!' };

# GET /subrequest_non_blocking
my $nb;
get '/subrequest_non_blocking' => sub {
  my $self = shift;
  $self->ua->post(
    '/template' => sub {
      my $tx = pop;
      $self->render_text($tx->res->body . $self->stash->{nb});
      $nb = $self->stash->{nb};
    }
  );
  $self->stash->{nb} = 'success!';
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

# GET /redirect_callback
get '/redirect_callback' => sub {
  my $self = shift;
  Mojo::IOLoop->timer(
    0 => sub {
      $self->res->code(301);
      $self->res->body('Whatever!');
      $self->redirect_to('http://127.0.0.1/foo');
    }
  );
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

# GET /url_with
get '/url_with';

# GET /url_with/*
get '/url_with/:foo' => sub {
  my $self = shift;
  $self->render(text => $self->url_with(foo => 'bar')->to_abs);
};

# GET /dynamic/inline
my $dynamic_inline = 1;
get '/dynamic/inline' => sub {
  my $self = shift;
  $self->render(inline => 'dynamic inline ' . $dynamic_inline++);
};

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $t = Test::Mojo->new;

# Application is already available
is $t->app->test_helper2, 'Mojolicious::Controller', 'right class';
is $t->app, app->commands->app, 'applications are equal';

# GET /☃
$t->get_ok('/☃')->status_is(200)->content_is('/%E2%98%83/%E2%98%83');

# GET /☃ (with trailing slash)
$t->get_ok('/☃/')->status_is(200)->content_is('/%E2%98%83//%E2%98%83/');

# GET /uni/aäb
$t->get_ok('/uni/aäb')->status_is(200)->content_is('/uni/a%C3%A4b');

# GET /uni/a%E4b
$t->get_ok('/uni/a%E4b')->status_is(200)->content_is('/uni/a%C3%A4b');

# GET /uni/a%C3%A4b
$t->get_ok('/uni/a%C3%A4b')->status_is(200)->content_is('/uni/a%C3%A4b');

# GET /unicode/☃
$t->get_ok('/unicode/☃')->status_is(200)
  ->content_is('☃/unicode/%E2%98%83');

# GET /unicode/a b
$t->get_ok('/unicode/a b')->status_is(200)->content_is('a b/unicode/a%20b');

# GET /unicode/a\b
$t->get_ok('/unicode/a\\b')->status_is(200)->content_is('a\\b/unicode/a%5Cb');

# GET /
$t->get_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# HEAD /
$t->head_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 55)->content_is('');

# GET / (with body)
$t->get_ok('/', '1234' x 1024)->status_is(200)
  ->content_is("/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# DELETE /
$t->delete_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Hello!');

# POST /
$t->post_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Bye!');

# GET /alternatives/☃
$t->get_ok('/alternatives/☃')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/alternatives/%E2%98%83');

# GET /alternatives/♥
$t->get_ok('/alternatives/♥')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/alternatives/%E2%99%A5');

# GET /alternatives/☃23 (invalid alternative)
$t->get_ok('/alternatives/☃23')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("Oops!\n");

# GET /alternatives (invalid alternative)
$t->get_ok('/alternatives')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("Oops!\n");

# GET /alternatives/test (invalid alternative)
$t->get_ok('/alternatives/test')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("Oops!\n");

# GET /alterformat
$t->get_ok('/alterformat')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('json');

# GET /alterformat.json
$t->get_ok('/alterformat.json')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('json');

# GET /alterformat.html (invalid format)
$t->get_ok('/alterformat.html')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("Oops!\n");

# GET /noformat
$t->get_ok('/noformat')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('xml/noformat');

# GET /noformat.xml
$t->get_ok('/noformat.xml')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("Oops!\n");

# POST /multipart/form ("application/x-www-form-urlencoded")
$t->post_form_ok('/multipart/form' => {test => [1 .. 5]})->status_is(200)
  ->content_is(join "\n", 1 .. 5);

# POST /multipart/form ("multipart/form-data")
$t->post_form_ok(
  '/multipart/form' => {test => [1 .. 5], file => {content => '123'}})
  ->status_is(200)->content_is(join "\n", 1 .. 5);

# GET /auto_name
$t->get_ok('/auto_name')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/custom_name');

# GET /query_string (query string roundtrip)
$t->get_ok('/query_string?http://mojolicio.us/perldoc?foo=bar')
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('http://mojolicio.us/perldoc?foo=bar');

# GET /multi/B
$t->get_ok('/multi/B?foo=A&baz=C')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('ABC');

# GET /multi/B (injection attack)
$t->get_ok('/multi/B?foo=A&foo=E&baz=C&yada=D&yada=text&yada=fail')
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('ABC');

# GET /multi/B (missing parameter)
$t->get_ok('/multi/B?baz=C')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('BC');

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
  ->content_is(qq{Died at template "dies.html.ep" from DATA section line 2}
    . qq{, near "123".\n\n});

# GET /template/exception
$t->get_ok('/template/exception')->status_is(500)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is(
  qq{Died at template "dies_too.html.ep" line 2, near "321".\n\n});

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
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("Just some\ntext!\n\n");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static.txt' => {'If-Modified-Since' => $modified})
  ->status_is(304)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# GET /static.txt (partial inline file)
$t->get_ok('/static.txt' => {'Range' => 'bytes=2-5'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 4)
  ->content_is('st s');

# GET /static.txt (base64 static inline file)
$t->get_ok('/static2.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");

# GET /static.txt (base64 static inline file, If-Modified-Since)
$modified = Mojo::Date->new->epoch(time - 3600);
$t->get_ok('/static2.txt' => {'If-Modified-Since' => $modified})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("test 123\nlalala");
$modified = $t->tx->res->headers->last_modified;
$t->get_ok('/static2.txt' => {'If-Modified-Since' => $modified})
  ->status_is(304)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('');

# GET /static.txt (base64 partial inline file)
$t->get_ok('/static2.txt' => {'Range' => 'bytes=2-5'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 4)
  ->content_is('st 1');

# GET /template.txt.epl (protected DATA template)
$t->get_ok('/template.txt.epl')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

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
  $t->ua->app_url->userinfo('sri:foo')->path('/stream')->query(foo => 'bar'))
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_like(qr!^foobarsri:foohttp://localhost:\d+/stream$!);

# GET /maybe/ajax (not ajax)
$t->get_ok('/maybe/ajax')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('not ajax');

# GET /maybe/ajax (is ajax)
$t->get_ok('/maybe/ajax' => {'X-Requested-With' => 'XMLHttpRequest'})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('is ajax');

# GET /finished (with finish event)
$t->get_ok('/finished')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('so far so good!');
is $finished, 3, 'finished';

# GET / (IRI)
$t->get_ok('/привет/мир')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is('привет мир');

# GET /root.html
$t->get_ok('/root.html')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is("/\n");

# GET /root (fallback route without format)
$t->get_ok('/root')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('root fallback!');

# GET /root.txt (fallback route without format)
$t->get_ok('/root.txt')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('root fallback!');

# GET /.html
$t->get_ok('/.html')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is("/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# GET /0 ("X-Forwarded-For")
$t->get_ok('/0' => {'X-Forwarded-For' => '192.0.2.2, 192.0.2.1'})
  ->status_is(200)->content_like(qr!^http://localhost:\d+/0-!)
  ->content_like(qr/-0$/)->content_unlike(qr!-192\.0\.2\.1-0$!);

# GET /0 ("X-Forwarded-HTTPS")
$t->get_ok('/0' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_like(qr!^http://localhost:\d+/0-!)->content_like(qr/-0$/)
  ->content_unlike(qr!-192\.0\.2\.1-0$!);

# GET /0 (reverse proxy with "X-Forwarded-For")
{
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  $t->get_ok('/0' => {'X-Forwarded-For' => '192.0.2.2, 192.0.2.1'})
    ->status_is(200)->content_like(qr!http://localhost:\d+/0-192\.0\.2\.1-0$!);
}

# GET /0 (reverse proxy with "X-Forwarded-HTTPS")
{
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  $t->get_ok('/0' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_like(qr!^https://localhost:\d+/0-!)->content_like(qr/-0$/)
    ->content_unlike(qr!-192\.0\.2\.1-0$!);
}

# DELETE /inline/epl
$t->delete_ok('/inline/epl')->status_is(200)->content_is("2 ☃\n");

# GET /inline/ep
$t->get_ok('/inline/ep?foo=bar')->status_is(200)->content_is("barworks!\n");

# GET /inline/ep/too
$t->get_ok('/inline/ep/too')->status_is(200)->content_is("0\n");

# GET /inline/ep/partial
$t->get_ok('/inline/ep/partial')->status_is(200)
  ->content_is("♥just ♥\nworks!\n");

# GET /source
$t->get_ok('/source')->status_is(200)->content_like(qr!get_ok\('/source!);

# GET /source (file does not exist)
$t->get_ok('/source?fail=1')->status_is(404)->content_is('does not exist!');

# GET / (with body and max message size)
{
  local $ENV{MOJO_MAX_MESSAGE_SIZE} = 1024;
  $t->get_ok('/', '1234' x 1024)->status_is(413)
    ->content_is(
    "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");
}

# GET /foo_relaxed/123
$t->get_ok('/foo_relaxed/123')->status_is(200)->content_is('1230');

# GET /foo_relaxed/123 (Do Not Track)
$t->get_ok('/foo_relaxed/123' => {DNT => 1})->status_is(200)
  ->content_is('1231');

# GET /foo_relaxed
$t->get_ok('/foo_relaxed/')->status_is(404);

# GET /foo_wildcard/123
$t->get_ok('/foo_wildcard/123')->status_is(200)->content_is('123');

# GET /foo_wildcard/IQ==%0A
$t->get_ok('/foo_wildcard/IQ==%0A')->status_is(200)->content_is("IQ==\x0a");

# GET /foo_wildcard
$t->get_ok('/foo_wildcard/')->status_is(404);

# GET /foo_wildcard_too/123
$t->get_ok('/foo_wildcard_too/123')->status_is(200)->content_is('123');

# GET /foo_wildcard_too
$t->get_ok('/foo_wildcard_too/')->status_is(404);

# GET /with/header/condition
$t->get_ok('/with/header/condition',
  {'X-Secret-Header' => 'bar', 'X-Another-Header' => 'baz'})->status_is(200)
  ->content_like(qr!^Test ok<base href="http://localhost!);

# GET /with/header/condition (missing headers)
$t->get_ok('/with/header/condition')->status_is(404)->content_like(qr/Oops!/);

# GET /with/header/condition (missing header)
$t->get_ok('/with/header/condition' => {'X-Secret-Header' => 'bar'})
  ->status_is(404)->content_like(qr/Oops!/);

# POST /with/header/condition
$t->post_ok('/with/header/condition' => {'X-Secret-Header' => 'bar'} => 'bar')
  ->status_is(200)->content_is('foo bar');

# POST /with/header/condition (missing header)
$t->post_ok('/with/header/condition' => {} => 'bar')->status_is(404)
  ->content_like(qr/Oops!/);

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
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('Yea baby!');

# POST /template
$t->post_ok('/template')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

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
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# GET /regex/23
$t->get_ok('/regex/23')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_is('23');

# GET /regex/foo
$t->get_ok('/regex/foo')->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

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

# PATCH /firefox
$t->patch_ok('/firefox/bar' => {'User-Agent' => 'Firefox'})->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/firefox/foo');

# PATCH /firefox
$t->patch_ok('/firefox/bar' => {'User-Agent' => 'Explorer'})->status_is(404)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# GET /url_for_foxy
$t->get_ok('/url_for_foxy')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('/firefox/%23test');

# POST /utf8
$t->post_form_ok('/utf8' => 'UTF-8' => {name => 'табак'})->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 22)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("табак ангел\n");

# POST /utf8 (multipart/form-data)
$t->post_form_ok(
  '/utf8' => 'UTF-8' => {name => 'табак'},
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
$t->ua->start($tx);
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
  ->json_content_is({foo => [1, -2, 3, 'b☃r']})
  ->json_is('/foo' => [1, -2, 3, 'b☃r'])->json_is('/foo/3', 'b☃r')
  ->json_has('/foo')->json_hasnt('/bar');

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
$t->get_ok('/helper' => {'User-Agent' => 'Explorer'})->status_is(200)
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

# GET /subrequest (again)
$t->get_ok('/subrequest')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!');

# GET /subrequest_non_blocking
$t->get_ok('/subrequest_non_blocking')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('Just works!success!');
is $nb, 'broken!', 'right text';

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
  ->header_like(Location => qr!/foo/bar\?foo=bar$!)
  ->content_is('Redirecting!');

# GET /redirect_named
$t->get_ok('/redirect_named')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_like(Location => qr!/template.txt$!)->content_is('Redirecting!');

# GET /redirect_no_render
$t->get_ok('/redirect_no_render')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 0)
  ->header_like(Location => qr!/template.txt$!)->content_is('');

# GET /redirect_callback
$t->get_ok('/redirect_callback')->status_is(301)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 9)
  ->header_is(Location => 'http://127.0.0.1/foo')->content_is('Whatever!');

# GET /static_render
$t->get_ok('/static_render')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'   => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 31)
  ->content_is("Hello Mojo from a static file!\n");

# GET /redirect_named (with redirecting enabled in user agent)
$t->ua->max_redirects(3);
$t->get_ok('/redirect_named')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_is(Location       => undef)->element_exists('#☃')
  ->element_exists_not('#foo')->text_isnt('#foo' => 'whatever')
  ->text_isnt('div#☃' => 'Redirect')
  ->text_is('div#☃' => 'Redirect works!')->text_unlike('div#☃' => qr/Foo/)
  ->text_like('div#☃' => qr/^Redirect/);
$t->ua->max_redirects(0);
Test::Mojo->new->tx($t->tx->previous)->status_is(302)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->header_like(Location => qr!/template.txt$!)->content_is('Redirecting!');

# GET /koi8-r
my $koi8
  = 'Этот человек наполняет меня надеждой.'
  . ' Ну, и некоторыми другими глубокими и приводящими в'
  . ' замешательство эмоциями.';
$t->get_ok('/koi8-r')->status_is(200)
  ->header_is(Server         => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_type_is('text/html; charset=koi8-r')->content_like(qr/^$koi8/);

# GET /hello.txt (static file)
$t->get_ok('/hello.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 31)
  ->content_is("Hello Mojo from a static file!\n");

# GET /hello.txt (partial static file)
$t->get_ok('/hello.txt' => {'Range' => 'bytes=2-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 7)
  ->content_is('llo Moj');

# GET /hello.txt (partial static file, starting at first byte)
$t->get_ok('/hello.txt' => {'Range' => 'bytes=0-8'})->status_is(206)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By'  => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 9)
  ->content_is('Hello Moj');

# GET /hello.txt (partial static file, first byte)
$t->get_ok('/hello.txt' => {'Range' => 'bytes=0-0'})->status_is(206)
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
$t->get_ok('/hello3.txt' => {'Range' => 'bytes=0-0'})->status_is(206)
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
  ->header_like('Location' => qr!/template$!)->content_is('');

# GET /redirect/condition/1 (with condition header)
$t->get_ok('/redirect/condition/1' => {'X-Condition-Test' => 1})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
  ->content_is('condition works too!');

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
is b($t->tx->res->body)->url_unescape->decode('UTF-8'), '/captures/♥/☃',
  'right result';

# GET /favicon.ico (bundled file in DATA section)
$t->get_ok('/favicon.ico')->status_is(200)->content_is("Not a favicon!\n\n");

# GET /url_with
$t->get_ok('/url_with?foo=23&bar=24&baz=25')->status_is(200)
  ->content_is(<<EOF);
/url_with?bar=24&baz=25&foo=bar
http://mojolicio.us/test?foo=23&bar=24&baz=25
/test?bar=24&baz=25
/bar/23?bar=24&baz=25&foo=yada
EOF

# GET /url_with/foo
$t->get_ok('/url_with/foo?foo=bar')->status_is(200)
  ->content_like(qr!http://localhost:\d+/url_with/bar\?foo\=bar!);

# GET /dynamic/inline
$t->get_ok('/dynamic/inline')->status_is(200)
  ->content_is("dynamic inline 1\n");

# GET /dynamic/inline (again)
$t->get_ok('/dynamic/inline')->status_is(200)
  ->content_is("dynamic inline 2\n");

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
<div id="☃">Redirect works!</div>

@@ test(test)(\Qtest\E)(.html.ep
<%= $self->match->endpoint->name %>

@@ static2.txt (base64)
dGVzdCAxMjMKbGFsYWxh

@@ with_header_condition.html.ep
Test ok<%= base_tag %>

@@ root.html.epl
% my $self = shift;
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')
%== $self->url_for('root_path')

@@ root_path.html.epl
%== shift->url_for('root');

@@ not_found.html.epl
Oops!

@@ index.html.epl
Just works!\

@@ form.html.epl
<%= shift->param('name') %> ангел

@@ layouts/layout.html.epl
% my $self = shift;
<%= $self->title %><%= $self->content %> with layout

@@ autostash.html.ep
% $self->layout('layout');
%= $foo
%= $self->test_helper('bar')
% my $foo = 42;
%= $foo
%= $self->match->endpoint->name;

@@ layouts/layout.html.ep
layouted <%== content %>

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

@@ favicon.ico
Not a favicon!

@@ url_with.html.ep
%== url_with->query([foo => 'bar'])
%== url_with('http://mojolicio.us/test')
%== url_with('/test')->query([foo => undef])
%== url_with('bartest', test => 23)->query([foo => 'yada'])

__END__
This is not a template!
lalala
test
