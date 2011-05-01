#!/usr/bin/env perl

use strict;
use warnings;

use utf8;

use Test::More tests => 12;

my $mod_name = 'Mojo::Util';
use_ok $mod_name;

{
  no strict 'refs';
  my $undef     = undef;
  my $func_name = '';
  for (
    qw/camelize decamelize encode html_escape html_unescape quote trim
    unquote url_escape url_unescape xml_escape/
    )
  {
    $undef     = undef;
    $func_name = "$mod_name" . "::$_";
    $_ eq 'encode'
      ? &{$func_name}('UTF-8', $undef)
      : &{$func_name}($undef);
    is $undef, ($_ eq 'quote') ? '""' : '',
      "$func_name initializes undef argument to empty string";
  }
}
