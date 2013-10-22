use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'development';
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::ByteStream 'b';
use Mojo::Cookie::Response;
use Mojo::IOLoop;
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
helper test_helper3 => sub { state $cache = {} };
helper dead         => sub { die $_[1] || 'works!' };
is app->test_helper('foo'), undef, 'no value yet';
is app->test_helper2, 'Mojolicious::Controller', 'right value';
app->test_helper3->{foo} = 'bar';
is app->test_helper3->{foo}, 'bar', 'right result';

# Test renderer
app->renderer->add_handler(dead => sub { die 'renderer works!' });

# UTF-8 text
app->types->type(txt => 'text/plain;charset=UTF-8');

get '/☃' => sub {
  my $self = shift;
  $self->render(
    text => $self->url_for . $self->url_for({}) . $self->url_for('current'));
};

get '/uni/aäb' => sub {
  my $self = shift;
  $self->render(text => $self->url_for);
};

get '/unicode/:0' => sub {
  my $self = shift;
  $self->render(text => $self->param('0') . $self->url_for);
};

get '/' => 'root';

get '/alternatives/:char' => [char => [qw(☃ ♥)]] => sub {
  my $self = shift;
  $self->render(text => $self->url_for);
};

get '/alterformat' => [format => ['json']] => {format => 'json'} => sub {
  my $self = shift;
  $self->render(text => $self->stash('format'));
};

get '/noformat' => [format => 0] => {format => 'xml'} => sub {
  my $self = shift;
  $self->render(text => $self->stash('format') . $self->url_for);
};

del sub { shift->render(text => 'Hello!') };

any sub { shift->render(text => 'Bye!') };

post '/multipart/form' => sub {
  my $self = shift;
  my @test = $self->param('test');
  $self->render(text => join "\n", @test);
};

get '/auto_name' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('auto_name'));
};

get '/query_string' => sub {
  my $self = shift;
  $self->render(text => b($self->req->url->query)->url_unescape);
};

