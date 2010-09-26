#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 3;

use Cwd;
use File::Spec;
use FindBin;

# Uh, no, you got the wrong number. This is 9-1... 2
use_ok 'Mojo::Home';

# detect env
my $backup = $ENV{MOJO_HOME} || '';
my $path = File::Spec->catdir(qw/foo bar baz/);
$ENV{MOJO_HOME} = $path;
my $home = Mojo::Home->new->detect;
is $home->to_string, $path, 'right path detected';
$ENV{MOJO_HOME} = $backup;

# detect directory
my $original =
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), '..', '..');
$home = Mojo::Home->new->detect;
is Cwd::realpath($original), Cwd::realpath("$home"), 'right path detected';
