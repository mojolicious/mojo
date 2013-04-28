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
  my $self = shift;

  my $params = $self->req->params->to_hash;
  my @chunks;
  for my $key (sort keys %$params) { push @chunks, $params->{$key} }

  my $cb;
  $cb = sub {
    my $self = shift;
    $cb = undef unless my $chunk = shift @chunks || '';
    $self->write_chunk($chunk, $cb);
  };
  $self->$cb;
};

get '/params' => sub {
  my $self = shift;
  $self->render_json($self->req->params->to_hash);
};

# Simple
my $msg = '';
{
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
}
my $res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
is $res->code, 200, 'right status';
is $res->headers->status,         '200 OK', 'right "Status" value';
is $res->headers->content_length, 21,       'right "Content-Length" value';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
is $res->body, 'Your Mojo is working!', 'right content';

# HEAD request
$msg = '';
{
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
}
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
is $res->code, 200, 'right status';
is $res->headers->status,         '200 OK', 'right "Status" value';
is $res->headers->content_length, 21,       'right "Content-Length" value';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
is $res->body, '', 'no content';

# Non-parsed headers
$msg = '';
{
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
}
$res = Mojo::Message::Response->new->parse($msg);
is $res->code, 200, 'right status';
is $res->headers->status,         undef, 'no "Status" value';
is $res->headers->content_length, 21,    'right "Content-Length" value';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
is $res->body, 'Your Mojo is working!', 'right content';

# Chunked
my $content = 'test1=1&test2=2&test3=3&test4=4&test5=5&test6=6&test7=7';
$msg = '';
{
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
}
like $msg, qr/chunked/, 'is chunked';
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
is $res->code, 200, 'right status';
is $res->headers->status, '200 OK', 'right "Status" value';
is $res->body, '1234567', 'right content';

# Parameters
$msg = '';
{
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
}
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$msg");
is $res->code, 200, 'right status';
is $res->headers->status, '200 OK', 'right "Status" value';
is $res->headers->content_type, 'application/json',
  'right "Content-Type" value';
is $res->headers->content_length, 27, 'right "Content-Length" value';
is $res->json->{lalala}, 23,    'right value';
is $res->json->{bar},    'baz', 'right value';

done_testing();
