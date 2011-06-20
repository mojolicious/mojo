package Mojo::HelloWorld;
use Mojo::Base 'Mojo';

use Mojo::IOLoop;
use Mojo::JSON;
use Mojo::Cookie::Response;

# "How is education supposed to make me feel smarter? Besides,
#  every time I learn something new,
#  it pushes some old stuff out of my brain.
#  Remember when I took that home winemaking course,
#  and I forgot how to drive?"
sub new {
  my $self = shift->SUPER::new(@_);

  # This app should log only errors to STDERR
  $self->log->level('error');
  $self->log->path(undef);

  $self;
}

sub handler {
  my ($self, $tx) = @_;

  # Dispatch to diagnostics functions
  return $self->_diag($tx) if defined $tx->req->url->path->parts->[0];

  # Hello world!
  my $res = $tx->res;
  $res->code(200);
  $res->headers->content_type('text/plain');
  $res->body('Your Mojo is working!');
  $tx->resume;
}

sub _cookies {
  my ($self, $tx) = @_;

  # Cookies
  my $res    = $tx->res;
  my $params = $tx->req->params->to_hash;
  for my $key (sort keys %$params) {
    $res->cookies(
      Mojo::Cookie::Response->new(
        name  => $key,
        value => $params->{$key}
      )
    );
  }

  # Response
  $res->code(200);
  $res->body('nomnomnom');
  $tx->resume;
}

sub _chunked_params {
  my ($self, $tx) = @_;

  # Chunked
  $tx->res->headers->transfer_encoding('chunked');

  # Chunks
  my $params = $tx->req->params->to_hash;
  my $chunks = [];
  for my $key (sort keys %$params) {
    push @$chunks, $params->{$key};
  }

  # Callback
  my $cb;
  $cb = sub {
    my $self = shift;
    my $chunk = shift @$chunks || '';
    $self->write_chunk($chunk, $chunk ? $cb : undef);
  };
  $cb->($tx->res);
  $tx->resume;
}

sub _diag {
  my ($self, $tx) = @_;

  # Finished transaction
  $tx->on_finish(sub { $ENV{MOJO_HELLO} = 'world' });

  # Path
  my $path = $tx->req->url->path->to_abs_string;
  $path = '/diag/websocket' if $path eq '/chat';
  $path =~ s/^\/diag// or return $self->_hello($tx);

  # WebSocket
  return $self->_websocket($tx) if $path =~ /^\/websocket/;

  # Defaults
  $tx->res->code(200);
  $tx->res->headers->content_type('text/plain')
    unless $tx->res->headers->content_type;

  # Dispatch
  return $self->_cookies($tx)        if $path =~ /^\/cookies/;
  return $self->_chunked_params($tx) if $path =~ /^\/chunked_params/;
  return $self->_dump_env($tx)       if $path =~ /^\/dump_env/;
  return $self->_dump_params($tx)    if $path =~ /^\/dump_params/;
  return $self->_upload($tx)         if $path =~ /^\/upload/;
  return $self->_proxy($tx)          if $path =~ /^\/proxy/;

  # List
  $tx->res->headers->content_type('text/html');
  $tx->res->body(<<'EOF');
<!doctype html><html>
  <head><title>Mojo Diagnostics</title></head>
  <body>
    <a href="/diag/cookies">Cookies</a>
    <a href="/diag/chunked_params">Chunked Request Parameters</a><br>
    <a href="/diag/dump_env">Dump Environment Variables</a><br>
    <a href="/diag/dump_params">Dump Request Parameters</a><br>
    <a href="/diag/proxy">Proxy</a><br>
    <a href="/diag/upload">Upload</a><br>
    <a href="/diag/websocket">WebSocket</a>
  </body>
</html>
EOF
  $tx->resume;
}

sub _dump_env {
  my ($self, $tx) = @_;
  my $res = $tx->res;
  $res->headers->content_type('application/json');
  $res->body(Mojo::JSON->new->encode(\%ENV));
  $tx->resume;
}

sub _dump_params {
  my ($self, $tx) = @_;
  my $res = $tx->res;
  $res->headers->content_type('application/json');
  $res->body(Mojo::JSON->new->encode($tx->req->params->to_hash));
  $tx->resume;
}

sub _hello {
  my ($self, $tx) = @_;

  # Hello world!
  my $res = $tx->res;
  $res->code(200);
  $res->headers->content_type('text/plain');
  $res->body('Your Mojo is working!');
  $tx->resume;
}

