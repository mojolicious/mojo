use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojo::Base -strict;

# "She's built like a steakhouse, but she handles like a bistro!"
use Mojo::UserAgent;

# Extract named character references from HTML5 spec
Mojo::UserAgent->new->get('http://dev.w3.org/html5/spec/single-page.html')
  ->res->dom("#named-character-references-table tbody > tr")
  ->each(sub { say $_->at("td > code")->text, $_->children("td")->[1]->text });

1;
