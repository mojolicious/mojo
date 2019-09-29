#
# Extract named character references from HTML Living Standard
#
use Mojo::Base -strict;

use Mojo::UserAgent;
use Mojo::Util 'trim';

my $res = Mojo::UserAgent->new->get('https://html.spec.whatwg.org')->result;
for my $row ($res->dom('#named-character-references-table tbody > tr')->each) {
  my $entity     = trim $row->at('td > code')->text;
  my $codepoints = trim $row->children('td')->[1]->text;
  say "$entity $codepoints";
}

1;
