#
# Minimal "Hello World" application with template for profiling
#
use Mojolicious::Lite;

get '/hello';

app->start;
__DATA__

@@ hello.html.ep
Hello <%= 'World!' %>
