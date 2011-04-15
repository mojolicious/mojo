#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 11;

# "This is the greatest case of false advertising I’ve seen since I sued the
#  movie 'The Never Ending Story.'"
use_ok 'Mojo::Path';

my $path = Mojo::Path->new;
is $path->parse('/path')->to_string,   '/path',   'right path';
is $path->parse('/path/0')->to_string, '/path/0', 'right path';

# Canonicalizing
$path = Mojo::Path->new(
  '/%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd');
is "$path", '/../../../../../../../../../../etc/passwd', 'rigth result';
is $path->parts->[0], '..', 'right part';
is $path->canonicalize, '/../../../../../../../../../../etc/passwd',
  'rigth result';
is $path->parts->[0], '..', 'right part';
$path = Mojo::Path->new(
  '/%2ftest%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2f..%2fetc%2fpasswd');
is "$path", '/test/../../../../../../../../../etc/passwd', 'rigth result';
is $path->parts->[0], 'test', 'right part';
is $path->canonicalize, '/../../../../../../../../etc/passwd', 'rigth result';
is $path->parts->[0], '..', 'right part';
