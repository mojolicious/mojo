use Mojolicious::Lite;

get '/hello';

# Minimal "Hello World" application with template for profiling
app->start;
__DATA__

@@ hello.html.ep
Hello World!
