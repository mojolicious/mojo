#!perl

# Copyright (C) 2008, Sebastian Riedel.

use strict;
use warnings;

use Test::More tests => 2;

use File::Spec;

# Uh, no, you got the wrong number. This is 9-1... 2
use_ok('Mojo::Home');

# detect env
my $backup = $ENV{MOJO_HOME} || '';
my $path = File::Spec->catdir(qw/foo bar baz/);
$ENV{MOJO_HOME} = $path;
my $home = Mojo::Home->new;
is($home->to_string, $path);
$ENV{MOJO_HOME} = $backup;