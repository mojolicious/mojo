use Mojolicious::Lite;

get '/' => {data => 'Hello World!'};

# Minimal "Hello World" application for profiling
app->start;
