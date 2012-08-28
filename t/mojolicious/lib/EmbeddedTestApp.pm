package EmbeddedTestApp;
use Mojolicious::Lite;

plugin "JSONConfig";

get '/works';

get '/works/too' => 'too';

1;
__DATA__
@@ works.html.ep
It is <%= $name %>!

@@ too.html.ep
It <%= config->{it} %>!