get '/multi/:bar' => sub {
  my $self = shift;
  my ($foo, $bar, $baz) = $self->param([qw(foo bar baz)]);
  $self->render(
    data => join('', map { $_ // '' } $foo, $bar, $baz),
    test => $self->param(['yada'])
  );
};

get '/reserved' => sub {
  my $self = shift;
  $self->render(text => $self->param('data') . join(',', $self->param));
};

get '/custom_name' => 'auto_name';

get '/inline/exception' => sub { shift->render(inline => '% die;') };

get '/data/exception' => 'dies';

get '/template/exception' => 'dies_too';

get '/with-format' => {format => 'html'} => 'with-format';

get '/without-format' => 'without-format';

any '/json_too' => {json => {hello => 'world'}};

get '/null/:null' => sub {
  my $self = shift;
  $self->render(text => $self->param('null'), layout => 'layout');
};

get '/action_template' => {controller => 'foo'} => sub {
  my $self = shift;
  $self->render(action => 'bar');
  $self->rendered;
};

get '/dead' => sub {
  my $self = shift;
  $self->dead;
  $self->render(text => 'failed!');
};

get '/dead_template' => 'dead_template';

get '/dead_renderer' => sub { shift->render(handler => 'dead') };

get '/dead_auto_renderer' => {handler => 'dead'};

get '/regex/in/template' => 'test(test)(\Qtest\E)(';

get '/maybe/ajax' => sub {
  my $self = shift;
  return $self->render(text => 'is ajax') if $self->req->is_xhr;
  $self->render(text => 'not ajax');
};

get '/stream' => sub {
  my $self = shift;
  my $chunks
    = [qw(foo bar), $self->req->url->to_abs->userinfo, $self->url_for->to_abs];
  $self->res->code(200);
  $self->res->headers->content_type('text/plain');
  my $cb;
  $cb = sub {
    my $content = shift;
    my $chunk = shift @$chunks || '';
    $content->write_chunk($chunk, $chunk ? $cb : undef);
  };
  $self->res->content->$cb;
  $self->rendered;
};

get '/finished' => sub {
  my $self = shift;
  $self->on(finish => sub { shift->stash->{finished} *= 2 });
  $self->stash->{finished} = 1;
  $self->render(text => 'so far so good!');
};

get '/привет/мир' =>
  sub { shift->render(text => 'привет мир') };

get '/root.html' => 'root_path';

get '/root' => sub { shift->render(text => 'root fallback!') };

get '/template.txt' => {template => 'template', format => 'txt'};

get ':number' => [number => qr/0/] => sub {
  my $self    = shift;
  my $url     = $self->req->url->to_abs;
  my $address = $self->tx->remote_address;
  my $num     = $self->param('number');
  $self->render(text => "$url-$address-$num");
};

del '/inline/epl' => sub { shift->render(inline => '<%= 1 + 1 %> ☃') };

get '/inline/ep' =>
  sub { shift->render(inline => "<%= param 'foo' %>works!", handler => 'ep') };

get '/inline/ep/too' => sub { shift->render(inline => '0', handler => 'ep') };

get '/inline/ep/partial' => sub {
  my $self = shift;
  $self->stash(inline_template => "♥<%= 'just ♥' %>");
  $self->render(
    inline  => '<%= include inline => $inline_template %>works!',
    handler => 'ep'
  );
};

get '/source' => sub {
  my $self = shift;
  my $file = $self->param('fail') ? 'does_not_exist.txt' : '../lite_app.t';
  $self->render_maybe('this_does_not_ever_exist')
    or $self->render_static($file)
    or $self->res->headers->header('X-Missing' => 1);
};

get '/foo_relaxed/#test' => sub {
  my $self = shift;
  $self->render(
    text => $self->stash('test') . ($self->req->headers->dnt ? 1 : 0));
};

get '/foo_wildcard/(*test)' => sub {
  my $self = shift;
  $self->render(text => $self->stash('test'));
};

get '/foo_wildcard_too/*test' => sub {
  my $self = shift;
  $self->render(text => $self->stash('test'));
};

get '/with/header/condition' => (
  headers => {'X-Secret-Header'  => 'bar'},
  headers => {'X-Another-Header' => 'baz'}
) => 'with_header_condition';

post '/with/header/condition' => sub {
  my $self = shift;
  $self->render(
    text => 'foo ' . $self->req->headers->header('X-Secret-Header'));
} => (headers => {'X-Secret-Header' => 'bar'});

get '/session_cookie' => sub {
  my $self = shift;
  $self->render(text => 'Cookie set!');
  $self->res->cookies(
    Mojo::Cookie::Response->new(
      path  => '/session_cookie',
      name  => 'session',
      value => '23'
    )
  );
};

get '/session_cookie/2' => sub {
  my $self    = shift;
  my $session = $self->req->cookie('session');
  my $value   = $session ? $session->value : 'missing';
  $self->render(text => "Session is $value!");
};

get '/foo' => sub {
  my $self = shift;
  $self->render(text => 'Yea baby!');
};

get '/layout' => sub {
  shift->render(
    text    => 'Yea baby!',
    layout  => 'layout',
    handler => 'epl',
    title   => 'Layout'
  );
};

post '/template' => 'index';

any '/something' => sub {
  my $self = shift;
  $self->render(text => 'Just works!');
};

any [qw(get post)] => '/something/else' => sub {
  my $self = shift;
  $self->render(text => 'Yay!');
};

get '/regex/:test' => [test => qr/\d+/] => sub {
  my $self = shift;
  $self->render(text => $self->stash('test'));
};

post '/bar/:test' => {test => 'default'} => sub {
  my $self = shift;
  $self->render(text => $self->stash('test'));
};

patch '/firefox/:stuff' => (agent => qr/Firefox/) => sub {
  my $self = shift;
  $self->render(text => $self->url_for('foxy', {stuff => 'foo'}));
} => 'foxy';

get '/url_for_foxy' => sub {
  my $self = shift;
  $self->render(text => $self->url_for('foxy', stuff => '#test'));
};

post '/utf8' => 'form';

post '/malformed_utf8' => sub {
  my $self = shift;
  $self->render(text => b($self->param('foo'))->url_escape->to_string);
};

get '/json' => sub {
  shift->render(json => {foo => [1, -2, 3, 'b☃r']}, layout => 'layout');
};

get '/autostash' => sub { shift->render(handler => 'ep', foo => 'bar') };

get app => {layout => 'app'};

get '/helper' => sub { shift->render(handler => 'ep') } => 'helper';
app->helper(agent => sub { shift->req->headers->user_agent });

get '/eperror' => sub { shift->render(handler => 'ep') } => 'eperror';

get '/subrequest' => sub {
  my $self = shift;
  $self->render(text => $self->ua->post('/template')->success->body);
};

# Make sure hook runs non-blocking
hook after_dispatch => sub { shift->stash->{nb} = 'broken!' };

my $nb;
get '/subrequest_non_blocking' => sub {
  my $self = shift;
  $self->ua->post(
    '/template' => sub {
      my ($ua, $tx) = @_;
      $self->render(text => $tx->res->body . $self->stash->{nb});
      $nb = $self->stash->{nb};
    }
  );
  $self->stash->{nb} = 'success!';
};

get '/redirect_url' => sub {
  shift->redirect_to('http://127.0.0.1/foo')->render(text => 'Redirecting!');
};

get '/redirect_path' => sub {
  shift->redirect_to('/foo/bar?foo=bar')->render(text => 'Redirecting!');
};

get '/redirect_named' => sub {
  shift->redirect_to('index', format => 'txt')->render(text => 'Redirecting!');
};

get '/redirect_twice' => sub { shift->redirect_to('/redirect_named') };

get '/redirect_no_render' => sub {
  shift->redirect_to('index', {format => 'txt'});
};

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

get '/static_render' => sub { shift->render_static('hello.txt') };

app->types->type('koi8-r' => 'text/html; charset=koi8-r');
get '/koi8-r' => sub {
  app->renderer->encoding('koi8-r');
  shift->render('encoding', format => 'koi8-r', handler => 'ep');
  app->renderer->encoding(undef);
};

get '/captures/:foo/:bar' => sub {
  my $self = shift;
  $self->render(text => $self->url_for);
};

# Default condition
app->routes->add_condition(
  default => sub {
    my ($route, $c, $captures, $num) = @_;
    $captures->{test} = $captures->{text} . "$num works!";
    return 1 if $c->stash->{default} == $num;
    return undef;
  }
);

get '/default/:text' => (default => 23) => sub {
  my $self    = shift;
  my $default = $self->stash('default');
  my $test    = $self->stash('test');
  $self->render(text => "works $default $test");
};

# Redirect condition
app->routes->add_condition(
  redirect => sub {
    my ($route, $c, $captures, $active) = @_;
    return 1 unless $active;
    $c->redirect_to('index') and return undef
      unless $c->req->headers->header('X-Condition-Test');
    return 1;
  }
);

get '/redirect/condition/0' => (redirect => 0) => sub {
  shift->render(text => 'condition works!');
};

get '/redirect/condition/1' => (redirect => 1) =>
  {text => 'condition works too!'};

get '/url_with';

get '/url_with/:foo' => sub {
  my $self = shift;
  $self->render(text => $self->url_with({foo => 'bar'})->to_abs);
};

my $dynamic_inline = 1;
get '/dynamic/inline' => sub {
  my $self = shift;
  $self->render(inline => 'dynamic inline ' . $dynamic_inline++);
};

my $t = Test::Mojo->new;

# Application is already available
is $t->app->test_helper2, 'Mojolicious::Controller', 'right class';
is $t->app, app->commands->app, 'applications are equal';
is $t->app->moniker, 'lite_app', 'right moniker';
my $log = '';
my $cb = $t->app->log->on(message => sub { $log .= pop });
is $t->app->secret, $t->app->moniker, 'secret defaults to moniker';
like $log, qr/Your secret passphrase needs to be changed!!!/, 'right message';
$t->app->log->unsubscribe(message => $cb);

# Unicode snowman
$t->get_ok('/☃')->status_is(200)
  ->content_is('/%E2%98%83/%E2%98%83/%E2%98%83');

# Umlaut
$t->get_ok('/uni/aäb')->status_is(200)->content_is('/uni/a%C3%A4b');

# Escaped umlaut
$t->get_ok('/uni/a%E4b')->status_is(200)->content_is('/uni/a%C3%A4b');

# Escaped umlaut again
$t->get_ok('/uni/a%C3%A4b')->status_is(200)->content_is('/uni/a%C3%A4b');

# Captured snowman
$t->get_ok('/unicode/☃')->status_is(200)
  ->content_is('☃/unicode/%E2%98%83');

# Captured data with whitespace
$t->get_ok('/unicode/a b')->status_is(200)->content_is('a b/unicode/a%20b');

# Captured data with backslash
$t->get_ok('/unicode/a\\b')->status_is(200)->content_is('a\\b/unicode/a%5Cb');

# Root
$t->get_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# HEAD request
$t->head_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 55)->content_is('');

# HEAD request (lowercase)
my $tx = $t->ua->build_tx(head => '/');
$t->request_ok($tx)->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 55)->content_is('');

