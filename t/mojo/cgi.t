use Mojo::Base -strict;

use Test::More;
use Mojo::Message::Response;
use Mojo::Server::CGI;
use Mojolicious::Command::cgi;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

get '/' => {text => 'Your Mojo is working!'};

post '/chunked' => sub {
  my $c = shift;

  my $params = $c->req->params->to_hash;
  my @chunks;
  for my $key (sort keys %$params) { push @chunks, $params->{$key} }

  my $cb = sub {
    my $c     = shift;
    my $chunk = shift @chunks || '';
    $c->write_chunk($chunk, $chunk ? __SUB__ : ());
  };
  $c->$cb;
};

get '/params' => sub {
  my $c = shift;
  $c->inactivity_timeout(60);
  $c->render(json => $c->req->params->to_hash);
};

get '/proxy' => sub {
  my $c       = shift;
  my $reverse = join ':', $c->tx->remote_address,
    $c->req->url->to_abs->protocol;
  $c->render(text => $reverse);
};

subtest 'Reverse proxy' => sub {
  ok !Mojo::Server::CGI->new->reverse_proxy, 'no reverse proxy';
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  ok !!Mojo::Server::CGI->new->reverse_proxy, 'reverse proxy';
};

subtest 'Simple' => sub {
  my $msg = '';
  local *STDOUT;
  open STDOUT, '>', \$msg;
  local %ENV = (
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  is(Mojolicious::Command::cgi->new(app => app)->run, 200, 'right status');

  my $res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
  is $res->code, 200, 'right status';
  is $res->headers->status,         '200 OK', 'right "Status" value';
  is $res->headers->content_length, 21,       'right "Content-Length" value';
  is $res->headers->content_type,   'text/html;charset=UTF-8',
    'right "Content-Type" value';
  is $res->body, 'Your Mojo is working!', 'right content';
};

subtest 'HEAD request' => sub {
  my $msg = '';
  local *STDOUT;
  open STDOUT, '>', \$msg;
  local %ENV = (
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'HEAD',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  is(Mojolicious::Command::cgi->new(app => app)->run, 200, 'right status');

  my $res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
  is $res->code, 200, 'right status';
  is $res->headers->status,         '200 OK', 'right "Status" value';
  is $res->headers->content_length, 21,       'right "Content-Length" value';
  is $res->headers->content_type,   'text/html;charset=UTF-8',
    'right "Content-Type" value';
  is $res->body, '', 'no content';
};

subtest 'Non-parsed headers' => sub {
  my $msg = '';
  local *STDOUT;
  open STDOUT, '>', \$msg;
  local %ENV = (
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  is(Mojolicious::Command::cgi->new(app => app)->run('--nph'),
    200, 'right status');

  my $res = Mojo::Message::Response->new->parse($msg);
  is $res->code, 200, 'right status';
  is $res->headers->status,         undef, 'no "Status" value';
  is $res->headers->content_length, 21,    'right "Content-Length" value';
  is $res->headers->content_type,   'text/html;charset=UTF-8',
    'right "Content-Type" value';
  is $res->body, 'Your Mojo is working!', 'right content';
};

subtest 'Chunked' => sub {
  my $content = 'test1=1&test2=2&test3=3&test4=4&test5=5&test6=6&test7=7';
  my $msg     = '';
  local *STDIN;
  open STDIN, '<', \$content;
  local *STDOUT;
  open STDOUT, '>', \$msg;
  local %ENV = (
    PATH_INFO       => '/chunked',
    CONTENT_LENGTH  => length($content),
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  is(Mojolicious::Command::cgi->new(app => app)->run, 200, 'right status');

  like $msg, qr/chunked/, 'is chunked';
  my $res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
  is $res->code, 200, 'right status';
  is $res->headers->status, '200 OK', 'right "Status" value';
  is $res->body, '1234567', 'right content';
};

subtest 'Parameters' => sub {
  my $msg = '';
  local *STDOUT;
  open STDOUT, '>', \$msg;
  local %ENV = (
    PATH_INFO       => '/params',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  is(Mojolicious::Command::cgi->new(app => app)->run, 200, 'right status');

  my $res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
  is $res->code, 200, 'right status';
  is $res->headers->status, '200 OK', 'right "Status" value';
  is $res->headers->content_type, 'application/json;charset=UTF-8',
    'right "Content-Type" value';
  is $res->headers->content_length, 27, 'right "Content-Length" value';
  is $res->json->{lalala}, 23,    'right value';
  is $res->json->{bar},    'baz', 'right value';
};

subtest 'Reverse proxy' => sub {
  my $msg = '';
  local *STDOUT;
  open STDOUT, '>', \$msg;
  local %ENV = (
    PATH_INFO                => '/proxy',
    REQUEST_METHOD           => 'GET',
    SCRIPT_NAME              => '/',
    HTTP_HOST                => 'localhost:8080',
    SERVER_PROTOCOL          => 'HTTP/1.0',
    'HTTP_X_Forwarded_For'   => '192.0.2.2, 192.0.2.1',
    'HTTP_X_Forwarded_Proto' => 'https'
  );
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  is(Mojolicious::Command::cgi->new(app => app)->run, 200, 'right status');

  my $res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
  is $res->code, 200, 'right status';
  is $res->headers->status,         '200 OK', 'right "Status" value';
  is $res->headers->content_length, 15,       'right "Content-Length" value';
  is $res->headers->content_type,   'text/html;charset=UTF-8',
    'right "Content-Type" value';
  is $res->body, '192.0.2.1:https', 'right content';
};

done_testing();
