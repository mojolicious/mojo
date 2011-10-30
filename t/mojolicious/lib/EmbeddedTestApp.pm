package EmbeddedTestApp;
use Mojolicious::Lite;

plugin "JSONConfig";

# "But you're better than normal, you're abnormal."
get '/works';

get '/works/too' => 'too';

1;
__DATA__
@@ works.html.ep
It is <%= $name %>!

@@ too.html.ep
It <%= config->{it} %>!
