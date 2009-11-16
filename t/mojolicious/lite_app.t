#!/usr/bin/env perl

# Copyright (C) 2008-2009, Sebastian Riedel.

use strict;
use warnings;

use utf8;

use Test::More tests => 164;

# Wait you're the only friend I have...
# You really want a robot for a friend?
# Yeah ever since I was six.
# Well, ok but I don't want people thinking we're robosexuals,
# so if anyone asks you're my debugger.
use Mojo::ByteStream 'b';
use Mojo::Client;
use Mojo::JSON;
use Mojo::Transaction::Single;
use Mojolicious::Lite;

# Silence
app->log->level('error');

# Test with lite templates
app->renderer->default_handler('epl');

# GET /
get '/' => 'root';

# GET /root
get '/root.html' => 'root_path';

# GET /outerlayout
get '/outerlayout' => sub {
    my $self = shift;
    $self->render(
        template => 'outerlayout',
        layout   => 'layout',
        handler  => 'ep'
    );
};

# GET /foo
get '/foo' => sub {
    my $self = shift;
    $self->render_text('Yea baby!');
};

# GET /layout
get '/layout' => sub { shift->render_text('Yea baby!', layout => 'layout') };

# POST /template
post '/template' => 'index';

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

# POST /utf8
post '/utf8' => 'form';

# POST /malformed_UTF-8
post '/malformed_utf8' => sub {
    my $c = shift;
    $c->render_text(Mojo::URL->new($c->param('foo')));
};

# GET /json
get '/json' => sub { shift->render_json({foo => [1, -2, 3, 'bar']}) };

# GET /autostash
get '/autostash' => sub { shift->render(handler => 'ep', foo => 'bar') } =>
  'autostash';

# GET /helper
get '/helper' => sub { shift->render(handler => 'ep') } => 'helper';
app->renderer->add_helper(
    agent => sub { scalar shift->req->headers->user_agent });

# GET /eperror
get '/eperror' => sub { shift->render(handler => 'ep') } => 'eperror';

# GET /subrequest
get '/subrequest' => sub {
    my $self = shift;
    $self->pause;
    $self->client->post(
        '/template' => sub {
            my ($client, $tx) = @_;
            $self->resume;
            $self->render_text($tx->res->body);
        }
    )->process;
};

# GET /redirect_url
get '/redirect_url' => sub {
    shift->redirect_to('http://127.0.0.1/foo')->render_text('Redirecting!');
};

# GET /redirect_path
get '/redirect_path' => sub {
    shift->redirect_to('/foo/bar')->render_text('Redirecting!');
};

# GET /redirect_named
get '/redirect_named' => sub {
    shift->redirect_to('index', format => 'txt')->render_text('Redirecting!');
};

# GET /koi8-r
app->types->type('koi8-r' => 'text/html; charset=koi8-r');
get '/koi8-r' => sub {
    app->renderer->encoding('koi8-r');
    shift->render('encoding', format => 'koi8-r', handler => 'ep');
    app->renderer->encoding(undef);
};

ladder sub {
    my $self = shift;
    return unless $self->req->headers->header('X-Bender');
    $self->res->headers->header('X-Ladder' => 23);
    return 1;
};

# GET /with_ladder
get '/with_ladder' => sub {
    my $self = shift;
    $self->render_text('Ladders are cool!');
};

# GET /with_ladder_too
get '/with_ladder_too' => sub {
    my $self = shift;
    $self->render_text('Ladders are cool too!');
};

ladder sub {
    my $self = shift;

    # Authenticated
    my $name = $self->param('name') || '';
    return 1 if $name eq 'Bender';

    # Not authenticated
    $self->render('param_auth_denied');
    return;
};

# GET /param_auth
get '/param_auth' => 'param_auth';

# GET /param_auth/too
get '/param_auth/too' =>
  sub { shift->render_text('You could be Bender too!') };

# Oh Fry, I love you more than the moon, and the stars,
# and the POETIC IMAGE NUMBER 137 NOT FOUND
my $app = Mojolicious::Lite->new;
my $client = Mojo::Client->new(app => $app);
$app->client($client);

# GET /
$client->get(
    '/' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "/root.html");
    }
)->process;

# GET /root
$client->get(
    '/root.html' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "/.html");
    }
)->process;

# GET /.html
$client->get(
    '/.html' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "/root.html");
    }
)->process;

# GET /outerlayout
$client->get(
    '/outerlayout' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body, "layouted Hello\n[\n  1,\n  2\n]\nthere!\n\n\n");
    }
)->process;

# GET /foo
$client->get(
    '/foo' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Yea baby!');
    }
)->process;

# POST /template
$client->post(
    '/template' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Just works!');
    }
)->process;

# GET /something
$client->get(
    '/something' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Just works!');
    }
)->process;

# POST /something
$client->post(
    '/something' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Just works!');
    }
)->process;

# DELETE /something
$client->delete(
    '/something' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Just works!');
    }
)->process;

# GET /something/else
$client->get(
    '/something/else' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Yay!');
    }
)->process;

# POST /something/else
$client->post(
    '/something/else' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Yay!');
    }
)->process;

# DELETE /something/else
$client->delete(
    '/something/else' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Oops!/);
    }
)->process;

# GET /regex/23
$client->get(
    '/regex/23' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '23');
    }
)->process;

# GET /regex/foo
$client->get(
    '/regex/foo' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Oops!/);
    }
)->process;

# POST /bar
$client->post(
    '/bar' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'default');
    }
)->process;

# POST /bar/baz
$client->post(
    '/bar/baz' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'baz');
    }
)->process;

# GET /layout
$client->get(
    '/layout' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body, "Yea baby! with layout\n");
    }
)->process;

