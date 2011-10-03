package Mojo::HelloWorld;
use Mojolicious::Lite;

# "Don't worry, son.
#  I'm sure he's up in heaven right now laughing it up with all the other
#  celebrities: John Dilinger, Ty Cobb, Joseph Stalin."
app->log->level('error');
app->log->path(undef);

# "Does whisky count as beer?"
under '/diag' => sub {
  shift->on_finish(sub { $ENV{MOJO_HELLO} = 'world' });
};

any '/' => 'diag';

any '/chunked_params' => sub {
  my $self = shift;

  # Turn parameters into chunks
  my $params = $self->req->params->to_hash;
  my $chunks = [];
  for my $key (sort keys %$params) {
    push @$chunks, $params->{$key};
  }

  # Write with drain callback
  my $cb;
  $cb = sub {
    my $self = shift;
    my $chunk = shift @$chunks || '';
    $self->write_chunk($chunk, $chunk ? $cb : undef);
  };
  $self->$cb();
};

any '/cookies' => sub {
  my $self = shift;

  # Turn parameters into cookies
  my $params = $self->req->params->to_hash;
  for my $key (sort keys %$params) {
    $self->cookie($key, $params->{$key});
  }
  $self->render_text('nomnomnom');
};

any '/dump_env' => sub { shift->render_json(\%ENV) };

any '/dump_params' => sub {
  my $self = shift;
  $self->render_json($self->req->params->to_hash);
};

# "Dear Homer, IOU one emergency donut.
#  Signed Homer.
#  Bastard!
#  He's always one step ahead."
any '/proxy' => sub {
  my $self = shift;

  # Blocking
  my $res = $self->res;
  if (my $blocking = $self->req->param('blocking')) {
    my $res2 = $self->ua->get($blocking)->res;
    $res->headers->content_type($res2->headers->content_type);
    $self->render_data($res2->content->asset->slurp);
  }

  # Non-blocking
  elsif (my $non_blocking = $self->req->param('non_blocking')) {
    return $self->render_text('This is a blocking deployment environment!')
      unless Mojo::IOLoop->is_running;
    $self->render_later;
    $self->ua->get(
      $non_blocking => sub {
        my $res2 = pop->res;
        $res->headers->content_type($res2->headers->content_type);
        $self->render_data($res2->content->asset->slurp);
      }
    );
  }
};

any '/upload' => sub {
  my $self = shift;

  # Echo uploaded file
  my $req = $self->req;
  return unless my $file = $req->upload('file');
  my $headers = $self->res->headers;
  $headers->content_type($file->headers->content_type
      || 'application/octet-stream');
  $headers->header('X-Upload-Limit-Exceeded' => 1)
    if $req->is_limit_exceeded;
  $self->render_data($file->slurp);
};

any '/websocket' => sub {
  my $self = shift;
  $self->on_message(sub { shift->send_message(shift) })
    if $self->tx->is_websocket;
};

# "How is education supposed to make me feel smarter?
#  Besides, every time I learn something new,
#  it pushes some old stuff out of my brain.
#  Remember when I took that home winemaking course,
#  and I forgot how to drive?"
under->any('/*whatever' => {whatever => '', text => 'Your Mojo is working!'});

1;
__DATA__

@@ layouts/default.html.ep
<!doctype html><html>
  <head>
    <title><%= title %></title>
    <%= content_for 'head' %>
  </head>
  <body>
    <%= content %>
  </body>
</html>

@@ diag.html.ep
% layout 'default';
% title 'Mojo Diagnostics';
<%= link_to Cookies => '/diag/cookies' %><br>
<%= link_to 'Chunked Request Parameters' => '/diag/chunked_params' %><br>
<%= link_to 'Dump Environment Variables' => '/diag/dump_env' %><br>
<%= link_to 'Dump Request Parameters' => '/diag/dump_params' %><br>
<%= link_to Proxy => '/diag/proxy' %><br>
<%= link_to Upload => '/diag/upload' %><br>
<%= link_to WebSocket => '/diag/websocket' %><br>

@@ proxy.html.ep
% layout 'default';
% title 'Proxy';
Blocking:
%= form_for 'proxy' => begin
  %= text_field 'blocking'
  %= submit_button 'Fetch'
% end
<br>
Non-Blocking:
%= form_for 'proxy' => begin
  %= text_field 'non_blocking'
  %= submit_button 'Fetch'
% end

@@ upload.html.ep
% layout 'default';
% title 'Upload';
File:
<%= form_for 'upload', method => 'POST',
      enctype => 'multipart/form-data' => begin %>
  %= file_field 'file'
  %= submit_button 'Upload'
<% end %>

@@ websocket.html.ep
% layout 'default';
% title 'WebSocket';
% content_for head => begin
  % my $url = url_for->to_abs->scheme('ws');
  %= javascript begin
    var ws;
    if ("MozWebSocket" in window) {
      ws = new MozWebSocket("<%= $url %>");
    }
    else if ("WebSocket" in window) {
      ws = new WebSocket("<%= $url %>");
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
% end
Testing WebSockets, please make sure you have JavaScript enabled.

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
