#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

use File::Spec;
use File::Temp;
use IO::Socket::INET;
use Mojo::Client;
use Mojo::IOLoop;
use Mojo::Template;

# Mac OS X only test
plan skip_all => 'Mac OS X required for this test!' unless $^O eq 'darwin';
plan skip_all => 'set TEST_APACHE to enable this test (developer only!)'
  unless $ENV{TEST_APACHE};
plan tests => 8;

# Robots don't have any emotions, and sometimes that makes me very sad.
use_ok 'Mojo::Server::FastCGI';

# Setup
my $port   = Mojo::IOLoop->generate_port;
my $dir    = File::Temp::tempdir(CLEANUP => 1);
my $config = File::Spec->catfile($dir, 'fcgi.config');
my $mt     = Mojo::Template->new;

# FastCGI setup
my $fcgi = File::Spec->catfile($dir, 'test.fcgi');
$mt->render_to_file(<<'EOF', $fcgi);
#!/usr/bin/env perl

use strict;
use warnings;

% use FindBin;
use lib '<%= "$FindBin::Bin/../../lib" %>';

use Mojo::Server::FastCGI;

Mojo::Server::FastCGI->new->run;

1;
EOF
chmod 0777, $fcgi;
ok -x $fcgi, 'script is executable';

# Apache setup
$mt->render_to_file(<<'EOF', $config, $dir, $port, $fcgi);
% my ($dir, $port, $fcgi) = @_;
% use File::Spec::Functions 'catfile';
ServerName 127.0.0.1
Listen <%= $port %>

LoadModule log_config_module libexec/apache2/mod_log_config.so

ErrorLog <%= catfile $dir, 'error.log' %>

LoadModule alias_module libexec/apache2/mod_alias.so
LoadModule fastcgi_module libexec/apache2/mod_fastcgi.so

PidFile <%= catfile $dir, 'httpd.pid' %>
LockFile <%= catfile $dir, 'accept.lock' %>

DocumentRoot  <%= $dir %>

FastCgiIpcDir <%= $dir %>
FastCgiServer <%= $fcgi %> -processes 1
Alias / <%= $fcgi %>/
EOF

# Start
my $pid = open my $server, '-|', '/usr/sbin/httpd', '-X', '-f', $config;
sleep 1
  while !IO::Socket::INET->new(
    Proto    => 'tcp',
    PeerAddr => 'localhost',
    PeerPort => $port
  );

# Request
my $client = Mojo::Client->new;
my ($code, $body);
$client->get(
    "http://127.0.0.1:$port/" => sub {
        my $self = shift;
        $code = $self->res->code;
        $body = $self->res->body;
    }
)->start;
is $code,   200,      'right status';
like $body, qr/Mojo/, 'right content';

# Form with chunked response
my $params = {};
for my $i (1 .. 10) { $params->{"test$i"} = $i }
my $result = '';
for my $key (sort keys %$params) { $result .= $params->{$key} }
($code, $body) = undef;
$client->post_form(
    "http://127.0.0.1:$port/diag/chunked_params" => $params => sub {
        my $self = shift;
        $code = $self->res->code;
        $body = $self->res->body;
    }
)->start;
is $code, 200, 'right status';
is $body, $result, 'right content';

# Upload
($code, $body) = undef;
$client->post_form(
    "http://127.0.0.1:$port/diag/upload" => {file => {content => $result}} =>
      sub {
        my $self = shift;
        $code = $self->res->code;
        $body = $self->res->body;
    }
)->start;
is $code, 200, 'right status';
is $body, $result, 'right content';

# Stop
kill 'INT', $pid;
sleep 1
  while IO::Socket::INET->new(
    Proto    => 'tcp',
    PeerAddr => 'localhost',
    PeerPort => $port
  );
