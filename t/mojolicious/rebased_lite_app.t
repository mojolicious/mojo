use Mojo::Base -strict;

BEGIN { $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll' }

use Test::More;
use Mojo::URL;
use Mojolicious::Lite;
use Test::Mojo;

# Rebase hook
app->hook(
  before_dispatch => sub {
    my $c = shift;
    $c->req->url->base(Mojo::URL->new('http://example.com/rebased/'));
    $c->req->url->path->leading_slash(0);
  }
);

# Current route hook
app->hook(
  after_dispatch => sub {
    my $c = shift;
    $c->res->headers->header('X-Route' => $c->current_route);
  }
);

get '/' => 'root';

get '/foo';

get '/bar' => sub {
  my $c = shift;
  $c->flash(just => 'works!')->flash({works => 'too!'});
  $c->redirect_to($c->url_for('foo'));
};

get '/baz' => sub { shift->render('root') };

my $t = Test::Mojo->new;

# Rebased root
$t->get_ok('/')->status_is(200)->header_is('X-Route' => 'root')
  ->content_is(<<'EOF');
http://example.com/rebased/
<script src="/rebased/mojo/jquery/jquery.js"></script>
<img src="/rebased/images/test.png">
<link href="//example.com/base.css" rel="stylesheet">
<a href="mailto:sri@example.com">Contact</a>
http://example.com/rebased
http://example.com/rebased/foo
/rebased/foo
http://example.com/
root
  Welcome to the root!
EOF

# Rebased route
$t->get_ok('/foo')->status_is(200)->header_is('X-Route' => 'foo')
  ->content_is(<<EOF);
http://example.com/rebased/
<link href="/rebased/b.css" media="test" rel="stylesheet">
<img alt="Test" src="/rebased/images/test.png">
http://example.com/rebased/foo
http://example.com/rebased
/rebased
http://example.com/
foo
EOF

# Rebased route with flash
ok !$t->ua->cookie_jar->find($t->ua->server->url->path('/foo')),
  'no session cookie';
$t->get_ok('/bar')->status_is(302)->header_is('X-Route' => 'bar')
  ->header_is(Location => '/rebased/foo');
ok $t->ua->cookie_jar->find($t->ua->server->url->path('/foo')),
  'session cookie';

# Rebased route with message from flash
$t->get_ok('/foo')->status_is(200)->content_is(<<EOF);
http://example.com/rebased/works!too!
<link href="/rebased/b.css" media="test" rel="stylesheet">
<img alt="Test" src="/rebased/images/test.png">
http://example.com/rebased/foo
http://example.com/rebased
/rebased
http://example.com/
foo
EOF

# Rebased route sharing a template
$t->get_ok('/baz')->status_is(200)->header_is('X-Route' => 'baz')
  ->content_is(<<'EOF');
http://example.com/rebased/
<script src="/rebased/mojo/jquery/jquery.js"></script>
<img src="/rebased/images/test.png">
<link href="//example.com/base.css" rel="stylesheet">
<a href="mailto:sri@example.com">Contact</a>
http://example.com/rebased/baz
http://example.com/rebased/foo
/rebased/foo
http://example.com/
baz
EOF

# Does not exist
$t->get_ok('/yada')->status_is(404)->header_is('X-Route' => '');

done_testing();

__DATA__
@@ root.html.ep
%= $c->req->url->base
%= javascript '/mojo/jquery/jquery.js'
%= image '/images/test.png'
%= stylesheet '//example.com/base.css'
%= link_to Contact => 'mailto:sri@example.com'
%= $c->req->url->to_abs
%= url_for('foo')->to_abs
%= url_for 'foo'
%= url_for('foo')->base
%= current_route
% if (current_route 'root') {
  Welcome to the root!
% }

@@ foo.html.ep
<%= $c->req->url->base %><%= flash 'just' || '' %><%= flash 'works' || '' %>
%= stylesheet '/b.css', media => 'test'
%= image '/images/test.png', alt => 'Test'
%= $c->req->url->to_abs
%= url_for('root')->to_abs
%= url_for 'root'
%= url_for('root')->base
%= current_route
