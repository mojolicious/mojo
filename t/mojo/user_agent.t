use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

use Test::More tests => 73;

# "The strong must protect the sweet."
use Mojo::IOLoop;
use Mojolicious::Lite;

use_ok 'Mojo::UserAgent';

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'works!'};

# GET /timeout
my $timeout = undef;
get '/timeout' => sub {
  my $self = shift;
  Mojo::IOLoop->stream($self->tx->connection)
    ->timeout($self->param('timeout'));
  $self->on(finish => sub { $timeout = 1 });
  $self->render_later;
};

# GET /no_length
get '/no_length' => sub {
  my $self = shift;
  $self->finish('works too!');
  $self->rendered(200);
};

# GET /echo
get '/echo' => sub {
  my $self = shift;
  $self->render_data($self->req->body);
};

# Proxy detection
my $ua      = Mojo::UserAgent->new;
my $backup  = $ENV{HTTP_PROXY} || '';
my $backup2 = $ENV{HTTPS_PROXY} || '';
my $backup3 = $ENV{NO_PROXY} || '';
my $backup4 = $ENV{http_proxy} || '';
my $backup5 = $ENV{https_proxy} || '';
my $backup6 = $ENV{no_proxy} || '';
$ENV{HTTP_PROXY}  = 'http://127.0.0.1';
$ENV{HTTPS_PROXY} = 'http://127.0.0.1:8080';
$ENV{NO_PROXY}    = 'mojolicio.us';
$ua->detect_proxy;
is $ua->http_proxy,  'http://127.0.0.1',      'right proxy';
is $ua->https_proxy, 'http://127.0.0.1:8080', 'right proxy';
$ua->http_proxy(undef);
$ua->https_proxy(undef);
is $ua->http_proxy,  undef, 'right proxy';
is $ua->https_proxy, undef, 'right proxy';
ok !$ua->need_proxy('dummy.mojolicio.us'), 'no proxy needed';
ok $ua->need_proxy('icio.us'),   'proxy needed';
ok $ua->need_proxy('localhost'), 'proxy needed';
$ENV{HTTP_PROXY}  = undef;
$ENV{HTTPS_PROXY} = undef;
$ENV{NO_PROXY}    = undef;
$ENV{http_proxy}  = 'proxy.kraih.com';
$ENV{https_proxy} = 'tunnel.kraih.com';
$ENV{no_proxy}    = 'localhost,localdomain,foo.com,kraih.com';
$ua->detect_proxy;
is $ua->http_proxy,  'proxy.kraih.com',  'right proxy';
is $ua->https_proxy, 'tunnel.kraih.com', 'right proxy';
ok $ua->need_proxy('dummy.mojolicio.us'), 'proxy needed';
ok $ua->need_proxy('icio.us'),            'proxy needed';
ok !$ua->need_proxy('localhost'),             'proxy needed';
ok !$ua->need_proxy('localhost.localdomain'), 'no proxy needed';
ok !$ua->need_proxy('foo.com'),               'no proxy needed';
ok !$ua->need_proxy('kraih.com'),             'no proxy needed';
ok !$ua->need_proxy('www.kraih.com'),         'no proxy needed';
ok $ua->need_proxy('www.kraih.com.com'), 'proxy needed';
$ENV{HTTP_PROXY}  = $backup;
$ENV{HTTPS_PROXY} = $backup2;
$ENV{NO_PROXY}    = $backup3;
$ENV{http_proxy}  = $backup4;
$ENV{https_proxy} = $backup5;
$ENV{no_proxy}    = $backup6;

# Max redirects
$backup = $ENV{MOJO_MAX_REDIRECTS} || '';
$ENV{MOJO_MAX_REDIRECTS} = 25;
is(Mojo::UserAgent->new->max_redirects, 25, 'right value');
$ENV{MOJO_MAX_REDIRECTS} = $backup;

# GET / (non-blocking)
$ua = Mojo::UserAgent->new(ioloop => Mojo::IOLoop->singleton);
my ($success, $code, $body);
$ua->get(
  '/' => sub {
    my $tx = pop;
    $success = $tx->success;
    $code    = $tx->res->code;
    $body    = $tx->res->body;
    Mojo::IOLoop->stop;
  }
);
Mojo::IOLoop->start;
ok $success, 'successful';
is $code,    200, 'right status';
is $body,    'works!', 'right content';

# Error in callback
my $cb = app->log->subscribers('message')->[0];
app->log->unsubscribe(message => $cb);
app->log->level('error');
my $cb2 = app->ua->on(error => sub { Mojo::IOLoop->stop });
ok app->ua->has_subscribers('error'), 'has subscribers';
my $err;
my $cb3 = app->log->on(message => sub { $err .= pop });
app->ua->get('/' => sub { die 'error event works' });
Mojo::IOLoop->start;
app->log->level('fatal');
app->log->on(message => $cb);
like $err, qr/error event works/, 'right error';
app->ua->unsubscribe(error => $cb2);
app->log->unsubscribe(message => $cb3);

