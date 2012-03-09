use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 9;

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

# GET /
get '/' => 'root';

# GET /foo
get '/foo';

# GET /bar
get '/bar' => sub {
  my $self = shift;
  $self->redirect_to($self->url_for('foo'));
};

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
<script src="/rebased/js/jquery.js" type="text/javascript"></script>
<img src="/rebased/images/test.png" />
http://kraih.com/rebased/foo
/rebased/foo
http://kraih.com/
EOF

# GET /foo
$t->get_ok('/foo')->status_is(200)->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
<link href="/rebased/b.css" media="test" rel="stylesheet" type="text/css" />
<img alt="Test" src="/rebased/images/test.png" />
http://kraih.com/rebased
/rebased
http://kraih.com/
EOF

# GET /bar
$t->get_ok('/bar')->status_is(302)
  ->header_is(Location => 'http://kraih.com/rebased/foo');

__DATA__
@@ root.html.ep
%= base_tag
%= javascript '/js/jquery.js'
%= image '/images/test.png'
%= url_for('foo')->to_abs
%= url_for 'foo'
%= url_for('foo')->base

@@ foo.html.ep
%= base_tag
%= stylesheet '/b.css', media => 'test'
%= image '/images/test.png', alt => 'Test'
%= url_for('root')->to_abs
%= url_for 'root'
%= url_for('root')->base
