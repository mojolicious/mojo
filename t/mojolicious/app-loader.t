use Mojo::Base -strict;

use Test::More;

use FindBin;
use lib "$FindBin::Bin/lib";

use Mojolicious;
use Test::Mojo;

my $t = Test::Mojo->new('MojoliciousLoaderTest');


# Application is already available
$t->get_ok('/bar')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from the other template \/bar!/);

$t->get_ok('/foo')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from the template \/foo!/);

$t->get_ok('/bar')->status_is(200)
  ->header_is(Server => 'Mojolicious (Perl)')
  ->content_like(qr/Hello Mojo from the other template \/bar!/);

done_testing();
