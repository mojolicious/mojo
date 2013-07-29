use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::ByteStream 'b';
use Mojo::UserAgent::CookieJar;
use Mojolicious::Lite;
use Test::Mojo;

get '/expiration' => sub {
  my $self = shift;
  if ($self->param('redirect')) {
    $self->session(expiration => 0);
    return $self->redirect_to('expiration');
  }
  $self->render(text => $self->session('expiration'));
};

under sub {
  my $self = shift;
  return undef unless $self->req->headers->header('X-Bender');
  $self->res->headers->add('X-Under' => 23);
  $self->res->headers->add('X-Under' => 24);
  1;
};

get '/with_under' => sub {
  my $self = shift;
  $self->render(text => 'Unders are cool!');
};

get '/with_under_too' => sub {
  my $self = shift;
  $self->render(text => 'Unders are cool too!');
};

under sub {
  my $self = shift;

  # Authenticated
  my $name = $self->param('name') || '';
  return 1 if $name eq 'Bender';

  # Not authenticated
  $self->render('param_auth_denied');
  return undef;
};

get '/param_auth';

get '/param_auth/too' =>
  sub { shift->render(text => 'You could be Bender too!') };

under sub {
  my $self = shift;
  $self->stash(_name => 'stash');
  $self->cookie(foo => 'cookie', {expires => time + 60});
  $self->signed_cookie(bar => 'signed_cookie', {expires => time + 120});
  $self->cookie(bad => 'bad_cookie--12345678');
  1;
};

get '/bridge2stash' =>
  sub { shift->render(template => 'bridge2stash', handler => 'ep') };

# Make sure after_dispatch can make session changes
hook after_dispatch => sub {
  my $c = shift;
  return unless $c->req->url->path->contains('/late/session');
  $c->session(late => 'works!');
};

get '/late/session' => sub {
  my $self = shift;
  my $late = $self->session('late') || 'not yet!';
  $self->render(text => $late);
};

# Counter
my $under;
under sub {
  shift->res->headers->header('X-Under' => ++$under);
  1;
};

get '/with/under/count';

# Everything gets past this
under sub {
  shift->res->headers->header('X-Possible' => 1);
  1;
};

get '/possible' => 'possible';

# Nothing gets past this
under sub {
  shift->res->headers->header('X-Impossible' => 1);
  0;
};

get '/impossible' => 'impossible';

# Prefix
under '/prefix';

get sub { shift->render(text => 'prefixed GET works!') };

post sub { shift->render(text => 'prefixed POST works!') };

get '/works' => sub { shift->render(text => 'prefix works!') };

under '/prefix2' => {message => 'prefixed'};

get '/foo' => {inline => '<%= $message %>!'};

get '/bar' => {inline => 'also <%= $message %>!'};

# Reset
under '/' => {foo => 'one'};

get '/reset' => {text => 'reset works!'};

# Group
group {

  under '/group' => {bar => 'two'};

  get {inline => '<%= $foo %><%= $bar %>!'};

  # Nested group
  group {

    under '/nested' => {baz => 'three'};

    get {inline => '<%= $baz %><%= $bar %><%= $foo %>!'};

    get '/whatever' => {inline => '<%= $foo %><%= $bar %><%= $baz %>!'};
  };
};

# Authentication group
group {

  # Check "ok" parameter
  under sub {
    my $self = shift;
    return 1 if $self->req->param('ok');
    $self->render(text => "You're not ok.");
    return undef;
  };

  get '/authgroup' => {text => "You're ok."};
};

get '/noauthgroup' => {inline => 'Whatever <%= $foo %>.'};

# Disable format detection
under [format => 0];

get '/no_format' => {text => 'No format detection.'};

get '/some_formats' => [format => [qw(txt json)]] =>
  {text => 'Some format detection.'};

get '/no_real_format.xml' => {text => 'No real format.'};

get '/one_format' => [format => 'xml'] => {text => 'One format.'};

my $t = Test::Mojo->new;

# Preserve stash
my $stash;
$t->app->hook(after_dispatch => sub { $stash = shift->stash });

# Zero expiration persists
$t->ua->max_redirects(1);
$t->get_ok('/expiration?redirect=1')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('0');
ok !$t->tx->res->cookie('mojolicious')->expires, 'no expiration';
$t->reset_session;

