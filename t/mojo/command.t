#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 7;

# "My cat's breath smells like cat food."
use_ok 'Mojo::Command';

my $command = Mojo::Command->new;

# UNIX DATA templates
my $unix = "@@ template1\nFirst Template\n@@ template2\r\nSecond Template\n";
open my $data, '<', \$unix;
no strict 'refs';
*{"Example::Package::UNIX::DATA"} = $data;
is $command->get_data('template1', 'Example::Package::UNIX'),
  "First Template\n", 'right template';
is $command->get_data('template2', 'Example::Package::UNIX'),
  "Second Template\n", 'right template';
is_deeply [sort keys %{$command->get_all_data('Example::Package::UNIX')}],
  [qw/template1 template2/], 'right DATA files';
close $data;

# Windows DATA templates
my $windows =
  "@@ template3\r\nThird Template\r\n@@ template4\r\nFourth Template\r\n";
open $data, '<', \$windows;
no strict 'refs';
*{"Example::Package::Windows::DATA"} = $data;
is $command->get_data('template3', 'Example::Package::Windows'),
  "Third Template\r\n", 'right template';
is $command->get_data('template4', 'Example::Package::Windows'),
  "Fourth Template\r\n", 'right template';
is_deeply [sort keys %{$command->get_all_data('Example::Package::Windows')}],
  [qw/template3 template4/], 'right DATA files';
close $data;
