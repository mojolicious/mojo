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
plan tests => 7;

# Hey, we didn't have a message on our answering machine when we left.
# How very odd.
use_ok('Mojo::Server::CGI');

# Lighttpd setup
my $server = Test::Mojo::Server->new;
my $port   = $server->generate_port_ok;
my $dir    = File::Temp::tempdir();
my $config = File::Spec->catfile($dir, 'cgi.config');
my $mt     = Mojo::Template->new;

$mt->render_to_file(<<'EOF', $config, $dir, $port);
% my ($dir, $port) = @_;
% use File::Spec::Functions 'catfile'
server.modules = (
    "mod_access",
    "mod_cgi",
    "mod_rewrite",
    "mod_accesslog"
)

server.document-root = "<%= $dir %>"
server.errorlog    = "<%= catfile $dir, 'error.log' %>"
accesslog.filename = "<%= catfile $dir, 'access.log' %>"

server.bind = "127.0.0.1"
server.port = <%= $port %>

cgi.assign = ( ".pl"  => "<%= $^X %>",
               ".cgi" => "<%= $^X %>" )
EOF
$server->command("lighttpd -D -f $config");

# CGI setup
my $lib = $server->home->lib_dir;
my $cgi = File::Spec->catfile($dir, 'test.cgi');
$mt->render_to_file(<<'EOF', $cgi, $lib);
#!<%= $^X %>

use strict;
use warnings;

use lib '<%= shift %>';

use Mojo::Server::CGI;

Mojo::Server::CGI->new->run;

1;
EOF
chmod 0777, $cgi;
ok(-x $cgi);

# Start
$server->start_server_ok;

# Request
my $tx     = Mojo::Transaction->new_get("http://127.0.0.1:$port/test.cgi");
my $client = Mojo::Client->new;
$client->process_all($tx);
is($tx->res->code, 200);
like($tx->res->body, qr/Mojo is working/);

# Stop
$server->stop_server_ok;
