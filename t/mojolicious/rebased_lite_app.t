use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More tests => 19;

# "For example, if you killed your grandfather, you'd cease to exist!
#  But existing is basically all I do!"
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

# GET /
get '/' => 'root';

# GET /foo
get '/foo';

# GET /bar
get '/bar' => sub {
  my $self = shift;
  $self->redirect_to($self->url_for('foo'));
};

# GET /baz
get '/baz' => sub { shift->render('root') };

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->header_is('X-Route' => 'root')
  ->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
<script src="/rebased/js/jquery.js" type="text/javascript"></script>
<img src="/rebased/images/test.png" />
http://kraih.com/rebased/foo
/rebased/foo
http://kraih.com/
root
  Welcome to the root!
EOF

# GET /foo
$t->get_ok('/foo')->status_is(200)->header_is('X-Route' => 'foo')
  ->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
<link href="/rebased/b.css" media="test" rel="stylesheet" type="text/css" />
<img alt="Test" src="/rebased/images/test.png" />
http://kraih.com/rebased
/rebased
http://kraih.com/
foo
EOF

# GET /bar
$t->get_ok('/bar')->status_is(302)->header_is('X-Route' => 'bar')
  ->header_is(Location => 'http://kraih.com/rebased/foo');

# GET /baz
$t->get_ok('/baz')->status_is(200)->header_is('X-Route' => 'baz')
  ->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
<script src="/rebased/js/jquery.js" type="text/javascript"></script>
<img src="/rebased/images/test.png" />
http://kraih.com/rebased/foo
/rebased/foo
http://kraih.com/
baz
EOF

# GET /yada (does not exist)
$t->get_ok('/yada')->status_is(404)->header_is('X-Route' => '');

__DATA__
@@ root.html.ep
%= base_tag
%= javascript '/js/jquery.js'
%= image '/images/test.png'
%= url_for('foo')->to_abs
%= url_for 'foo'
%= url_for('foo')->base
%= current_route
% if (current_route 'root') {
  Welcome to the root!
% }

@@ foo.html.ep
%= base_tag
%= stylesheet '/b.css', media => 'test'
%= image '/images/test.png', alt => 'Test'
%= url_for('root')->to_abs
%= url_for 'root'
%= url_for('root')->base
%= current_route
