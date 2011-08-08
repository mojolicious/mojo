#!/usr/bin/env perl
use Mojo::Base -strict;

# Disable Bonjour, IPv6 and libev
BEGIN {
  $ENV{MOJO_NO_BONJOUR} = $ENV{MOJO_NO_IPV6} = 1;
  $ENV{MOJO_IOWATCHER} = 'Mojo::IOWatcher';
}

# mod_fastcgi doesn't like small chunks
BEGIN { $ENV{MOJO_CHUNK_SIZE} = 131072 }

use Test::More;

use File::Spec;
use File::Temp;
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Template;
use Mojo::UserAgent;

# Mac OS X only test
plan skip_all => 'Mac OS X required for this test!' unless $^O eq 'darwin';
plan skip_all => 'set TEST_APACHE to enable this test (developer only!)'
  unless $ENV{TEST_APACHE};
plan tests => 12;

# "Robots don't have any emotions, and sometimes that makes me very sad."
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
% use File::Spec;
ServerName 127.0.0.1
Listen <%= $port %>
DocumentRoot  <%= $dir %>

LoadModule log_config_module libexec/apache2/mod_log_config.so

ErrorLog <%= File::Spec->catfile($dir, 'error.log') %>

LoadModule alias_module libexec/apache2/mod_alias.so
LoadModule fastcgi_module libexec/apache2/mod_fastcgi.so

PidFile <%= File::Spec->catfile($dir, 'httpd.pid') %>
LockFile <%= File::Spec->catfile($dir, 'accept.lock') %>

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
my $ua = Mojo::UserAgent->new;
my $tx = $ua->get("http://127.0.0.1:$port/");
is $tx->res->code, 200, 'right status';
is $tx->res->headers->content_length, 21, 'right "Content-Length" value';
is $tx->res->body, 'Your Mojo is working!', 'right content';

# HEAD request
$tx = $ua->head("http://127.0.0.1:$port/");
is $tx->res->code, 200, 'right status';
is $tx->res->headers->content_length, 21, 'right "Content-Length" value';
is $tx->res->body, '', 'no content';

# Form with chunked response
my $params = {};
for my $i (1 .. 10) { $params->{"test$i"} = $i }
my $result = '';
for my $key (sort keys %$params) { $result .= $params->{$key} }
my ($code, $body);
$tx = $ua->post_form("http://127.0.0.1:$port/diag/chunked_params" => $params);
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Upload
($code, $body) = undef;
$tx = $ua->post_form(
  "http://127.0.0.1:$port/diag/upload" => {file => {content => $result}});
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Stop
kill 'INT', $pid;
sleep 1
  while IO::Socket::INET->new(
  Proto    => 'tcp',
  PeerAddr => 'localhost',
  PeerPort => $port
  );
