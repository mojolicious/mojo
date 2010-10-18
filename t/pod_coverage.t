#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;

eval "use Test::Pod::Coverage 1.04";
plan skip_all => 'Test::Pod::Coverage 1.04 required for this test!' if $@;
plan skip_all => 'set TEST_POD to enable this test (developer only!)'
  unless $ENV{TEST_POD};

# DEPRECATED in Comet!
my @client  = qw/max_keep_alive_connections process/;
my @ioloop  = qw/error_cb hup_cb idle_cb lock_cb read_cb tick_cb unlock_cb/;
my @message = qw/finish_cb progress_cb/;
my @server =
  qw/build_tx_cb handler_cb max_keep_alive_requests websocket_handshake_cb/;
my @tx = qw/finished helper receive_message resume_cb upgrade_cb/;

# Marge, I'm going to miss you so much. And it's not just the sex.
# It's also the food preparation.
all_pod_coverage_ok(
    {also_private => [@client, @ioloop, @message, @server, @tx]});
