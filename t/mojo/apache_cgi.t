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

plan skip_all => 'set TEST_APACHE to enable this test (developer only!)'
  unless $ENV{TEST_APACHE};
plan tests => 7;

# I'm not a robot!
# I don't like having discs crammed into me, unless they're Oreos.
# And then, only in the mouth.
use_ok('Mojo::Server::CGI');

# Apache setup
my $server = Test::Mojo::Server->new;
my $port   = $server->generate_port_ok;
my $dir    = File::Temp::tempdir();
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
$server->command("/usr/sbin/httpd -X -f $config");

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
my $client = Mojo::Client->new;
$client->get(
    "http://127.0.0.1:$port/cgi-bin/test.cgi" => sub {
        my ($self, $tx) = @_;
        is($tx->res->code, 200);
        like($tx->res->body, qr/Mojo is working/);
    }
)->process;

# Stop
$server->stop_server_ok;
