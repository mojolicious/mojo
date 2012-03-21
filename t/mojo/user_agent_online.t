use Mojo::Base -strict;

# Disable libev and TLS
BEGIN {
  $ENV{MOJO_NO_TLS}  = 1;
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor';
}

use Test::More;

plan skip_all => 'set TEST_ONLINE to enable this test (developer only!)'
  unless $ENV{TEST_ONLINE};
plan tests => 108;

# "So then I said to the cop, "No, you're driving under the influence...
#  of being a jerk"."
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojolicious::Lite;
use ojo;

# GET /remote_address
get '/remote_address' => sub {
  my $self = shift;
  $self->render(text => $self->tx->remote_address);
};

# Make sure user agents dont taint the ioloop
my $loop = Mojo::IOLoop->singleton;
my $ua   = Mojo::UserAgent->new;
my ($id, $code);
$ua->get(
  'http://cpan.org' => sub {
    my $tx = pop;
    $id   = $tx->connection;
    $code = $tx->res->code;
    $loop->stop;
  }
);
$loop->start;
$ua = undef;
$loop->one_tick;
ok !$loop->stream($id), 'loop not tainted';
is $code, 301, 'right status';

# Fresh user agent
$ua = Mojo::UserAgent->new;

# Local address
$ua->app(app);
my $sock = IO::Socket::INET->new(
  PeerAddr => 'mojolicio.us',
  PeerPort => 80,
  Proto    => 'tcp'
);
my $address = $sock->sockhost;
isnt $address, '127.0.0.1', 'different address';
$ua->local_address('127.0.0.1')->max_connections(0);
is $ua->get('/remote_address')->res->body, '127.0.0.1', 'right address';
$ua->local_address($address);
is $ua->get('/remote_address')->res->body, $address, 'right address';

# Fresh user agent
$ua = Mojo::UserAgent->new;

# Connection refused
my $tx = $ua->build_tx(GET => 'http://localhost:99999');
$ua->start($tx);
ok !$tx->is_finished, 'transaction is not finished';
is $tx->error, "Couldn't connect.", 'right error';

# Connection refused
$tx = $ua->build_tx(GET => 'http://127.0.0.1:99999');
$ua->start($tx);
ok !$tx->is_finished, 'transaction is not finished';

# Host does not exist
$tx = $ua->build_tx(GET => 'http://cdeabcdeffoobarnonexisting.com');
$ua->start($tx);
is $tx->error, "Couldn't connect.", 'right error';
ok !$tx->is_finished, 'transaction is not finished';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Keep alive
$ua->get('http://mojolicio.us', sub { Mojo::IOLoop->singleton->stop });
Mojo::IOLoop->singleton->start;
my $kept_alive;
$ua->get(
  'http://mojolicio.us',
  sub {
    my $tx = pop;
    Mojo::IOLoop->singleton->stop;
    $kept_alive = $tx->kept_alive;
  }
);
Mojo::IOLoop->singleton->start;
ok $kept_alive, 'connection was kept alive';

# Nested keep alive
my @kept_alive;
$ua->get(
  'http://mojolicio.us',
  sub {
    my ($self, $tx) = @_;
    push @kept_alive, $tx->kept_alive;
    $self->get(
      'http://mojolicio.us',
      sub {
        my ($self, $tx) = @_;
        push @kept_alive, $tx->kept_alive;
        $self->get(
          'http://mojolicio.us',
          sub {
            my ($self, $tx) = @_;
            push @kept_alive, $tx->kept_alive;
            Mojo::IOLoop->singleton->stop;
          }
        );
      }
    );
  }
);
Mojo::IOLoop->singleton->start;
is_deeply \@kept_alive, [1, 1, 1], 'connections kept alive';

# Fresh user agent again
$ua = Mojo::UserAgent->new;

# Custom non keep alive request
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://cpan.org');
$tx->req->headers->connection('close');
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
is $tx->res->code, 301, 'right status';
like $tx->res->headers->connection, qr/close/i, 'right "Connection" header';

