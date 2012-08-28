use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;

get '/' => {data => 'Hello World!'};

# Minimal "Hello World" application for profiling
app->start;
