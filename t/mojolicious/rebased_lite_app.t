#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll and kqueue
BEGIN { $ENV{MOJO_POLL} = 1 }

use Test::More tests => 6;

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

my $t = Test::Mojo->new;

# GET /
$t->get_ok('/')->status_is(200)->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
http://kraih.com/rebased/foo
foo
http://kraih.com/rebased/
EOF

# GET /foo
$t->get_ok('/foo')->status_is(200)->content_is(<<EOF);
<base href="http://kraih.com/rebased/" />
http://kraih.com/rebased/

http://kraih.com/rebased/
EOF

__DATA__
@@ root.html.ep
%= base_tag
%= url_for('foo')->to_abs
%= url_for('foo')
%= url_for('foo')->base

@@ foo.html.ep
%= base_tag
%= url_for('root')->to_abs
%= url_for('root')
%= url_for('root')->base
