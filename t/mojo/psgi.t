use Mojo::Base -strict;

use Test::More;
use Mojo::JSON qw(decode_json);
use Mojo::Server::PSGI;
use Mojolicious::Command::psgi;
use Mojolicious::Lite;

# Silence
app->log->level('fatal');

under sub {
  shift->on(finish => sub { $ENV{MOJO_HELLO} = 'world' });
};

get '/' => {text => 'Your Mojo is working!'};

get '/cookies' => sub {
  my $c      = shift;
  my $params = $c->req->params->to_hash;
  for my $key (sort keys %$params) { $c->cookie($key, $params->{$key}) }
  $c->render(text => 'nomnomnom');
};

post '/params' => sub {
  my $c = shift;
  $c->render(json => $c->req->params->to_hash);
};

get '/proxy' => sub {
  my $c       = shift;
  my $reverse = join ':', grep {length} $c->tx->remote_address, $c->req->url->to_abs->protocol;
  $c->render(text => $reverse);
};

subtest 'Reverse proxy' => sub {
  ok !Mojo::Server::PSGI->new->reverse_proxy, 'no reverse proxy';
  local $ENV{MOJO_REVERSE_PROXY} = 1;
  ok !!Mojo::Server::PSGI->new->reverse_proxy, 'reverse proxy';
};

subtest 'Binding' => sub {
  my @server;
  app->hook(
    before_server_start => sub {
      my ($server, $app) = @_;
      push @server, ref $server, $app->mode;
    }
  );
  my $app     = Mojo::Server::PSGI->new(app => app)->to_psgi_app;
  my $content = 'hello=world';
  open my $body, '<', \$content;
  my $env = {
    CONTENT_LENGTH      => 11,
    CONTENT_TYPE        => 'application/x-www-form-urlencoded',
    PATH_INFO           => '/params',
    QUERY_STRING        => 'lalala=23&bar=baz',
    REQUEST_METHOD      => 'POST',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.0',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => $body,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
  };
  my $res = $app->($env);
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  ok keys(%headers) >= 3, 'enough headers';
  ok $headers{Date},      'has "Date" value';
  is $headers{'Content-Length'}, 43,                               'right "Content-Length" value';
  is $headers{'Content-Type'},   'application/json;charset=UTF-8', 'right "Content-Type" value';
  my $params = '';
  while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
  is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
  is_deeply decode_json($params), {bar => 'baz', hello => 'world', lalala => 23}, 'right structure';
  is_deeply \@server, ['Mojo::Server::PSGI', 'development'], 'hook has been emitted once';
};

subtest 'Command' => sub {
  my $content = 'world=hello';
  open my $body, '<', \$content;
  my $env = {
    CONTENT_LENGTH      => 11,
    CONTENT_TYPE        => 'application/x-www-form-urlencoded',
    PATH_INFO           => '/params',
    QUERY_STRING        => 'lalala=23&bar=baz',
    REQUEST_METHOD      => 'POST',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.0',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => $body,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
  };
  my $app = Mojolicious::Command::psgi->new(app => app)->run;
  my $res = $app->($env);
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  ok keys(%headers) >= 3, 'enough headers';
  ok $headers{Date},      'has "Date" value';
  is $headers{'Content-Length'}, 43,                               'right "Content-Length" value';
  is $headers{'Content-Type'},   'application/json;charset=UTF-8', 'right "Content-Type" value';
  my $params = '';
  while (defined(my $chunk = $res->[2]->getline)) { $params .= $chunk }
  is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
  is_deeply decode_json($params), {bar => 'baz', world => 'hello', lalala => 23}, 'right structure';
};

subtest 'Simple' => sub {
  my $env = {
    CONTENT_LENGTH      => 0,
    PATH_INFO           => '/',
    REQUEST_METHOD      => 'GET',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.1',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => *STDIN,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
  };
  my $app = Mojolicious::Command::psgi->new(app => app)->run;
  my $res = $app->($env);
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  is $headers{'Content-Length'}, 21,                        'right "Content-Length" value';
  is $headers{'Content-Type'},   'text/html;charset=UTF-8', 'right "Content-Type" value';
  my $body = '';
  while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
  is $body,            'Your Mojo is working!', 'right content';
  is $ENV{MOJO_HELLO}, undef,                   'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
};

subtest 'HEAD request' => sub {
  my $env = {
    CONTENT_LENGTH      => 0,
    PATH_INFO           => '/',
    REQUEST_METHOD      => 'HEAD',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.1',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => *STDIN,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
  };
  my $app = Mojolicious::Command::psgi->new(app => app)->run;
  my $res = $app->($env);
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  is $headers{'Content-Length'}, 21,                        'right "Content-Length" value';
  is $headers{'Content-Type'},   'text/html;charset=UTF-8', 'right "Content-Type" value';
  my $body = '';
  while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
  is $body,            '',    'no content';
  is $ENV{MOJO_HELLO}, undef, 'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
};

