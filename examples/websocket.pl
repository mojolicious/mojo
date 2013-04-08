use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;
use Mojo::JSON 'j';

websocket '/test' => sub {
  my $self = shift;
  $self->on(
    text => sub {
      my ($self, $data) = @_;
      my $hash = j($data);
      $hash->{test} = "♥ $hash->{test}";
      $self->send({text => j($hash)});
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
    %= javascript begin
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
    % end
  </head>
  <body>Testing WebSockets: </body>
</html>