# Root with body
$t->get_ok('/', '1234' x 1024)->status_is(200)
  ->content_is("/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# DELETE request
$t->delete_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Hello!');

# POST request
$t->post_ok('/')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Bye!');

# Unicode alternatives
$t->get_ok('/alternatives/☃')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('/alternatives/%E2%98%83');

# Different unicode alternative
$t->get_ok('/alternatives/♥')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('/alternatives/%E2%99%A5');

# Invalid alternative
$t->get_ok('/alternatives/☃23')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Oops!\n");

# Invalid alternative
$t->get_ok('/alternatives')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Oops!\n");

# Invalid alternative
$t->get_ok('/alternatives/test')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Oops!\n");

# No format
$t->get_ok('/alterformat')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('json');

# Format alternative
$t->get_ok('/alterformat.json')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('json');

# Invalid format alternative
$t->get_ok('/alterformat.html')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Oops!\n");

# No format
$t->get_ok('/noformat')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('xml/noformat');

# Invalid format
$t->get_ok('/noformat.xml')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Oops!\n");

# "application/x-www-form-urlencoded"
$t->post_ok('/multipart/form' => form => {test => [1 .. 5]})->status_is(200)
  ->content_is(join "\n", 1 .. 5);

# "multipart/form-data"
$t->post_ok(
  '/multipart/form' => form => {test => [1 .. 5], file => {content => '123'}})
  ->status_is(200)->content_is(join "\n", 1 .. 5);

# Generated name
$t->get_ok('/auto_name')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('/custom_name');

# Query string roundtrip
$t->get_ok('/query_string?http://mojolicio.us/perldoc?foo=bar')
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('http://mojolicio.us/perldoc?foo=bar');

# Normal parameters
$t->get_ok('/multi/B?foo=A&baz=C')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('ABC');

# Injection attack
$t->get_ok('/multi/B?foo=A&foo=E&baz=C&yada=D&yada=text&yada=fail')
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('ABC');

# Missing parameter
$t->get_ok('/multi/B?baz=C')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('BC');

# Reserved stash value
$t->get_ok('/reserved?data=just-works')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('just-worksdata');

# More reserved stash values
$t->get_ok('/reserved?data=just-works&json=test')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('just-worksdata,json');

# Exception in inline template
$t->get_ok('/inline/exception')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Died at inline template line 1.\n\n");

# Exception in template from data section
$t->get_ok('/data/exception')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Died at template dies.html.ep from DATA section line 2.\n\n");

# Exception in template
$t->get_ok('/template/exception')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("Died at template dies_too.html.ep line 2.\n\n");

# Generate URL without format
$t->get_ok('/with-format')->content_is("/without-format\n");
$t->get_ok('/without-format')->content_is("/without-format\n");
$t->get_ok('/without-format.html')->content_is("/without-format\n");

# JSON response
$t->get_ok('/json_too')->status_is(200)->json_is({hello => 'world'});

# Static inline file
$t->get_ok('/static.txt')->status_is(200)
  ->header_is(Server          => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->content_is("Just some\ntext!\n\n");

# Partial inline file
$t->get_ok('/static.txt' => {Range => 'bytes=2-5'})->status_is(206)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Accept-Ranges' => 'bytes')->header_is('Content-Length' => 4)
  ->content_is('st s');

# Protected DATA template
$t->get_ok('/template.txt.epl')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# Captured "0"
$t->get_ok('/null/0')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/layouted 0/);

# Render action
$t->get_ok('/action_template')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("controller and action!\n");

# Dead action
$t->get_ok('/dead')->status_is(500)->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/works!/);

