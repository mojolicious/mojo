#!/usr/bin/env perl

use strict;
use warnings;

use lib 'lib';

use Test::More tests => 2;

# Windows Inline template
my $test_string =
    qq{@@ template1\r\n} .
    qq{First Template\r\n} .
    qq{@@ template2\r\n} .
    qq{Second Template\r\n};

open(my $fh, '<', \$test_string);
no strict 'refs';
*{"Example::Package::DATA"} = $fh;
use_ok 'Mojo::Command';

my $cmd = Mojo::Command->new;

like $cmd->get_data('template1', 'Example::Package'),
    qr/^First Template/, 'correct template';

close($fh);
