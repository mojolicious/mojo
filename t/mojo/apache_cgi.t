#!/usr/bin/env perl

use strict;
use warnings;

# Disable IPv6, epoll and kqueue
BEGIN { $ENV{MOJO_NO_IPV6} = $ENV{MOJO_POLL} = 1 }

use Test::More;

use File::Spec;
use File::Temp;
use FindBin;
use IO::Socket::INET;
use Mojo::IOLoop;
use Mojo::Template;
use Mojo::UserAgent;

# Mac OS X only test
plan skip_all => 'Mac OS X required for this test!' unless $^O eq 'darwin';
plan skip_all => 'set TEST_APACHE to enable this test (developer only!)'
  unless $ENV{TEST_APACHE};
plan tests => 12;

# "I'm not a robot!
#  I don't like having discs crammed into me, unless they're Oreos.
#  And then, only in the mouth."
use_ok 'Mojo::Server::CGI';

# Apache setup
my $port   = Mojo::IOLoop->generate_port;
my $dir    = File::Temp::tempdir(CLEANUP => 1);
my $config = File::Spec->catfile($dir, 'cgi.config');
my $mt     = Mojo::Template->new;

$mt->render_to_file(<<'EOF', $config, $dir, $port);
% my ($dir, $port) = @_;
% use File::Spec::Functions 'catfile';
ServerName 127.0.0.1
Listen <%= $port %>
DocumentRoot  <%= $dir %>

LoadModule log_config_module libexec/apache2/mod_log_config.so

ErrorLog <%= catfile $dir, 'error.log' %>

LoadModule alias_module libexec/apache2/mod_alias.so
LoadModule cgi_module libexec/apache2/mod_cgi.so

PidFile <%= catfile $dir, 'httpd.pid' %>
LockFile <%= catfile $dir, 'accept.lock' %>

ScriptAlias /cgi-bin <%= $dir %>
EOF

# CGI setup
my $lib = "$FindBin::Bin/../../lib";
my $cgi = File::Spec->catfile($dir, 'test.cgi');
$mt->render_to_file(<<'EOF', $cgi, $lib);
#!/usr/bin/env perl

use strict;
use warnings;

use lib '<%= shift %>';

use Mojo::Server::CGI;

Mojo::Server::CGI->new->run;

1;
EOF
chmod 0777, $cgi;
ok -x $cgi, 'script is executable';

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
my $tx = $ua->get("http://127.0.0.1:$port/cgi-bin/test.cgi");
is $tx->res->code, 200, 'right status';
is $tx->res->headers->content_length, 21, 'right "Content-Length" value';
like $tx->res->body, qr/Mojo/, 'right content';

# HEAD request
$tx = $ua->head("http://127.0.0.1:$port/cgi-bin/test.cgi");
is $tx->res->code, 200, 'right status';
is $tx->res->headers->content_length, 21, 'right "Content-Length" value';
is $tx->res->body, '', 'no content';

# Form with chunked response
my $params = {};
for my $i (1 .. 10) { $params->{"test$i"} = $i }
my $result = '';
for my $key (sort keys %$params) { $result .= $params->{$key} }
my ($code, $body);
$tx = $ua->post_form(
  "http://127.0.0.1:$port/cgi-bin/test.cgi/diag/chunked_params" => $params);
is $tx->res->code, 200, 'right status';
is $tx->res->body, $result, 'right content';

# Upload
($code, $body) = undef;
$tx =
  $ua->post_form("http://127.0.0.1:$port/cgi-bin/test.cgi/diag/upload" =>
    {file => {content => $result}});
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