# GET /firefox
$client->get(
    '/firefox/bar' => ('User-Agent' => 'Firefox') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '/firefox/foo');
    }
)->process;

# GET /firefox
$client->get(
    '/firefox/bar' => ('User-Agent' => 'Explorer') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Oops!/);
    }
)->process;

# POST /utf8
my $tx = Mojo::Transaction::Single->new;
$tx->req->method('POST');
$tx->req->url->parse('/utf8');
$tx->req->headers->content_type('application/x-www-form-urlencoded');
$tx->req->body('name=%D0%92%D1%8F%D1%87%D0%B5%D1%81%D0%BB%D0%B0%D0%B2');
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->content_type,           'text/html');
        is($tx->res->headers->content_length,         40);
        is($tx->res->body, b(<<EOF)->encode('UTF-8')->to_string);
Вячеслав Тихановский
EOF
    }
)->process;

# POST /malformed_utf8
my $level = $app->log->level;
$app->log->level('fatal');
$tx = Mojo::Transaction::Single->new;
$tx->req->method('POST');
$tx->req->url->parse('/malformed_utf8');
$tx->req->headers->content_type('application/x-www-form-urlencoded');
$tx->req->body('foo=%E1');
$client->queue(
    $tx => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            '');
    }
)->process;
$app->log->level($level);

# GET /json
$client->get(
    '/json' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->content_type,           'application/json');
        my $hash = Mojo::JSON->new->decode($tx->res->body);
        is($hash->{foo}->[0], 1);
        is($hash->{foo}->[1], -2);
        is($hash->{foo}->[2], 3);
        is($hash->{foo}->[3], 'bar');
    }
)->process;

# GET /autostash
$client->get(
    '/autostash?bar=23' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "layouted bar23\n");
    }
)->process;

# GET /helper
$client->get(
    '/helper' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,
            '<br/>&lt;.../template(Mozilla/5.0 (compatible; Mojo; Perl))');
    }
)->process;

# GET /helper
$client->get(
    '/helper' => ('User-Agent' => 'Explorer') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body, '<br/>&lt;.../template(Explorer)');
    }
)->process;

# GET /eperror
$level = $app->log->level;
$app->log->level('fatal');
$client->get(
    '/eperror' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            500);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Internal Server Error/);
    }
)->process;
$app->log->level($level);

# GET /subrequest
$client->get(
    '/subrequest' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            'Just works!');
    }
)->process;

# GET /redirect_url
$client->get(
    '/redirect_url' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            302);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->location,               'http://127.0.0.1/foo');
        is($tx->res->body,                            'Redirecting!');
    }
)->process;

# GET /redirect_path
$client->get(
    '/redirect_path' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            302);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->location,               '/foo/bar');
        is($tx->res->body,                            'Redirecting!');
    }
)->process;

# GET /redirect_named
$client->get(
    '/redirect_named' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            302);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->location,               '/template.txt');
        is($tx->res->body,                            'Redirecting!');
    }
)->process;

# GET /koi8-r
$client->get(
    '/koi8-r' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->content_type, 'text/html; charset=koi8-r');
        is(b($tx->res->body)->decode('koi8-r'),
            "Этот человек наполняет меня надеждой."
              . " Ну, и некоторыми другими глубокими и приводящими в"
              . " замешательство эмоциями.\n");
    }
)->process;

# GET /with_ladder
$client->get(
    '/with_ladder' => ('X-Bender' => 'Rodriguez') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->header('X-Ladder'),     '23');
        is($tx->res->body,                            'Ladders are cool!');
    }
)->process;

# GET /with_ladder_too
$client->get(
    '/with_ladder_too' => ('X-Bender' => 'Rodriguez') => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->headers->header('X-Ladder'),     '23');
        is($tx->res->body, 'Ladders are cool too!');
    }
)->process;

# GET /with_ladder_too
$client->get(
    '/with_ladder_too' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            404);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        like($tx->res->body, qr/Oops!/);
    }
)->process;

# GET /param_auth
$client->get(
    '/param_auth' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "Not Bender!\n");
    }
)->process;

# GET /param_auth?name=Bender
$client->get(
    '/param_auth?name=Bender' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "Bender!\n");
    }
)->process;

# GET /param_auth/too
$client->get(
    '/param_auth/too' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body,                            "Not Bender!\n");
    }
)->process;

# GET /param_auth/too?name=Bender
$client->get(
    '/param_auth/too?name=Bender' => sub {
        my ($self, $tx) = @_;
        is($tx->res->code,                            200);
        is($tx->res->headers->server,                 'Mojo (Perl)');
        is($tx->res->headers->header('X-Powered-By'), 'Mojo (Perl)');
        is($tx->res->body, 'You could be Bender too!');
    }
)->process;

__DATA__
@@ param_auth.html.epl
Bender!

@@ param_auth_denied.html.epl
Not Bender!

@@ root.html.epl
%== shift->url_for('root_path')

@@ root_path.html.epl
%== shift->url_for('root');

@@ outerlayout.html.ep
Hello
<%== include 'outermenu' %>

@@ outermenu.html.ep
<%= dumper [1, 2] %>there!

@@ not_found.html.epl
Oops!

@@ index.html.epl
Just works!\

@@ form.html.epl
<%= shift->param('name') %> Тихановский

@@ layouts/layout.html.epl
<%= shift->render_inner %> with layout

@@ autostash.html.ep
% layout 'layout';
%= $foo
%= param 'bar'

@@ layouts/layout.html.ep
layouted <%== content %>

@@ helper.html.ep
%== '<br/>'
%= '<...'
%= url_for 'index'
(<%= agent %>)\

@@ eperror.html.ep
%= $c->foo('bar');

__END__
This is not a template!
lalala
test
