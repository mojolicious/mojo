use Mojo::Base -strict;

BEGIN {
  $ENV{MOJO_MODE} = 'testing';
}

use Test::More tests => 5;

use FindBin;
use lib "$FindBin::Bin/external/lib";

use Test::Mojo;

is(Test::Mojo->new('MyModeApp')->app->config('key'),
  'val', 'Valid .[mode].conf file');

MISSING: {
  local $ENV{MOJO_MODE} = 'missing';
  ok !eval { Test::Mojo->new('MyModeApp')->app->config }, 'Can not load App';
  like "$@", qr{missing}, 'Dies without config file';
}


NOTVALID: {
  local $ENV{MOJO_MODE} = 'notvalid';
  ok !eval { Test::Mojo->new('MyModeApp')->app->config }, 'Can not load App';
  like "$@", qr{hash reference}, 'Dies when the file is not valid';
}
