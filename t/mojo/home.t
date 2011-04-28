#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 5;

use Cwd qw/cwd realpath/;
use File::Spec;
use FindBin;

# "Uh, no, you got the wrong number. This is 9-1... 2"
use_ok 'Mojo::Home';

# ENV detection
my $backup = $ENV{MOJO_HOME} || '';
$ENV{MOJO_HOME} = '.';
my $home = Mojo::Home->new->detect;
is_deeply [split /\\|\//, File::Spec->canonpath($home->to_string)],
  [split /\\|\//, File::Spec->canonpath(realpath cwd())],
  'right path detected';
$ENV{MOJO_HOME} = $backup;

# Class detection
my $original =
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), '..', '..');
$home = Mojo::Home->new->detect;
my $target = realpath $original;
is_deeply [split /\\|\//, $target], [split /\\|\//, $home],
  'right path detected';

# Specific class detection
$INC{'MyClass.pm'} = 'MyClass.pm';
$home = Mojo::Home->new->detect('MyClass');
is_deeply [split /\\|\//, File::Spec->canonpath($home->to_string)],
  [split /\\|\//, File::Spec->canonpath(realpath cwd())],
  'right path detected';

# FindBin detection
$home = Mojo::Home->new->app_class(undef)->detect;
is_deeply [split /\\|\//,
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin))],
  [split /\\|\//, $home], 'right path detected';
