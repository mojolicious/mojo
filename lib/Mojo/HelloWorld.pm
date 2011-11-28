package Mojo::HelloWorld;
use Mojolicious::Lite;

# "Don't worry, son.
#  I'm sure he's up in heaven right now laughing it up with all the other
#  celebrities: John Dilinger, Ty Cobb, Joseph Stalin."
app->log->level('error');
app->log->path(undef);

any '/websocket' => sub {
  my $self = shift;
  $self->on(message => sub { shift->send_message(shift) })
    if $self->tx->is_websocket;
};

# "Does whisky count as beer?"
under->any('/*whatever' => {whatever => '', text => 'Your Mojo is working!'});

1;
__DATA__

@@ websocket.html.ep
<!DOCTYPE html>
<html>
  <head>
    <title>WebSocket</title>
    % my $url = url_for->to_abs->scheme('ws');
    %= javascript begin
      var ws;
      if ("MozWebSocket" in window) {
        ws = new MozWebSocket('<%= $url %>');
      }
      else if ("WebSocket" in window) {
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

__END__

=head1 NAME

Mojo::HelloWorld - Hello World!

=head1 SYNOPSIS

  use Mojo::HelloWorld;

=head1 DESCRIPTION

L<Mojo::HelloWorld> is the default L<Mojolicious> application, used mostly
for testing.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