# Oneliner
is g('mojolicio.us')->code,          200, 'right status';
is h('mojolicio.us')->code,          200, 'right status';
is p('mojolicio.us/lalalala')->code, 404, 'right status';
is g('http://mojolicio.us')->code,   200, 'right status';
is p('http://mojolicio.us')->code,   404, 'right status';
is oO('http://mojolicio.us')->code,  200, 'right status';
is oO(POST => 'http://mojolicio.us')->code, 404, 'right status';
my $res = f('search.cpan.org/search' => {query => 'mojolicious'});
like $res->body, qr/Mojolicious/, 'right content';
is $res->code,   200,             'right status';

# Simple request
$tx = $ua->get('cpan.org');
is $tx->req->method, 'GET',             'right method';
is $tx->req->url,    'http://cpan.org', 'right url';
is $tx->res->code,   301,               'right status';

# HTTPS request without TLS support
$tx = $ua->get('https://www.google.com');
ok !!$tx->error, 'request failed';

# Simple request with body
$tx = $ua->get('http://mojolicio.us' => 'Hi there!');
is $tx->req->method, 'GET', 'right method';
is $tx->req->url, 'http://mojolicio.us', 'right url';
is $tx->req->headers->content_length, 9, 'right content length';
is $tx->req->body, 'Hi there!', 'right content';
is $tx->res->code, 200,         'right status';

# Simple form POST
$tx =
  $ua->post_form('http://search.cpan.org/search' => {query => 'mojolicious'});
is $tx->req->method, 'POST', 'right method';
is $tx->req->url, 'http://search.cpan.org/search', 'right url';
is $tx->req->headers->content_length, 17, 'right content length';
is $tx->req->body,   'query=mojolicious', 'right content';
like $tx->res->body, qr/Mojolicious/,     'right content';
is $tx->res->code,   200,                 'right status';
ok $tx->keep_alive, 'connection will be kept alive';

# Simple keep alive form POST
$tx =
  $ua->post_form('http://search.cpan.org/search' => {query => 'mojolicious'});
is $tx->req->method, 'POST', 'right method';
is $tx->req->url, 'http://search.cpan.org/search', 'right url';
is $tx->req->headers->content_length, 17, 'right content length';
is $tx->req->body,   'query=mojolicious', 'right content';
like $tx->res->body, qr/Mojolicious/,     'right content';
is $tx->res->code,   200,                 'right status';
ok $tx->kept_alive, 'connection was kept alive';

# Simple request
$tx = $ua->get('http://www.wikipedia.org');
is $tx->req->method, 'GET',                      'right method';
is $tx->req->url,    'http://www.wikipedia.org', 'right url';
is $tx->req->body,   '',                         'no content';
is $tx->res->code,   200,                        'right status';

# Simple keep alive requests
$tx = $ua->get('http://google.com');
is $tx->req->method, 'GET',               'right method';
is $tx->req->url,    'http://google.com', 'right url';
is $tx->res->code,   301,                 'right status';
$tx = $ua->get('http://www.wikipedia.org');
is $tx->req->method, 'GET',                      'right method';
is $tx->req->url,    'http://www.wikipedia.org', 'right url';
is $tx->res->code,   200,                        'right status';
ok $tx->kept_alive, 'connection was kept alive';
$tx = $ua->get('http://www.wikipedia.org');
is $tx->req->method, 'GET',                      'right method';
is $tx->req->url,    'http://www.wikipedia.org', 'right url';
is $tx->res->code,   200,                        'right status';

# Simple requests with redirect
$ua->max_redirects(3);
$tx = $ua->get('http://wikipedia.org/wiki/Perl');
$ua->max_redirects(0);
is $tx->req->method, 'GET',                               'right method';
is $tx->req->url,    'http://en.wikipedia.org/wiki/Perl', 'right url';
is $tx->res->code,   200,                                 'right status';
is $tx->previous->req->method, 'GET', 'right method';
is $tx->previous->req->url, 'http://www.wikipedia.org/wiki/Perl', 'right url';
is $tx->previous->res->code, 301, 'right status';