# Dead renderer
$t->get_ok('/dead_renderer')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/renderer works!/);

# Dead renderer with auto rendering
$t->get_ok('/dead_auto_renderer')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/renderer works!/);

# Dead template
$t->get_ok('/dead_template')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/works too!/);

# Regex in name
$t->get_ok('/regex/in/template')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("test(test)(\\Qtest\\E)(\n");

# Chunked response with basic auth
my $url = $t->ua->server->url->userinfo('sri:foo')->path('/stream')
  ->query(foo => 'bar');
$t->get_ok($url)->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr!^foobarsri:foohttp://localhost:\d+/stream$!);

# Not ajax
$t->get_ok('/maybe/ajax')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('not ajax');

# Ajax
$t->get_ok('/maybe/ajax' => {'X-Requested-With' => 'XMLHttpRequest'})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('is ajax');

# With finish event
my $stash;
$t->app->plugins->once(before_dispatch => sub { $stash = shift->stash });
$t->get_ok('/finished')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('so far so good!');
is $stash->{finished}, 2, 'finish event has been emitted once';

# IRI
$t->get_ok('/привет/мир')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is('привет мир');

# Route with format
$t->get_ok('/root.html')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("/\n");

# Fallback route without format
$t->get_ok('/root')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('root fallback!');
$t->get_ok('/root.txt')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('root fallback!');

