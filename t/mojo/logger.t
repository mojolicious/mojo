#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 1;

use Mojo::Log;

use utf8;

my $logger = Mojo::Log->new;
$logger->path(undef);

eval { $logger->log->debug('ошибка'); };
ok(!$@, 'Logging utf8 data to stderr');
