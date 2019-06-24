#
# Extract named character references from HTML Living Standard
#
use Mojo::Base -strict;
use Mojo::UserAgent;

my $res = Mojo::UserAgent->new->get('https://html.spec.whatwg.org')->result;
for my $row ($res->dom('#named-character-references-table tbody > tr')->each) {
  my $entity     = $row->at('td > code')->text;
  my $codepoints = $row->children('td')->[1]->text;
  say "$entity $codepoints";
}

1;
