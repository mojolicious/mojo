use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE}    = 'testing';
  $ENV{MOJO_REACTOR} = 'Mojo::Reactor::Poll';
}

use Test::More;

use Mojo::File qw(curfile);
use lib curfile->sibling('external', 'lib')->to_string;

use Test::Mojo;

my $t = Test::Mojo->new('MyApp');

# Text from config file
$t->get_ok('/')->status_is(200)->content_is('too%21');

# Static file
$t->get_ok('/index.html')->status_is(200)
  ->content_is("External static file!\n");

# More text from config file
$t->get_ok('/test')->status_is(200)->content_is('works%21');

# Config override
$t = Test::Mojo->new(
  MyApp => {whatever => 'override!', works => 'override two!'});

# Text from config override
$t->get_ok('/')->status_is(200)->content_is('override two!');

# Static file again
$t->get_ok('/index.html')->status_is(200)
  ->content_is("External static file!\n");

# More text from config override
$t->get_ok('/test')->status_is(200)->content_is('override!');

# Config stash value from template
$t->get_ok('/inline')->status_is(200)->content_is('override!');

done_testing();
