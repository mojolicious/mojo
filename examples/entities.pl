use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::Base -strict;

use Mojo::ByteStream 'b';
use Mojo::UserAgent;

# Extract named character references from HTML5 spec
my $tx = Mojo::UserAgent->new->get(
  'http://www.w3.org/html/wg/drafts/html/master/single-page.html');
b($_->at('td > code')->text . ' ' . $_->children('td')->[1]->text)->trim->say
  for $tx->res->dom('#named-character-references-table tbody > tr')->each;

1;