# Authenticated with header
$t->get_ok('/with_under' => {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Under' => '23, 24')->header_like('X-Under' => qr/23, 24/)
  ->content_is('Unders are cool!');

# Authenticated with header too
$t->get_ok('/with_under_too' => {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Under' => '23, 24')->header_like('X-Under' => qr/23, 24/)
  ->content_is('Unders are cool too!');

# Not authenticated with header
$t->get_ok('/with_under_too')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')->content_like(qr/Oops!/);

# Not authenticated with parameter
$t->get_ok('/param_auth')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Not Bender!\n");
is $stash->{_name}, undef, 'no "_name" value';

# Authenticated with parameter
$t->get_ok('/param_auth?name=Bender')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Bender!\n");

# Not authenticated with parameter
$t->get_ok('/param_auth/too')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is("Not Bender!\n");

# Authenticated with parameter too
$t->get_ok('/param_auth/too?name=Bender')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('You could be Bender too!');

# No cookies, session or flash
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!\n");
ok $t->tx->res->cookie('mojolicious')->expires, 'has expiration';
is $stash->{_name}, 'stash', 'right "_name" value';

# Cookies, session and flash
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!\n");
ok $t->tx->res->cookie('mojolicious')->httponly,
  'session cookie has HttpOnly flag';

# Broken session cookie
$t->reset_session;
my $session = b("☃☃☃☃☃")->encode->b64_encode('');
my $hmac    = $session->clone->hmac_sha1_sum($t->app->secret);
$t->get_ok('/bridge2stash' => {Cookie => "mojolicious=$session--$hmac"})
  ->status_is(200)->content_is("stash too!!!!!!!\n");

# Without cookie jar
$t->ua->cookie_jar(0);
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!\n");

# Again without cookie jar
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!\n");
$t->reset_session->ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

# Fresh start without cookies, session or flash
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!\n");

# Random static requests
$t->get_ok('/mojo/logo-white.png')->status_is(200);
$t->get_ok('/mojo/logo-black.png')->status_is(200);
$t->get_ok('/mojo/logo-white.png')->status_is(200);
$t->get_ok('/mojo/logo-black.png')->status_is(200);

# With cookies, session and flash again
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!\n");

# With cookies and session but no flash
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!\n");
ok $t->tx->res->cookie('mojolicious')->expires->epoch < time,
  'session cookie expires';

# With cookies and session cleared
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is("stash too!cookie!signed_cookie!!bad_cookie--12345678!!!\n");

# Late session does not affect rendering
$t->get_ok('/late/session')->status_is(200)->content_is('not yet!');

# Previous late session does affect rendering
$t->get_ok('/late/session')->status_is(200)->content_is('works!');

# Previous late session does affect rendering again
$t->get_ok('/late/session')->status_is(200)->content_is('works!');

# Counter
$t->get_ok('/with/under/count' => {'X-Bender' => 'Rodriguez'})->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->header_is('X-Under' => 1)
  ->content_is("counter\n");
is $stash->{_name}, undef, 'no "_name" value';

# Cookies, session and no flash again
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!\n");

# With cookies, session and flash
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!\n");

# With cookies and session but no flash
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!\n");

# Reachable route
$t->get_ok('/possible')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->header_is('X-Possible' => 1)
  ->header_is('X-Impossible' => undef)->content_is("Possible!\n");

# Unreachable route
$t->get_ok('/impossible')->status_is(404)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->header_is('X-Possible' => undef)->header_is('X-Impossible' => 1)
  ->content_is("Oops!\n");

# Prefix
$t->get_ok('/prefix')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('prefixed GET works!');

# POST request with prefix
$t->post_ok('/prefix')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_is('prefixed POST works!');

# GET request with prefix
$t->get_ok('/prefix/works')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')->content_is('prefix works!');

# Another prefix
$t->get_ok('/prefix2/foo')->status_is(200)->content_is("prefixed!\n");

# Another prefix again
$t->get_ok('/prefix2/bar')->status_is(200)->content_is("also prefixed!\n");

# Reset under statements
$t->get_ok('/reset')->status_is(200)->content_is('reset works!');

# Not reachable with prefix
$t->get_ok('/prefix/reset')->status_is(404);

# Group
$t->get_ok('/group')->status_is(200)->content_is("onetwo!\n");

# Nested group
$t->get_ok('/group/nested')->status_is(200)->content_is("threetwoone!\n");

# GET request to nested group
$t->get_ok('/group/nested/whatever')->status_is(200)
  ->content_is("onetwothree!\n");

# Another GET request to nested group
$t->get_ok('/group/nested/something')->status_is(404);

# Authenticated by group
$t->get_ok('/authgroup?ok=1')->status_is(200)->content_is("You're ok.");

# Not authenticated by group
$t->get_ok('/authgroup')->status_is(200)->content_is("You're not ok.");

# Bypassed group authentication
$t->get_ok('/noauthgroup')->status_is(200)->content_is("Whatever one.\n");

# Disabled format detection
$t->get_ok('/no_format')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')
  ->content_is('No format detection.');

# Invalid format
$t->get_ok('/no_format.txt')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

# Invalid format
$t->get_ok('/some_formats')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

# Format "txt" has been detected
$t->get_ok('/some_formats.txt')->status_is(200)->content_type_is('text/plain')
  ->content_is('Some format detection.');

# Format "json" has been detected
$t->get_ok('/some_formats.json')->status_is(200)
  ->content_type_is('application/json')->content_is('Some format detection.');

# Invalid format
$t->get_ok('/some_formats.xml')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

# Invalid format
$t->get_ok('/no_real_format')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

# No format detected
$t->get_ok('/no_real_format.xml')->status_is(200)
  ->content_type_is('text/html;charset=UTF-8')->content_is('No real format.');

# Invalid format
$t->get_ok('/no_real_format.txt')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

# Invalid format
$t->get_ok('/one_format')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

# Format "xml" detected
$t->get_ok('/one_format.xml')->status_is(200)
  ->content_type_is('application/xml')->content_is('One format.');

# Invalid format
$t->get_ok('/one_format.txt')->status_is(404)
  ->content_type_is('text/html;charset=UTF-8');

done_testing();

__DATA__
@@ not_found.html.epl
Oops!

@@ param_auth.html.epl
Bender!

@@ param_auth_denied.html.epl
Not Bender!

@@ bridge2stash.html.ep
% my $cookie = $self->req->cookie('mojolicious');
<%= stash('_name') %> too!<%= $self->cookie('foo') %>!\
<%= $self->signed_cookie('bar')%>!<%= $self->signed_cookie('bad')%>!\
<%= $self->cookie('bad') %>!<%= session 'foo' %>!\
<%= flash 'foo' %>!
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
