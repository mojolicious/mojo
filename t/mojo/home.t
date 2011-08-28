#!/usr/bin/env perl
use Mojo::Base -strict;

use Test::More tests => 13;

use Cwd qw/cwd realpath/;
use File::Spec;
use FindBin;
use List::Util 'first';

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

# Path generation
$home = Mojo::Home->new->parse($FindBin::Bin);
is $home->lib_dir,
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), 'lib'),
  'right path';
is $home->rel_file('foo.txt'),
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), 'foo.txt'),
  'right path';
is $home->rel_file('foo/bar.txt'),
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), 'foo', 'bar.txt'),
  'right path';
is $home->rel_dir('foo'),
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), 'foo'),
  'right path';
is $home->rel_dir('foo/bar'),
  File::Spec->catdir(File::Spec->splitdir($FindBin::Bin), 'foo', 'bar'),
  'right path';

# List files
is first(sub { $_ =~ /Base1\.pm$/ }, @{$home->list_files('lib')}),
  'BaseTest/Base1.pm', 'right result';
is first(sub { $_ =~ /Base2\.pm$/ }, @{$home->list_files('lib')}),
  'BaseTest/Base2.pm', 'right result';
is first(sub { $_ =~ /Base3\.pm$/ }, @{$home->list_files('lib')}),
  'BaseTest/Base3.pm', 'right result';
