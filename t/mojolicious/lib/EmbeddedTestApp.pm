package EmbeddedTestApp;
use Mojolicious::Lite;

# "But you're better than normal, you're abnormal."
get '/works' => 'works';

1;
__DATA__
@@ works.html.ep
It is <%= $name %>!
