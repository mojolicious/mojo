#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 9;

use_ok 'Mojo::Util', 'decamelize';

{
    my %set = (
        'no camel' => 'no camel',
        'Camel' => 'camel',
        'CamelCase' => 'camel_case',
        'Camel::Case' => 'camel-case',
        'FOO'        => 'foo',
        'FOO::BAR'   => 'foo-bar',
        'FooBAR'     => 'foo_bar',
        'BARFoo'     => 'bar_foo',
    );
    while ( my ($orig, $expected) = each %set ) {
        decamelize( my $got = $orig );
        is $got, $expected, "correctly decamelized '$orig'";
    }
}
