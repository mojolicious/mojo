#!perl

use strict;
use warnings;

use Test::More tests => 3;

use_ok('Mojo::Path');

my $parser = Mojo::Path->new;
is($parser->parse('/path')->to_string, '/path');
is($parser->parse('/path/0')->to_string, '/path/0');
