use FindBin;
use lib "$FindBin::Bin/../lib";
use Mojolicious::Lite;

any '/' => sub {
  my $self = shift;
  $self->on(message => sub { shift->send(shift) }) if $self->tx->is_websocket;
} => 'websocket';

# Minimal WebSocket application for browser testing
app->start;
__DATA__

@@ websocket.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>WebSocket</title>
    % my $url = url_for->to_abs->scheme('ws');
    %= javascript begin
      var ws;
      if ("WebSocket" in window) {
        ws = new WebSocket('<%= $url %>');
      }
      if(typeof(ws) !== 'undefined') {
        function wsmessage(event) {
          data = event.data;
          alert(data);
        }
        function wsopen(event) {
          ws.send("WebSocket support works!");
        }
        ws.onmessage = wsmessage;
        ws.onopen = wsopen;
      }
      else {
        alert("Sorry, your browser does not support WebSockets.");
      }
    % end
  </head>
  <body>
    Testing WebSockets, please make sure you have JavaScript enabled.
  </body>
</html>
