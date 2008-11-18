#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

use File::Spec;
use File::Temp;
use Mojo::Client;
use Mojo::Template;
use Mojo::Transaction;
use Test::Mojo::Server;

plan skip_all => 'set TEST_LIGHTTPD to enable this test (developer only!)'
  unless $ENV{TEST_LIGHTTPD};
plan tests => 6;

# They think they're so high and mighty,
# just because they never got caught driving without pants.
use_ok('Mojo::Server::FastCGI');

# Setup
my $server = Test::Mojo::Server->new;
my $port   = $server->generate_port_ok;
my $script = $server->home->executable;
my $dir    = File::Temp::tempdir();
my $config = File::Spec->catfile($dir, 'fcgi.config');
my $mt     = Mojo::Template->new;

$mt->render_to_file(<<'EOF', $config, $dir, $port, $script);
% my ($dir, $port, $script) = @_;
% use File::Spec::Functions 'catfile'
server.modules = (
    "mod_access",
    "mod_fastcgi",
    "mod_rewrite",
    "mod_accesslog"
)

server.document-root = "<%= $dir %>"
server.errorlog    = "<%= catfile $dir, 'error.log' %>"
accesslog.filename = "<%= catfile $dir, 'access.log' %>"

server.bind = "127.0.0.1"
server.port = <%= $port %>

fastcgi.server = (
    "/test" => (
        "FastCgiTest" => (
            "socket"          => "<%= catfile $dir, 'test.socket' %>",
            "check-local"     => "disable",
            "bin-path"        => "<%= $script %> fastcgi",
            "min-procs"       => 1,
            "max-procs"       => 1,
            "idle-timeout"    => 20
        )
    )
)
EOF

# Start
$server->command("lighttpd -D -f $config");
$server->start_server_ok;

# Request
my $tx     = Mojo::Transaction->new_get("http://127.0.0.1:$port/test/");
my $client = Mojo::Client->new;
$client->process_all($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Mojo is working/);

# Stop
$server->stop_server_ok;
