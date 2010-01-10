#!/usr/bin/env perl

# Copyright (C) 2008-2010, Sebastian Riedel.

use strict;
use warnings;

use Test::More;

use File::Spec;
use File::Temp;
use Mojo::Client;
use Mojo::Template;
use Test::Mojo::Server;

plan skip_all => 'set TEST_LIGHTTPD to enable this test (developer only!)'
  unless $ENV{TEST_LIGHTTPD};
plan tests => 7;

# They think they're so high and mighty,
# just because they never got caught driving without pants.
use_ok('Mojo::Server::FastCGI');

# Setup
my $server = Test::Mojo::Server->new;
my $port   = $server->generate_port_ok;
my $dir    = File::Temp::tempdir();
my $config = File::Spec->catfile($dir, 'fcgi.config');
my $mt     = Mojo::Template->new;

# FastCGI setup
my $fcgi = File::Spec->catfile($dir, 'test.fcgi');
$mt->render_to_file(<<'EOF', $fcgi);
#!<%= $^X %>

use strict;
use warnings;

% use FindBin;
use lib '<%= "$FindBin::Bin/../../lib" %>';

use Mojo::Server::FastCGI;

Mojo::Server::FastCGI->new->run;

1;
EOF
chmod 0777, $fcgi;
ok(-x $fcgi);

$mt->render_to_file(<<'EOF', $config, $dir, $port, $fcgi);
% my ($dir, $port, $fcgi) = @_;
% use File::Spec::Functions 'catfile';
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
            "bin-path"        => "<%= $fcgi %> fastcgi",
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
my $client = Mojo::Client->new;
$client->get(
    "http://127.0.0.1:$port/test/" => sub {
        my ($self, $tx) = @_;
        is($tx->res->code, 200);
        like($tx->res->body, qr/Mojo is working/);
    }
)->process;

# Stop
$server->stop_server_ok;
