use Mojolicious::Lite;

websocket '/test' => sub {
  my $c = shift;
  $c->on(
    json => sub {
      my ($c, $hash) = @_;
      $hash->{test} = "♥ $hash->{test}";
      $c->send({json => $hash});
    }
  );
};

get '/' => 'websocket';

# Minimal WebSocket application for browser testing
app->start;
__DATA__

@@ websocket.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>WebSocket Test</title>
    <script>
      var ws;
      if ("WebSocket" in window) {
        ws = new WebSocket('<%= url_for('test')->to_abs %>');
      }
      if(typeof(ws) !== 'undefined') {
        ws.onmessage = function (event) {
          document.body.innerHTML += JSON.parse(event.data).test;
        };
        ws.onopen = function (event) {
          ws.send(JSON.stringify({test: 'WebSocket support works! ♥'}));
        };
      }
      else {
        document.body.innerHTML += 'Browser does not support WebSockets.';
      }
    </script>
  </head>
  <body>Testing WebSockets: </body>
</html>
