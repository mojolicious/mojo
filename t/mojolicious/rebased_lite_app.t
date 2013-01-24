use Mojo::Base -strict;

# Disable IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;
use Mojo::URL;
use Mojolicious::Lite;
use Test::Mojo;

# Rebase hook
app->hook(
  before_dispatch => sub {
    shift->req->url->base(Mojo::URL->new('http://kraih.com/rebased/'));
  }
);

# Current route hook
app->hook(
  after_dispatch => sub {
    my $self = shift;
    $self->res->headers->header('X-Route' => $self->current_route);
  }
);

get '/' => 'root';

get '/foo';

get '/bar' => sub {
  my $self = shift;
  $self->flash(just => 'works!')->flash({works => 'too!'});
  $self->redirect_to($self->url_for('foo'));
};

get '/baz' => sub { shift->render('root') };

my $t = Test::Mojo->new;

# Rebased root
$t->get_ok('/')->status_is(200)->header_is('X-Route' => 'root')
  ->content_is(<<EOF);
http://kraih.com/rebased/
<script src="/rebased/mojo/jquery/jquery.js"></script>
<img src="/rebased/images/test.png" />
http://kraih.com/rebased/foo
/rebased/foo
http://kraih.com/
root
  Welcome to the root!
EOF

# Rebased route
$t->get_ok('/foo')->status_is(200)->header_is('X-Route' => 'foo')
  ->content_is(<<EOF);
http://kraih.com/rebased/
<link href="/rebased/b.css" media="test" rel="stylesheet" />
<img alt="Test" src="/rebased/images/test.png" />
http://kraih.com/rebased
/rebased
http://kraih.com/
foo
EOF

# Rebased route with flash
ok !$t->ua->cookie_jar->find($t->ua->app_url->path('/foo')),
  'no session cookie';
$t->get_ok('/bar')->status_is(302)->header_is('X-Route' => 'bar')
  ->header_is(Location => 'http://kraih.com/rebased/foo');
ok $t->ua->cookie_jar->find($t->ua->app_url->path('/foo')), 'session cookie';

# Rebased route with message from flash
$t->get_ok('/foo')->status_is(200)->content_is(<<EOF);
http://kraih.com/rebased/works!too!
<link href="/rebased/b.css" media="test" rel="stylesheet" />
<img alt="Test" src="/rebased/images/test.png" />
http://kraih.com/rebased
/rebased
http://kraih.com/
foo
EOF

# Rebased route sharing a template
$t->get_ok('/baz')->status_is(200)->header_is('X-Route' => 'baz')
  ->content_is(<<EOF);
http://kraih.com/rebased/
<script src="/rebased/mojo/jquery/jquery.js"></script>
<img src="/rebased/images/test.png" />
http://kraih.com/rebased/foo
/rebased/foo
http://kraih.com/
baz
EOF

# Does not exist
$t->get_ok('/yada')->status_is(404)->header_is('X-Route' => '');

done_testing();

__DATA__
@@ root.html.ep
%= $self->req->url->base
%= javascript '/mojo/jquery/jquery.js'
%= image '/images/test.png'
%= url_for('foo')->to_abs
%= url_for 'foo'
%= url_for('foo')->base
%= current_route
% if (current_route 'root') {
  Welcome to the root!
% }

@@ foo.html.ep
<%= $self->req->url->base %><%= flash 'just' || '' %><%= flash 'works' || '' %>
%= stylesheet '/b.css', media => 'test'
%= image '/images/test.png', alt => 'Test'
%= url_for('root')->to_abs
%= url_for 'root'
%= url_for('root')->base
%= current_route
