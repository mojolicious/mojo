use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;

# "Amy, technology isn't intrinsically good or evil. It's how it's used.
#  Like the Death Ray."
get '/' => {data => 'Hello World!'};

# Minimal "Hello World" application for profiling
app->start;
