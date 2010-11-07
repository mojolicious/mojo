#!/usr/bin/env perl

use strict;
use warnings;

# Disable epoll, kqueue and IPv6
BEGIN { $ENV{MOJO_POLL} = $ENV{MOJO_NO_IPV6} = 1 }

use Test::More;

use File::Spec;
use File::Temp;
use FindBin;
use IO::Socket::INET;
use Mojo::Client;
use Mojo::IOLoop;
use Mojo::Template;

# Mac OS X only test
plan skip_all => 'Mac OS X required for this test!' unless $^O eq 'darwin';
plan skip_all => 'set TEST_APACHE to enable this test (developer only!)'
  unless $ENV{TEST_APACHE};
plan tests => 8;

# I'm not a robot!
# I don't like having discs crammed into me, unless they're Oreos.
# And then, only in the mouth.
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

LoadModule log_config_module libexec/apache2/mod_log_config.so

ErrorLog <%= catfile $dir, 'error.log' %>

LoadModule alias_module libexec/apache2/mod_alias.so
LoadModule cgi_module libexec/apache2/mod_cgi.so

PidFile <%= catfile $dir, 'httpd.pid' %>
LockFile <%= catfile $dir, 'accept.lock' %>

DocumentRoot  <%= $dir %>

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
my $client = Mojo::Client->new;
my ($code, $body);
$client->get(
    "http://127.0.0.1:$port/cgi-bin/test.cgi" => sub {
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
    "http://127.0.0.1:$port/cgi-bin/test.cgi/diag/chunked_params" =>
      $params => sub {
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
    "http://127.0.0.1:$port/cgi-bin/test.cgi/diag/upload" =>
      {file => {content => $result}} => sub {
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