subtest 'Cookies' => sub {
  my $env = {
    CONTENT_LENGTH      => 0,
    PATH_INFO           => '/cookies',
    QUERY_STRING        => 'lalala=23&bar=baz',
    REQUEST_METHOD      => 'GET',
    SCRIPT_NAME         => '/',
    HTTP_HOST           => 'localhost:8080',
    SERVER_PROTOCOL     => 'HTTP/1.1',
    'psgi.version'      => [1, 0],
    'psgi.url_scheme'   => 'http',
    'psgi.input'        => *STDIN,
    'psgi.errors'       => *STDERR,
    'psgi.multithread'  => 0,
    'psgi.multiprocess' => 1,
    'psgi.run_once'     => 0
  };
  my $app = Mojolicious::Command::psgi->new(app => app)->run;
  my $res = $app->($env);
  is $res->[0], 200, 'right status';
  ok scalar @{$res->[1]} >= 10, 'enough headers';
  my $i = 0;
  for my $header (@{$res->[1]}) { $i++ if $header eq 'Set-Cookie' }
  is $i, 2, 'right number of "Set-Cookie" headers';
};

subtest 'Reverse proxy' => sub {
  my $env = {
    CONTENT_LENGTH         => 0,
    PATH_INFO              => '/proxy',
    REQUEST_METHOD         => 'GET',
    SCRIPT_NAME            => '/',
    HTTP_HOST              => 'localhost:8080',
    SERVER_PROTOCOL        => 'HTTP/1.1',
    HTTP_X_FORWARDED_FOR   => '192.0.2.2, 192.0.2.1',
    HTTP_X_FORWARDED_PROTO => 'https',
    'psgi.version'         => [1, 0],
    'psgi.url_scheme'      => 'http',
    'psgi.input'           => *STDIN,
    'psgi.errors'          => *STDERR,
    'psgi.multithread'     => 0,
    'psgi.multiprocess'    => 1,
    'psgi.run_once'        => 0
  };
  my ($app, $res);
  {
    local $ENV{MOJO_REVERSE_PROXY} = 1;
    $app = Mojolicious::Command::psgi->new(app => app)->run;
    $res = $app->($env);
  }
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  is $headers{'Content-Length'}, 15,                        'right "Content-Length" value';
  is $headers{'Content-Type'},   'text/html;charset=UTF-8', 'right "Content-Type" value';
  my $body = '';
  while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
  is $body,            '192.0.2.1:https', 'right content';
  is $ENV{MOJO_HELLO}, undef,             'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
};

subtest 'Trusted proxies' => sub {
  my $env = {
    CONTENT_LENGTH         => 0,
    PATH_INFO              => '/proxy',
    REQUEST_METHOD         => 'GET',
    SCRIPT_NAME            => '/',
    HTTP_HOST              => 'localhost:8080',
    REMOTE_ADDR            => '127.0.0.1',
    SERVER_PROTOCOL        => 'HTTP/1.1',
    HTTP_X_FORWARDED_FOR   => '10.10.10.10, 192.0.2.2, 192.0.2.1',
    HTTP_X_FORWARDED_PROTO => 'https',
    'psgi.version'         => [1, 0],
    'psgi.url_scheme'      => 'http',
    'psgi.input'           => *STDIN,
    'psgi.errors'          => *STDERR,
    'psgi.multithread'     => 0,
    'psgi.multiprocess'    => 1,
    'psgi.run_once'        => 0
  };
  my ($app, $res);
  {
    local $ENV{MOJO_TRUSTED_PROXIES} = '127.0.0.0/8, 192.0.0.0/8';
    $app = Mojolicious::Command::psgi->new(app => app)->run;
    $res = $app->($env);
  }
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  is $headers{'Content-Length'}, 17,                        'right "Content-Length" value';
  is $headers{'Content-Type'},   'text/html;charset=UTF-8', 'right "Content-Type" value';
  my $body = '';
  while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
  is $body,            '10.10.10.10:https', 'right content';
  is $ENV{MOJO_HELLO}, undef,               'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
};

subtest 'Trusted proxies (no REMOTE_ADDR)' => sub {
  my $env = {
    CONTENT_LENGTH           => 0,
    PATH_INFO                => '/proxy',
    REQUEST_METHOD           => 'GET',
    SCRIPT_NAME              => '/',
    HTTP_HOST                => 'localhost:8080',
    SERVER_PROTOCOL          => 'HTTP/1.1',
    'HTTP_X_Forwarded_For'   => '10.10.10.10, 192.0.2.2, 192.0.2.1',
    'HTTP_X_Forwarded_Proto' => 'https',
    'psgi.version'           => [1, 0],
    'psgi.url_scheme'        => 'http',
    'psgi.input'             => *STDIN,
    'psgi.errors'            => *STDERR,
    'psgi.multithread'       => 0,
    'psgi.multiprocess'      => 1,
    'psgi.run_once'          => 0
  };
  my ($app, $res);
  {
    local $ENV{MOJO_TRUSTED_PROXIES} = '127.0.0.0/8, 192.0.0.0/8';
    $app = Mojolicious::Command::psgi->new(app => app)->run;
    $res = $app->($env);
  }
  is $res->[0], 200, 'right status';
  my %headers = @{$res->[1]};
  is $headers{'Content-Length'}, 5,                         'right "Content-Length" value';
  is $headers{'Content-Type'},   'text/html;charset=UTF-8', 'right "Content-Type" value';
  my $body = '';
  while (defined(my $chunk = $res->[2]->getline)) { $body .= $chunk }
  is $body,            'https', 'right content';
  is $ENV{MOJO_HELLO}, undef,   'finish event has not been emitted';
  $res->[2]->close;
  is delete $ENV{MOJO_HELLO}, 'world', 'finish event has been emitted';
};

done_testing();