# Root with format
$t->get_ok('/.html')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");

# "X-Forwarded-For"
$t->get_ok('/0' => {'X-Forwarded-For' => '192.0.2.2, 192.0.2.1'})
  ->status_is(200)->content_like(qr!^http://localhost:\d+/0-!)
  ->content_like(qr/-0$/)->content_unlike(qr!-192\.0\.2\.1-0$!);

# "X-Forwarded-HTTPS"
$t->get_ok('/0' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
  ->content_like(qr!^http://localhost:\d+/0-!)->content_like(qr/-0$/)
  ->content_unlike(qr!-192\.0\.2\.1-0$!);

# Reverse proxy with "X-Forwarded-For"
{
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  $t->get_ok('/0' => {'X-Forwarded-For' => '192.0.2.2, 192.0.2.1'})
    ->status_is(200)->content_like(qr!http://localhost:\d+/0-192\.0\.2\.1-0$!);
}

# Reverse proxy with "X-Forwarded-HTTPS"
{
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  $t->get_ok('/0' => {'X-Forwarded-HTTPS' => 1})->status_is(200)
    ->content_like(qr!^https://localhost:\d+/0-!)->content_like(qr/-0$/)
    ->content_unlike(qr!-192\.0\.2\.1-0$!);
}

# Inline "epl" template
$t->delete_ok('/inline/epl')->status_is(200)->content_is("2 ☃\n");

# Inline "ep" template
$t->get_ok('/inline/ep?foo=bar')->status_is(200)->content_is("barworks!\n");

# Inline "ep" template "0"
$t->get_ok('/inline/ep/too')->status_is(200)->content_is("0\n");

# Inline template with partial
$t->get_ok('/inline/ep/partial')->status_is(200)
  ->content_is("♥just ♥\nworks!\n");

# Render static file outside of public directory
$t->get_ok('/source')->status_is(200)->header_isnt('X-Missing' => 1)
  ->content_like(qr!get_ok\('/source!);

# File does not exist
$log = '';
$cb = $t->app->log->on(message => sub { $log .= pop });
$t->get_ok('/source?fail=1')->status_is(404)->header_is('X-Missing' => 1)
  ->content_is("Oops!\n");
like $log, qr/File "does_not_exist.txt" not found, public directory missing\?/,
  'right message';
$t->app->log->unsubscribe(message => $cb);

# With body and max message size
{
  local $ENV{MOJO_MAX_MESSAGE_SIZE} = 1024;
  $t->get_ok('/', '1234' x 1024)->status_is(413)
    ->header_is(Connection => 'close')
    ->content_is(
    "/root.html\n/root.html\n/root.html\n/root.html\n/root.html\n");
}

# Relaxed placeholder
$t->get_ok('/foo_relaxed/123')->status_is(200)->content_is('1230');
$t->get_ok('/foo_relaxed/123' => {DNT => 1})->status_is(200)
  ->content_is('1231');
$t->get_ok('/foo_relaxed/')->status_is(404);

# Wildcard placeholder
$t->get_ok('/foo_wildcard/123')->status_is(200)->content_is('123');
$t->get_ok('/foo_wildcard/IQ==%0A')->status_is(200)->content_is("IQ==\x0a");
$t->get_ok('/foo_wildcard/')->status_is(404);
$t->get_ok('/foo_wildcard_too/123')->status_is(200)->content_is('123');
$t->get_ok('/foo_wildcard_too/')->status_is(404);

# Header conditions
$t->get_ok('/with/header/condition',
  {'X-Secret-Header' => 'bar', 'X-Another-Header' => 'baz'})->status_is(200)
  ->content_is("Test ok!\n");

# Missing headers
$t->get_ok('/with/header/condition')->status_is(404)->content_like(qr/Oops!/);

# Missing header
$t->get_ok('/with/header/condition' => {'X-Secret-Header' => 'bar'})
  ->status_is(404)->content_like(qr/Oops!/);

# Single header condition
$t->post_ok('/with/header/condition' => {'X-Secret-Header' => 'bar'} => 'bar')
  ->status_is(200)->content_is('foo bar');

# Missing header
$t->post_ok('/with/header/condition' => {} => 'bar')->status_is(404)
  ->content_like(qr/Oops!/);

# Session cookie
$t->get_ok('/session_cookie')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Cookie set!');
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Session is 23!');
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Session is 23!');

# Session reset
$t->reset_session;
ok !$t->tx, 'session reset';
$t->get_ok('/session_cookie/2')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Session is missing!');

# Text
$t->get_ok('/foo')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Yea baby!');

# Template
$t->post_ok('/template')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Just works!');

# All methods
$t->get_ok('/something')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Just works!');
$t->post_ok('/something')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Just works!');
$t->delete_ok('/something')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Just works!');

# Only GET and POST
$t->get_ok('/something/else')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Yay!');
$t->post_ok('/something/else')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Yay!');
$t->delete_ok('/something/else')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# Regex constraint
$t->get_ok('/regex/23')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('23');
$t->get_ok('/regex/foo')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# Default value
$t->post_ok('/bar')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('default');
$t->post_ok('/bar/baz')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('baz');

# Layout
$t->get_ok('/layout')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("LayoutYea baby! with layout\n");

# User agent condition
$t->patch_ok('/firefox/bar' => {'User-Agent' => 'Firefox'})->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('/firefox/foo');
$t->patch_ok('/firefox/bar' => {'User-Agent' => 'Explorer'})->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# URL for route with condition
$t->get_ok('/url_for_foxy')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('/firefox/%23test');

# UTF-8 form
$t->post_ok('/utf8' => form => {name => 'табак'} => charset => 'UTF-8')
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 22)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("табак ангел\n");

# UTF-8 "multipart/form-data" form
$t->post_ok('/utf8' => {'Content-Type' => 'multipart/form-data'} => form =>
    {name => 'табак'} => charset => 'UTF-8')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 22)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is("табак ангел\n");

# Malformed UTF-8
$t->post_ok('/malformed_utf8' =>
    {'Content-Type' => 'application/x-www-form-urlencoded'} => 'foo=%E1')
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('%E1');

# JSON
$t->get_ok('/json')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_type_is('application/json')->json_is({foo => [1, -2, 3, 'b☃r']})
  ->json_is('/foo' => [1, -2, 3, 'b☃r'])->json_is('/foo/3', 'b☃r')
  ->json_has('/foo')->json_hasnt('/bar');

# Stash values in template
$t->get_ok('/autostash?bar=23')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("layouted bar\n23\n42\nautostash\n\n");

# Route without slash
$t->get_ok('/app')->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("app layout app23\ndevelopment\n");

# Helper
$t->get_ok('/helper')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("23\n<br>\n&lt;...\n/template\n(Mojolicious (Perl))");
$t->get_ok('/helper' => {'User-Agent' => 'Explorer'})->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is("23\n<br>\n&lt;...\n/template\n(Explorer)");

# Exception in EP template
$t->get_ok('/eperror')->status_is(500)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/\$c/);

# Subrequest
$t->get_ok('/subrequest')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Just works!');
$t->get_ok('/subrequest')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('Just works!');

# Non-blocking subrequest
$t->get_ok('/subrequest_non_blocking')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('Just works!success!');
is $nb, 'broken!', 'right text';

# Redirect to URL
$t->get_ok('/redirect_url')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_is(Location => 'http://127.0.0.1/foo')->content_is('Redirecting!');

# Redirect to path
$t->get_ok('/redirect_path')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_like(Location => qr!/foo/bar\?foo=bar$!)
  ->content_is('Redirecting!');

# Redirect to named route
$t->get_ok('/redirect_named')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 12)
  ->header_like(Location => qr!/template.txt$!)->content_is('Redirecting!');

# Redirect twice
$t->ua->max_redirects(3);
$t->get_ok('/redirect_twice')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->text_is('div#☃' => 'Redirect works!');
my $redirects = $t->tx->redirects;
is scalar @$redirects, 2, 'two redirects';
is $redirects->[0]->req->url->path, '/redirect_twice', 'right path';
is $redirects->[1]->req->url->path, '/redirect_named', 'right path';
$t->ua->max_redirects(0);

# Redirect without rendering
$t->get_ok('/redirect_no_render')->status_is(302)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 0)
  ->header_like(Location => qr!/template.txt$!)->content_is('');

# Non-blocking redirect
$t->get_ok('/redirect_callback')->status_is(301)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 9)
  ->header_is(Location => 'http://127.0.0.1/foo')->content_is('Whatever!');

# Static file
$t->get_ok('/static_render')->status_is(200)
  ->header_is(Server           => 'Mojolicious (Perl)')
  ->header_is('Content-Length' => 31)
  ->content_is("Hello Mojo from a static file!\n");

# Redirect to named route with redirecting enabled in user agent
$t->ua->max_redirects(3);
$t->get_ok('/redirect_named')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->header_is(Location => undef)
  ->element_exists('#☃')->element_exists_not('#foo')
  ->text_isnt('#foo' => 'whatever')->text_isnt('div#☃' => 'Redirect')
  ->text_is('div#☃' => 'Redirect works!')->text_unlike('div#☃' => qr/Foo/)
  ->text_like('div#☃' => qr/^Redirect/);
$t->ua->max_redirects(0);
Test::Mojo->new->tx($t->tx->previous)->status_is(302)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like(Location => qr!/template.txt$!)->content_is('Redirecting!');

# Request with koi8-r content
my $koi8
  = 'Этот человек наполняет меня надеждой.'
  . ' Ну, и некоторыми другими глубокими и приводящими в'
  . ' замешательство эмоциями.';
$t->get_ok('/koi8-r')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_type_is('text/html; charset=koi8-r')->content_like(qr/^$koi8/);

# Custom condition
$t->get_ok('/default/condition')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('works 23 condition23 works!');

# Redirect from condition
$t->get_ok('/redirect/condition/0')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('condition works!');
$t->get_ok('/redirect/condition/1')->status_is(302)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_like('Location' => qr!/template$!)->content_is('');
$t->get_ok('/redirect/condition/1' => {'X-Condition-Test' => 1})
  ->status_is(200)->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('condition works too!');

# Multiple placeholders
$t->get_ok('/captures/foo/bar')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('/captures/foo/bar');
$t->get_ok('/captures/bar/baz')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('/captures/bar/baz');
$t->get_ok('/captures/♥/☃')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('/captures/%E2%99%A5/%E2%98%83');
is b($t->tx->res->body)->url_unescape->decode('UTF-8'), '/captures/♥/☃',
  'right result';

# Bundled file in DATA section
$t->get_ok('/favicon.ico')->status_is(200)->content_is("Not a favicon!\n\n");

# Generate URL with query parameters
$t->get_ok('/url_with?foo=23&bar=24&baz=25')->status_is(200)
  ->content_is(<<EOF);
/url_with?bar=24&baz=25&foo=bar
http://mojolicio.us/test?foo=23&bar=24&baz=25
/test?bar=24&baz=25
/bar/23?bar=24&baz=25&foo=yada
EOF
$t->get_ok('/url_with/foo?foo=bar')->status_is(200)
  ->content_like(qr!http://localhost:\d+/url_with/bar\?foo\=bar!);

# Dynamic inline template
$t->get_ok('/dynamic/inline')->status_is(200)
  ->content_is("dynamic inline 1\n");
$t->get_ok('/dynamic/inline')->status_is(200)
  ->content_is("dynamic inline 2\n");

done_testing();

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

@@ with_header_condition.html.ep
Test ok!

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
