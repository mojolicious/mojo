use Mojo::Base -strict;
use Mojo::UserAgent;

# Extract named character references from HTML Living Standard
my $tx   = Mojo::UserAgent->new->get('https://html.spec.whatwg.org');
my $rows = $tx->res->dom('#named-character-references-table tbody > tr');
for my $row ($rows->each) {
  my $entity     = $row->at('td > code')->text;
  my $codepoints = $row->children('td')->[1]->text;
  say "$entity $codepoints";
}

1;