# GET / (blocking)
my $tx = $ua->get('/');
ok $tx->success, 'successful';
ok !$tx->kept_alive, 'kept connection not alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (again)
$tx = $ua->get('/');
ok $tx->success,    'successful';
ok $tx->kept_alive, 'kept connection alive';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET / (callbacks)
my $finished;
$tx = $ua->build_tx(GET => '/');
$ua->on(
  start => sub {
    my ($self, $tx) = @_;
    $tx->on(finish => sub { $finished++ });
  }
);
$tx = $ua->start($tx);
$ua->unsubscribe('start');
ok $tx->success, 'successful';
is $finished, 1, 'finish event has been emitted';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /no_length (missing Content-Length header)
$tx = $ua->get('/no_length');
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok !$tx->keep_alive, 'keep connection not alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, 'works too!', 'right content';

# GET / (built-in server)
$tx = $ua->get('/');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';

# GET /timeout (built-in server times out)
my $log = '';
$cb = app->log->subscribers('message')->[0];
app->log->unsubscribe(message => $cb);
app->log->level('error');
app->log->on(message => sub { $log .= pop });
$tx = $ua->get('/timeout?timeout=0.5');
app->log->level('fatal');
app->log->on(message => $cb);
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close.', 'right error';
is $timeout, 1, 'finish event has been emitted';
like $log, qr/Connection\ timeout\./, 'right log message';

# GET /timeout (client times out)
$cb = $ua->on(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      connection => sub {
        my ($tx, $connection) = @_;
        Mojo::IOLoop->stream($connection)->timeout('0.5');
      }
    );
  }
);
$tx = $ua->get('/timeout?timeout=5');
$ua->unsubscribe(start => $cb);
ok !$tx->success, 'not successful';
is $tx->error, 'Connection timeout.', 'right error';

# GET / (introspect)
my $req = my $res = '';
my $start = $ua->on(
  start => sub {
    my ($ua, $tx) = @_;
    $tx->on(
      connection => sub {
        my ($tx, $connection) = @_;
        my $stream = Mojo::IOLoop->stream($connection);
        my $read   = $stream->on(
          read => sub {
            my ($stream, $chunk) = @_;
            $res .= $chunk;
          }
        );
        my $write = $stream->on(
          write => sub {
            my ($stream, $chunk) = @_;
            $req .= $chunk;
          }
        );
        $tx->on(
          finish => sub {
            $stream->unsubscribe(read  => $read);
            $stream->unsubscribe(write => $write);
          }
        );
      }
    );
  }
);
$tx = $ua->get('/', 'whatever');
ok $tx->success, 'successful';
is $tx->res->code, 200,      'right status';
is $tx->res->body, 'works!', 'right content';
is scalar @{Mojo::IOLoop->stream($tx->connection)->subscribers('write')}, 0,
  'unsubscribed successfully';
is scalar @{Mojo::IOLoop->stream($tx->connection)->subscribers('read')}, 1,
  'unsubscribed successfully';
like $req, qr#^GET / .*whatever$#s,      'right request';
like $res, qr#^HTTP/.*200 OK.*works!$#s, 'right response';
$ua->unsubscribe(start => $start);
ok !$ua->has_subscribers('start'), 'unsubscribed successfully';

# GET /echo (stream with drain callback)
my $stream = 0;
$tx = $ua->build_tx(GET => '/echo');
my $i = 0;
my $drain;
$drain = sub {
  my $req = shift;
  return $ua->ioloop->timer(
    '0.5' => sub {
      $req->write_chunk('');
      $tx->resume;
      $stream
        += @{Mojo::IOLoop->stream($tx->connection)->subscribers('drain')};
    }
  ) if $i >= 10;
  $req->write_chunk($i++, $drain);
  $tx->resume;
  return unless my $id = $tx->connection;
  $stream += @{Mojo::IOLoop->stream($id)->subscribers('drain')};
};
$tx->req->$drain;
$ua->start($tx);
ok $tx->success, 'successful';
ok !$tx->error, 'no error';
ok $tx->kept_alive, 'kept connection alive';
ok $tx->keep_alive, 'keep connection alive';
is $tx->res->code, 200,          'right status';
is $tx->res->body, '0123456789', 'right content';
is $stream, 1, 'no leaking subscribers';

# Nested keep alive
my @kept_alive;
$ua->get(
  '/',
  sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      '/',
      sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          '/',
          sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [undef, 1, 1], 'connections kept alive';

# Simple nested keep alive with timers
@kept_alive = ();
$ua->get(
  '/',
  sub {
    push @kept_alive, pop->kept_alive;
    Mojo::IOLoop->timer(
      '0.25' => sub {
        $ua->get(
          '/',
          sub {
            push @kept_alive, pop->kept_alive;
            Mojo::IOLoop->timer('0.25' => sub { Mojo::IOLoop->stop });
          }
        );
      }
    );
  }
);
Mojo::IOLoop->start;
is_deeply \@kept_alive, [1, 1], 'connections kept alive';

# Premature connection close
my $port = Mojo::IOLoop->generate_port;
my $id =
  Mojo::IOLoop->server({port => $port} => sub { Mojo::IOLoop->drop(pop) });
$tx = $ua->get("http://localhost:$port/");
ok !$tx->success, 'not successful';
is $tx->error, 'Premature connection close.', 'right error';
