use Mojo::Base -strict;

use Test::More tests => 18;

# "My ears are burning.
#  I wasn't talking about you, Dad.
#  No, my ears are really burning. I wanted to see inside, so I lit a Q-tip."
use Mojo::Message::Response;
use Mojo::Server::CGI;
use Mojolicious::Command::cgi;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

# GET /
get '/' => {text => 'Your Mojo is working!'};

# POST /chunked
post '/chunked' => sub {
  my $self = shift;

  my $params = $self->req->params->to_hash;
  my $chunks = [];
  for my $key (sort keys %$params) {
    push @$chunks, $params->{$key};
  }

  my $cb;
  $cb = sub {
    my $self = shift;
    $cb = undef unless my $chunk = shift @$chunks || '';
    $self->write_chunk($chunk, $cb);
  };
  $self->$cb();
};

# GET /params
get '/params' => sub {
  my $self = shift;
  $self->render_json($self->req->params->to_hash);
};

# Simple
my $message = '';
{
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    MOJO_APP        => $ENV{MOJO_APP},
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run;
}
my $res =
  Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$message");
is $res->code, 200, 'right status';
is $res->headers->status, '200 OK', 'right "Status" value';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
like $res->body, qr/Mojo/, 'right content';

# Non-parsed headers
$message = '';
{
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    MOJO_APP        => $ENV{MOJO_APP},
    PATH_INFO       => '/',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run('--nph');
}
$res = Mojo::Message::Response->new->parse($message);
is $res->code, 200, 'right status';
is $res->headers->status, undef, 'no "Status" value';
is $res->headers->content_type, 'text/html;charset=UTF-8',
  'right "Content-Type" value';
like $res->body, qr/Mojo/, 'right content';

# Chunked
my $content = 'test1=1&test2=2&test3=3&test4=4&test5=5&test6=6&test7=7';
$message = '';
{
  local *STDIN;
  open STDIN, '<', \$content;
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    MOJO_APP        => $ENV{MOJO_APP},
    PATH_INFO       => '/chunked',
    CONTENT_LENGTH  => length($content),
    CONTENT_TYPE    => 'application/x-www-form-urlencoded',
    REQUEST_METHOD  => 'POST',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run;
}
like $message, qr/chunked/, 'is chunked';
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$message");
is $res->code, 200, 'right status';
is $res->headers->status, '200 OK', 'right "Status" value';
is $res->body, '1234567', 'right content';

# Parameters
$message = '';
{
  local *STDOUT;
  open STDOUT, '>', \$message;
  local %ENV = (
    MOJO_APP        => $ENV{MOJO_APP},
    PATH_INFO       => '/params',
    QUERY_STRING    => 'lalala=23&bar=baz',
    REQUEST_METHOD  => 'GET',
    SCRIPT_NAME     => '/',
    HTTP_HOST       => 'localhost:8080',
    SERVER_PROTOCOL => 'HTTP/1.0'
  );
  Mojolicious::Command::cgi->new->run;
}
$res = Mojo::Message::Response->new->parse("HTTP/1.1 200 OK\x0d\x0a$message");
is $res->code, 200, 'right status';
is $res->headers->status, '200 OK', 'right "Status" value';
is $res->headers->content_type, 'application/json',
  'right "Content-Type" value';
is $res->headers->content_length, 27, 'right "Content-Length" value';
is $res->json->{lalala}, 23,    'right value';
is $res->json->{bar},    'baz', 'right value';