sub _proxy {
  my ($self, $tx) = @_;

  # Proxy
  if (my $url = $tx->req->param('url')) {

    # Fetch
    my $tx2 = $self->ua->get($url);

    # Pass through content
    $tx->res->headers->content_type($tx2->res->headers->content_type);
    $tx->res->body($tx2->res->content->asset->slurp);
    $tx->resume;

    return;
  }

  # Async proxy
  if (my $url = $tx->req->param('async_url')) {

    # Sync environment
    unless (Mojo::IOLoop->singleton->is_running) {
      $tx->res->body('Async not available in this deployment environment!');
      $tx->resume;
      return;
    }

    # Fetch
    $self->ua->get(
      $url => sub {
        my ($self, $tx2) = @_;

        # Pass through content
        $tx->res->headers->content_type($tx2->res->headers->content_type);
        $tx->res->body($tx2->res->content->asset->slurp);
        $tx->resume;
      }
    );

    return;
  }

  # Form
  my $url = $tx->req->url->to_abs;
  $url->path('/diag/proxy');
  $tx->res->headers->content_type('text/html');
  $tx->res->body(<<"EOF");
<!doctype html><html>
  <head><title>Mojo Diagnostics</title></head>
  <body>
    Sync:
    <form action="$url" method="GET">
      <input type="text" name="url" value="http://">
      <input type="submit" value="Fetch">
    </form>
    <br>
    Async:
    <form action="$url" method="GET">
      <input type="text" name="async_url" value="http://">
      <input type="submit" value="Fetch">
    </form>
  </body>
</html>
EOF
  $tx->resume;
}

sub _upload {
  my ($self, $tx) = @_;

  # File
  my $res = $tx->res;
  my $req = $tx->req;
  if (my $file = $req->upload('file')) {
    my $headers = $res->headers;
    $headers->content_type($file->headers->content_type
        || 'application/octet-stream');
    $headers->header('X-Upload-Limit-Exceeded' => 1)
      if $req->is_limit_exceeded;
    $res->body($file->slurp);
  }

  # Form
  else {
    my $url = $req->url->to_abs;
    $url->path('/diag/upload');
    $res->headers->content_type('text/html');
    $res->body(<<"EOF");
<!doctype html><html>
  <head><title>Mojo Diagnostics</title></head>
  <body>
    File:
    <form action="$url" method="POST" enctype="multipart/form-data">
      <input type="file" name="file">
      <input type="submit" value="Upload">
    </form>
  </body>
</html>
EOF
  }

  # Response
  $res->code(200);
  $tx->resume;
}

sub _websocket {
  my ($self, $tx) = @_;

  # WebSocket request
  if ($tx->is_websocket) {
    $tx->on_message(
      sub {
        my ($tx, $message) = @_;
        $tx->send_message($message);
        $tx->resume;
      }
    );
    return $tx->resume;
  }

  # WebSocket example
  my $url = $tx->req->url->to_abs;
  $url->scheme('ws');
  $url->path('/diag/websocket');
  $tx->res->headers->content_type('text/html');
  $tx->res->body(<<"EOF");
<!doctype html><html>
  <head>
    <title>Mojo Diagnostics</title>
    <script language="javascript">
      var ws;
      if ("MozWebSocket" in window) {
        ws = new MozWebSocket("$url");
      }
      else if ("WebSocket" in window) {
        ws = new WebSocket("$url");
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
    </script>
  </head>
  <body>
    Testing WebSockets, please make sure you have JavaScript enabled.
  </body>
</html>
EOF
  $tx->resume;
}

1;
__END__

=head1 NAME

Mojo::HelloWorld - Hello World!

=head1 SYNOPSIS

  use Mojo::Transaction::HTTP;
  use Mojo::HelloWorld;

  my $hello = Mojo::HelloWorld->new;
  my $tx = $hello->handler(Mojo::Transaction::HTTP->new);

=head1 DESCRIPTION

L<Mojo::HelloWorld> is the default L<Mojo> application, used mostly for
testing.

=head1 METHODS

L<Mojo::HelloWorld> inherits all methods from L<Mojo> and implements the
following new ones.

=head2 C<new>

  my $hello = Mojo::HelloWorld->new;

Construct a new L<Mojo::HelloWorld> application.

=head2 C<handler>

  $tx = $hello->handler($tx);

Handle request.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
