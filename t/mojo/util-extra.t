use Mojo::Base -strict;

use FindBin;
use lib "$FindBin::Bin/lib";
use Test::More;

{ # Test for https://github.com/kraih/mojo/issues/849
  local $/ = "\0";
  require Mojo::Util;
  # html_unescape (nothing to unescape)
  is Mojo::Util::html_unescape('&amp;'),
    '&', 'right HTML unescaped result';
}

done_testing();
