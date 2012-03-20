use Mojo::Base -strict;

use utf8;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor';
}

use Test::More tests => 154;

# "Let's see how crazy I am now, Nixon. The correct answer is very."
use Mojo::ByteStream 'b';
use Mojolicious::Lite;
use Test::Mojo;

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
  return;
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
  sub { shift->render(template => 'bridge2stash', handler => 'ep') };

# Make sure after_dispatch can make session changes
hook after_dispatch => sub {
  my $self = shift;
  return unless $self->req->url->path->contains('/late/session');
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

# /prefix (prefix)
under '/prefix';

# GET /prefix
get sub { shift->render(text => 'prefixed GET works!') };

# POST /prefix
post sub { shift->render(text => 'prefixed POST works!') };

# GET /prefix/works
get '/works' => sub { shift->render(text => 'prefix works!') };

# /prefix2 (another prefix)
under '/prefix2' => {message => 'prefixed'};

# GET /prefix2/foo
get '/foo' => {inline => '<%= $message %>!'};

# GET /prefix2/bar
get '/bar' => {inline => 'also <%= $message %>!'};

# Reset
under '/' => {foo => 'one'};

# GET /reset
get '/reset' => {text => 'reset works!'};

# Group
group {

  # /group
  under '/group' => {bar => 'two'};

  # GET /group
  get {inline => '<%= $foo %><%= $bar %>!'};

  # Nested group
  group {

    # /group/nested
    under '/nested' => {baz => 'three'};

    # GET /group/nested
    get {inline => '<%= $baz %><%= $bar %><%= $foo %>!'};

    # GET /group/nested/whatever
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
    return;
  };

  # GET /authgroup
  get '/authgroup' => {text => "You're ok."};
};

# GET /noauthgroup
get '/noauthgroup' => {inline => 'Whatever <%= $foo %>.'};

my $t = Test::Mojo->new;

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

# GET /bridge2stash
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!\n");

# GET /bridge2stash (with cookies, session and flash)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!\n");
ok $t->tx->res->cookie('mojolicious')->httponly,
  'session cookie has HttpOnly flag';

# GET /bridge2stash (broken session cookie)
$t->reset_session;
my $session = b("☃☃☃☃☃")->encode->b64_encode('');
my $hmac    = $session->clone->hmac_md5_sum($t->app->secret);
my $broken  = "\$Version=1; mojolicious=$session--$hmac; \$Path=/";
$t->get_ok('/bridge2stash' => {Cookie => $broken})->status_is(200)
  ->content_is("stash too!!!!!!!\n");

# GET /bridge2stash (fresh start)
$t->reset_session;
$t->get_ok('/bridge2stash' => {'X-Flash' => 1})->status_is(200)
  ->content_is("stash too!!!!!!!\n");

# GET /mojolicious-white.png
# GET /mojolicious-black.png
# (random static requests)
$t->get_ok('/mojolicious-white.png')->status_is(200);
$t->get_ok('/mojolicious-black.png')->status_is(200);
$t->get_ok('/mojolicious-white.png')->status_is(200);
$t->get_ok('/mojolicious-black.png')->status_is(200);

# GET /bridge2stash (with cookies, session and flash again)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!\n");

# GET /bridge2stash (with cookies and session but no flash)
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!\n");
ok $t->tx->res->cookie('mojolicious')->expires->epoch < time,
  'session cookie expires';

# GET /bridge2stash (with cookies and session cleared)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is("stash too!cookie!signed_cookie!!bad_cookie--12345678!!!\n");

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
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!\n");

# GET /bridge2stash (with cookies, session and flash)
$t->get_ok('/bridge2stash')->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!flash!\n");

# GET /bridge2stash (with cookies and session but no flash)
$t->get_ok('/bridge2stash' => {'X-Flash2' => 1})->status_is(200)
  ->content_is(
  "stash too!cookie!signed_cookie!!bad_cookie--12345678!session!!\n");

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

# GET /prefix2/foo
$t->get_ok('/prefix2/foo')->status_is(200)->content_is("prefixed!\n");

# GET /prefix2/bar
$t->get_ok('/prefix2/bar')->status_is(200)->content_is("also prefixed!\n");

# GET /reset
$t->get_ok('/reset')->status_is(200)->content_is('reset works!');

# GET /prefix/reset
$t->get_ok('/prefix/reset')->status_is(404);

# GET /group
$t->get_ok('/group')->status_is(200)->content_is("onetwo!\n");

# GET /group/nested
$t->get_ok('/group/nested')->status_is(200)->content_is("threetwoone!\n");

# GET /group/nested/whatever
$t->get_ok('/group/nested/whatever')->status_is(200)
  ->content_is("onetwothree!\n");

# GET /group/nested/something
$t->get_ok('/group/nested/something')->status_is(404);

# GET /authgroup?ok=1
$t->get_ok('/authgroup?ok=1')->status_is(200)->content_is("You're ok.");

# GET /authgroup
$t->get_ok('/authgroup')->status_is(200)->content_is("You're not ok.");

# GET /noauthgroup
$t->get_ok('/noauthgroup')->status_is(200)->content_is("Whatever one.\n");

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
