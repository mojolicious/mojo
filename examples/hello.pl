#
# Minimal "Hello World" application for profiling
#
use Mojolicious::Lite;

get '/' => {data => 'Hello World!'};

app->start;
