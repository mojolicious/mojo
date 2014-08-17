use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;

get '/hello';

app->start;
__DATA__

@@ hello.html.ep
Hello World!