# Simple requests with redirect and no callback
$ua->max_redirects(3);
$tx = $ua->get('http://wikipedia.org/wiki/Perl');
$ua->max_redirects(0);
is $tx->req->method, 'GET',                               'right method';
is $tx->req->url,    'http://en.wikipedia.org/wiki/Perl', 'right url';
is $tx->res->code,   200,                                 'right status';
is $tx->previous->req->method, 'GET', 'right method';
is $tx->previous->req->url, 'http://www.wikipedia.org/wiki/Perl', 'right url';
is $tx->previous->res->code, 301, 'right status';

# Custom chunked request without callback
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.google.com');
$tx->req->headers->transfer_encoding('chunked');
$tx->req->write_chunk(
  'hello world!' => sub {
    shift->write_chunk('hello world2!' => sub { shift->write_chunk('') });
  }
);
$ua->start($tx);
is_deeply [$tx->error],      ['Bad Request', 400], 'right error';
is_deeply [$tx->res->error], ['Bad Request', 400], 'right error';

# Custom requests with keep alive
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.wikipedia.org');
ok !$tx->kept_alive, 'connection was not kept alive';
$ua->start($tx);
ok $tx->is_finished, 'transaction is finished';
ok $tx->kept_alive,  'connection was kept alive';
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.wikipedia.org');
ok !$tx->kept_alive, 'connection was not kept alive';
$ua->start($tx);
ok $tx->is_finished,   'transaction is finished';
ok $tx->kept_alive,    'connection was kept alive';
ok $tx->local_address, 'has local address';
ok $tx->local_port > 0, 'has local port';

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.wikipedia.org');
my $tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.wikipedia.org');
my $tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.wikipedia.org');
$ua->start($tx);
$ua->start($tx2);
$ua->start($tx3);
ok $tx->is_finished,  'transaction is finished';
ok $tx2->is_finished, 'transaction is finished';
ok $tx3->is_finished, 'transaction is finished';
is $tx->res->code,  200, 'right status';
is $tx2->res->code, 200, 'right status';
is $tx3->res->code, 200, 'right status';
like $tx2->res->content->asset->slurp, qr/Wikipedia/i, 'right content';

# Mixed HEAD and GET requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('HEAD');
$tx->req->url->parse('http://www.wikipedia.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.wikipedia.org');
$ua->start($tx);
$ua->start($tx2);
ok $tx->is_finished,  'transaction is finished';
ok $tx2->is_finished, 'transaction is finished';
is $tx->res->code,  200, 'right status';
is $tx2->res->code, 200, 'right status';
like $tx2->res->content->asset->slurp, qr/Wikipedia/i, 'right content';

# Multiple requests
$tx = Mojo::Transaction::HTTP->new;
$tx->req->method('GET');
$tx->req->url->parse('http://www.perl.org');
$tx2 = Mojo::Transaction::HTTP->new;
$tx2->req->method('GET');
$tx2->req->url->parse('http://www.perl.org');
$tx3 = Mojo::Transaction::HTTP->new;
$tx3->req->method('GET');
$tx3->req->url->parse('http://www.perl.org');
my $tx4 = Mojo::Transaction::HTTP->new;
$tx4->req->method('GET');
$tx4->req->url->parse('http://www.perl.org');
$ua->start($tx);
$ua->start($tx2);
$ua->start($tx3);
$ua->start($tx4);
ok $tx->is_finished,  'transaction is finished';
ok $tx2->is_finished, 'transaction is finished';
ok $tx3->is_finished, 'transaction is finished';
ok $tx4->is_finished, 'transaction is finished';
is $tx->res->code,  200, 'right status';
is $tx2->res->code, 200, 'right status';
is $tx3->res->code, 200, 'right status';
is $tx4->res->code, 200, 'right status';
like $tx2->res->content->asset->slurp, qr/Perl/i, 'right content';

# Connect timeout (non-routable address)
$tx = $ua->connect_timeout(0.5)->get('192.0.2.1');
ok !$tx->is_finished, 'transaction is not finished';
is $tx->error, 'Connect timeout.', 'right error';
$ua->connect_timeout(3);

# Request timeout (non-routable address)
$tx = $ua->request_timeout(0.5)->get('192.0.2.1');
ok !$tx->is_finished, 'transaction is not finished';
is $tx->error, 'Request timeout.', 'right error';
