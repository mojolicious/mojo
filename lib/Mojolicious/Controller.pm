package Mojolicious::Controller;
use Mojo::Base -base;

# No imports, for security reasons!
use Carp        ();
use Digest::SHA ();
use Mojo::ByteStream;
use Mojo::DynamicMethods -dispatch;
use Mojo::URL;
use Mojo::Util;
use Mojolicious::Routes::Match;
use Scalar::Util ();

my $ABSOLUTE = qr!^(?:[^:/?#]+:|//|#)!;

has [qw(app tx)] => undef, weak => 1;
has match => sub { Mojolicious::Routes::Match->new(root => shift->app->routes) };

sub BUILD_DYNAMIC {
  my ($class, $method, $dyn_methods) = @_;

  return sub {
    my $self    = shift;
    my $dynamic = $dyn_methods->{$self->{app}{renderer}}{$method};
    return $self->$dynamic(@_) if $dynamic;
    my $package = ref $self;
    Carp::croak qq{Can't locate object method "$method" via package "$package"};
  };
}

sub continue { $_[0]->app->routes->continue($_[0]) }

sub cookie {
  my ($self, $name) = (shift, shift);

  # Response cookie
  if (@_) {

    # Cookie too big
    my $cookie = {name => $name, value => shift, %{shift // {}}};
    $self->helpers->log->error(qq{Cookie "$name" is bigger than 4KiB}) if length $cookie->{value} > 4096;

    $self->res->cookies($cookie);
    return $self;
  }

  # Request cookies
  return undef unless my $cookie = $self->req->cookie($name);
  return $cookie->value;
}

sub encrypted_cookie {
  my ($self, $name, $value, $options) = @_;

  # Request cookie
  return $self->every_encrypted_cookie($name)->[-1] unless defined $value;

  # Response cookie
  my $app     = $self->app;
  my $secret  = $app->secrets->[0];
  my $moniker = $app->moniker;
  return $self->cookie($name, Mojo::Util::encrypt_cookie($value, $secret, $moniker), $options);
}

sub every_cookie { [map { $_->value } @{shift->req->every_cookie(shift)}] }

sub every_encrypted_cookie {
  my ($self, $name) = @_;

  my $app     = $self->app;
  my $secrets = $app->secrets;
  my $moniker = $app->moniker;
  my @results;
  for my $value (@{$self->every_cookie($name)}) {
    my $decrypted;
    for my $secret (@$secrets) {
      last if defined($decrypted = Mojo::Util::decrypt_cookie($value, $secret, $moniker));
    }
    if (defined $decrypted) { push @results, $decrypted }

    else { $self->helpers->log->trace(qq{Cookie "$name" is not encrypted}) }
  }

  return \@results;
}

sub every_param {
  my ($self, $name) = @_;

  # Captured unreserved values
  my $captures = $self->stash->{'mojo.captures'} //= {};
  if (exists $captures->{$name} && !$self->app->routes->is_reserved($name)) {
    my $value = $captures->{$name};
    return ref $value eq 'ARRAY' ? $value : [$value];
  }

  # Uploads or param values
  my $req     = $self->req;
  my $uploads = $req->every_upload($name);
  return @$uploads ? $uploads : $req->every_param($name);
}

sub every_signed_cookie {
  my ($self, $name) = @_;

  my $secrets = $self->app->secrets;
  my @results;
  for my $value (@{$self->every_cookie($name)}) {

    # Check signature with rotating secrets
    if ($value =~ s/--([^\-]+)$//) {
      my $signature = $1;

      my $valid;
      for my $secret (@$secrets) {
        my $check = Digest::SHA::hmac_sha256_hex("$name=$value", $secret);
        ++$valid and last if Mojo::Util::secure_compare($signature, $check);
      }
      if ($valid) { push @results, $value }

      else { $self->helpers->log->trace(qq{Cookie "$name" has bad signature}) }
    }

    else { $self->helpers->log->trace(qq{Cookie "$name" is not signed}) }
  }

  return \@results;
}

sub finish {
  my $self = shift;

  # WebSocket
  my $tx = $self->tx || Carp::croak 'Transaction already destroyed';
  $tx->finish(@_) and return $tx->established ? $self : $self->rendered(101) if $tx->is_websocket;

  # Chunked stream
  return @_ ? $self->write_chunk(@_)->write_chunk('') : $self->write_chunk('') if $tx->res->content->is_chunked;

  # Normal stream
  return @_ ? $self->write(@_)->write('') : $self->write('');
}

sub helpers { $_[0]->app->renderer->get_helper('')->($_[0]) }

sub on {
  my ($self, $name, $cb) = @_;
  my $tx = $self->tx || Carp::croak 'Transaction already destroyed';
  $self->rendered(101) if $tx->is_websocket && !$tx->established;
  return $tx->on($name => sub { shift; $self->$cb(@_) });
}

sub param {
  my ($self, $name) = (shift, shift);
  return $self->every_param($name)->[-1] unless @_;
  $self->stash->{'mojo.captures'}{$name} = @_ > 1 ? [@_] : $_[0];
  return $self;
}

sub render {
  my $self = shift;

  # Template may be first argument
  my ($template, $args) = (@_ % 2 ? shift : undef, {@_});
  $args->{template} = $template if $template;
  my $app     = $self->app;
  my $plugins = $app->plugins->emit_hook(before_render => $self, $args);

  # Localize "extends" and "layout" to allow argument overrides
  my ($maybe, $ts) = @{$args}{'mojo.maybe', 'mojo.string'};
  my $stash = $self->stash;
  local $stash->{layout}  = $stash->{layout}  if exists $stash->{layout};
  local $stash->{extends} = $stash->{extends} if exists $stash->{extends};

  # Rendering to string
  local @{$stash}{keys %$args}         if $ts || $maybe;
  delete @{$stash}{qw(layout extends)} if $ts;

  # All other arguments just become part of the stash
  @$stash{keys %$args} = values %$args;
  my $renderer = $app->renderer;
  my ($output, $format) = $renderer->render($self);

  # Maybe no 404
  return defined $output ? Mojo::ByteStream->new($output) : undef if $ts;
  return $maybe          ? undef : Carp::croak("Could not render a response") unless defined $output;

  $plugins->emit_hook(after_render => $self, \$output, $format);
  return $renderer->respond($self, $output, $format, $stash->{status});
}

sub render_later { shift->stash('mojo.rendered' => 1) }

sub render_maybe { shift->render(@_, 'mojo.maybe' => 1) }

sub render_to_string { shift->render(@_, 'mojo.string' => 1) }

sub rendered {
  my ($self, $status) = @_;

  # Make sure we have a status
  $self->res->code($status) if $status;

  # Finish transaction
  my $stash = $self->stash;
  if (!$stash->{'mojo.finished'} && ++$stash->{'mojo.finished'}) {
    my $res = $self->res;
    $res->code(200) if !$status && !$res->code;

    # Disable auto rendering and stop timer
    my $app = $self->render_later->app;
    $self->helpers->log->trace(sub {
      my $timing  = $self->helpers->timing;
      my $elapsed = $timing->elapsed('mojo.timer') // 0;
      my $rps     = $timing->rps($elapsed)         // '??';
      my $code    = $res->code;
      my $msg     = $res->message || $res->default_message($code);
      return "$code $msg (${elapsed}s, $rps/s)";
    }) unless $stash->{'mojo.static'};

    $app->plugins->emit_hook_reverse(after_dispatch => $self);
    $app->sessions->store($self);
  }
  $self->tx->resume;
  return $self;
}

sub req { (shift->tx || Carp::croak 'Transaction already destroyed')->req }
sub res { (shift->tx || Carp::croak 'Transaction already destroyed')->res }

sub send {
  my ($self, $msg, $cb) = @_;
  my $tx = $self->tx || Carp::croak 'Transaction already destroyed';
  Carp::croak 'No WebSocket connection to send message to' unless $tx->is_websocket;
  $tx->send($msg, $cb ? sub { shift; $self->$cb(@_) } : ());
  return $tx->established ? $self : $self->rendered(101);
}

sub session {
  my $self = shift;

  my $stash = $self->stash;
  $self->app->sessions->load($self) unless exists $stash->{'mojo.active_session'};

  # Hash
  my $session = $stash->{'mojo.session'} //= {};
  return $session unless @_;

  # Get
  return $session->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  @$session{keys %$values} = values %$values;

  return $self;
}

sub signed_cookie {
  my ($self, $name, $value, $options) = @_;

  # Request cookie
  return $self->every_signed_cookie($name)->[-1] unless defined $value;

  # Response cookie
  my $sum = Digest::SHA::hmac_sha256_hex("$name=$value", $self->app->secrets->[0]);
  return $self->cookie($name, "$value--$sum", $options);
}

sub stash { Mojo::Util::_stash(stash => @_) }

sub url_for {
  my ($self, $target) = (shift, shift // '');

  # Absolute URL
  return $target                 if Scalar::Util::blessed $target && $target->isa('Mojo::URL');
  return Mojo::URL->new($target) if $target =~ $ABSOLUTE;

  # Base
  my $url  = Mojo::URL->new;
  my $req  = $self->req;
  my $base = $url->base($req->url->base->clone)->base->userinfo(undef);

  # Relative URL
  my $path = $url->path;
  if ($target =~ m!^/!) {
    if (defined(my $prefix = $self->stash->{path})) {
      my $real = $req->url->path->to_route;
      $real =~ s!/?\Q$prefix\E$!$target!;
      $target = $real;
    }
    $url->parse($target);
  }

  # Route
  else {
    my $generated = $self->match->path_for($target, @_);
    $path->parse($generated->{path})                         if $generated->{path};
    $base->scheme($base->protocol eq 'https' ? 'wss' : 'ws') if $generated->{websocket};
  }

  # Make path absolute
  my $base_path = $base->path;
  unshift @{$path->parts}, @{$base_path->parts};
  $base_path->parts([])->trailing_slash(0);

  return $url;
}

sub url_for_asset {
  my ($self, $asset) = @_;
  return $self->url_for($asset =~ $ABSOLUTE ? $asset : $self->app->static->asset_path($asset));
}

sub url_for_file {
  my ($self, $file) = @_;
  return $self->url_for($file =~ $ABSOLUTE ? $file : $self->app->static->file_path($file));
}

sub write {
  my ($self, $chunk, $cb) = @_;
  $self->res->content->write($chunk, $cb ? sub { shift; $self->$cb(@_) } : ());
  return $self->rendered;
}

sub write_chunk {
  my ($self, $chunk, $cb) = @_;
  $self->res->content->write_chunk($chunk, $cb ? sub { shift; $self->$cb(@_) } : ());
  return $self->rendered;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Controller - Controller base class

=head1 SYNOPSIS

  # Controller
  package MyApp::Controller::Foo;
  use Mojo::Base 'Mojolicious::Controller', -signatures;

  # Action
  sub bar ($self) {
    my $name = $self->param('name');
    $self->res->headers->cache_control('max-age=1, no-cache');
    $self->render(json => {hello => $name});
  }

=head1 DESCRIPTION

L<Mojolicious::Controller> is the base class for your L<Mojolicious> controllers. It is also the default controller
class unless you set L<Mojolicious/"controller_class">.

=head1 ATTRIBUTES

L<Mojolicious::Controller> implements the following attributes.

=head2 app

  my $app = $c->app;
  $c      = $c->app(Mojolicious->new);

A reference back to the application that dispatched to this controller, usually a L<Mojolicious> object. Note that this
attribute is weakened.

  # Use application logger
  $c->app->log->debug('Hello Mojo');

  # Generate path
  my $path = $c->app->home->child('templates', 'foo', 'bar.html.ep');

=head2 match

  my $m = $c->match;
  $c    = $c->match(Mojolicious::Routes::Match->new);

Router results for the current request, defaults to a L<Mojolicious::Routes::Match> object.

  # Introspect
  my $name   = $c->match->endpoint->name;
  my $foo    = $c->match->endpoint->pattern->defaults->{foo};
  my $action = $c->match->stack->[-1]{action};

=head2 tx

  my $tx = $c->tx;
  $c     = $c->tx(Mojo::Transaction::HTTP->new);

The transaction that is currently being processed, usually a L<Mojo::Transaction::HTTP> or
L<Mojo::Transaction::WebSocket> object. Note that this attribute is weakened. So the object needs to be referenced
elsewhere as well when you're performing non-blocking operations and the underlying connection might get closed early.

  # Check peer information
  my $address = $c->tx->remote_address;
  my $port    = $c->tx->remote_port;

  # Increase size limit for WebSocket messages to 16MiB
  $c->tx->max_websocket_size(16777216) if $c->tx->is_websocket;

  # Perform non-blocking operation without knowing the connection status
  my $tx = $c->tx;
  Mojo::IOLoop->timer(2 => sub {
    $c->app->log->debug($tx->is_finished ? 'Finished' : 'In progress');
  });

=head1 METHODS

L<Mojolicious::Controller> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 continue

  $c->continue;

Continue dispatch chain from an intermediate destination with L<Mojolicious::Routes/"continue">.

=head2 cookie

  my $value = $c->cookie('foo');
  $c        = $c->cookie(foo => 'bar');
  $c        = $c->cookie(foo => 'bar', {path => '/'});

Access request cookie values and create new response cookies. If there are multiple values sharing the same name, and
you want to access more than just the last one, you can use L</"every_cookie">.

  # Create response cookie with domain and expiration date
  $c->cookie(user => 'sri', {domain => 'example.com', expires => time + 60});

  # Create secure response cookie
  $c->cookie(secret => 'I <3 Mojolicious', {secure => 1, httponly => 1});

=head2 encrypted_cookie

  my $value = $c->encrypted_cookie('foo');
  $c        = $c->encrypted_cookie(foo => 'bar');
  $c        = $c->encrypted_cookie(foo => 'bar', {path => '/'});

Access encrypted request cookie values and create new encrypted response cookies. If there are multiple values sharing
the same name, and you want to access more than just the last one, you can use L</"every_encrypted_cookie">. Cookies
are encrypted with ChaCha20-Poly1305, to prevent tampering, and the ones failing decryption will be automatically
discarded.

=head2 every_cookie

  my $values = $c->every_cookie('foo');

Similar to L</"cookie">, but returns all request cookie values sharing the same name as an array reference.

  $ Get first cookie value
  my $first = $c->every_cookie('foo')->[0];

=head2 every_encrypted_cookie

  my $values = $c->every_encrypted_cookie('foo');

Similar to L</"encrypted_cookie">, but returns all encrypted request cookie values sharing the same name as an array
reference.

  # Get first encrypted cookie value
  my $first = $c->every_encrypted_cookie('foo')->[0];

=head2 every_param

  my $values = $c->every_param('foo');

Similar to L</"param">, but returns all values sharing the same name as an array reference.

  # Get first value
  my $first = $c->every_param('foo')->[0];

=head2 every_signed_cookie

  my $values = $c->every_signed_cookie('foo');

Similar to L</"signed_cookie">, but returns all signed request cookie values sharing the same name as an array
reference.

  # Get first signed cookie value
  my $first = $c->every_signed_cookie('foo')->[0];

=head2 finish

  $c = $c->finish;
  $c = $c->finish(1000);
  $c = $c->finish(1003 => 'Cannot accept data!');
  $c = $c->finish('Bye!');

Close WebSocket connection or long poll stream gracefully. This method will automatically respond to WebSocket
handshake requests with a C<101> response status, to establish the WebSocket connection.

=head2 helpers

  my $helpers = $c->helpers;

Return a proxy object containing the current controller object and on which helpers provided by L</"app"> can be
called. This includes all helpers from L<Mojolicious::Plugin::DefaultHelpers> and L<Mojolicious::Plugin::TagHelpers>.

  # Make sure to use the "title" helper and not the controller method
  $c->helpers->title('Welcome!');

  # Use a nested helper instead of the "reply" controller method
  $c->helpers->reply->not_found;

=head2 on

  my $cb = $c->on(finish => sub {...});

Subscribe to events of L</"tx">, which is usually a L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket>
object. This method will automatically respond to WebSocket handshake requests with a C<101> response status, to
establish the WebSocket connection.

  # Do something after the transaction has been finished
  $c->on(finish => sub ($c) {
    $c->app->log->debug('All data has been sent');
  });

  # Receive WebSocket message
  $c->on(message => sub ($c, $msg) {
    $c->app->log->debug("Message: $msg");
  });

  # Receive JSON object via WebSocket message
  $c->on(json => sub ($c, $hash) {
    $c->app->log->debug("Test: $hash->{test}");
  });

  # Receive WebSocket "Binary" message
  $c->on(binary => sub ($c, $bytes) {
    my $len = length $bytes;
    $c->app->log->debug("Received $len bytes");
  });

=head2 param

  my $value = $c->param('foo');
  $c        = $c->param(foo => 'ba;r');
  $c        = $c->param(foo => 'ba;r', 'baz');
  $c        = $c->param(foo => ['ba;r', 'baz']);

Access route placeholder values that are not reserved stash values, file uploads as well as C<GET> and C<POST>
parameters extracted from the query string and C<application/x-www-form-urlencoded> or C<multipart/form-data> message
body, in that order. If there are multiple values sharing the same name, and you want to access more than just the last
one, you can use L</"every_param">. Parts of the request body need to be loaded into memory to parse C<POST>
parameters, so you have to make sure it is not excessively large. There's a 16MiB limit for requests by default.

  # Get first value
  my $first = $c->every_param('foo')->[0];

For more control you can also access request information directly.

  # Only GET parameters
  my $foo = $c->req->query_params->param('foo');

  # Only POST parameters
  my $foo = $c->req->body_params->param('foo');

  # Only GET and POST parameters
  my $foo = $c->req->param('foo');

  # Only file uploads
  my $foo = $c->req->upload('foo');

=head2 render

  my $bool = $c->render;
  my $bool = $c->render(foo => 'bar', baz => 23);
  my $bool = $c->render(template => 'foo/index');
  my $bool = $c->render(template => 'index', format => 'html');
  my $bool = $c->render(data => $bytes);
  my $bool = $c->render(text => 'Hello!');
  my $bool = $c->render(json => {foo => 'bar'});
  my $bool = $c->render(handler => 'something');
  my $bool = $c->render('foo/index');

Render content with L<Mojolicious/"renderer"> and emit hooks L<Mojolicious/"before_render"> as well as
L<Mojolicious/"after_render">, or dies if no response could be generated. All additional key/value pairs get merged into
the L</"stash">.

  # Render characters
  $c->render(text => 'I ♥ Mojolicious!');

  # Render characters (alternative)
  $c->stash(text => 'I ♥ Mojolicious!')->render;

  # Render binary data
  use Mojo::JSON qw(encode_json);
  $c->render(data => encode_json({test => 'I ♥ Mojolicious!'}));

  # Render JSON
  $c->render(json => {test => 'I ♥ Mojolicious!'});

  # Render inline template
  $c->render(inline => '<%= 1 + 1 %>');

  # Render template "foo/bar.html.ep"
  $c->render(template => 'foo/bar', format => 'html', handler => 'ep');

  # Render template "test.*.*" with arbitrary values "foo" and "bar"
  $c->render(template => 'test', foo => 'test', bar => 23);

  # Render template "test.xml.*"
  $c->render(template => 'test', format => 'xml');

  # Render template "test.xml.*" (alternative)
  $c->render('test', format => 'xml');

=head2 render_later

  $c = $c->render_later;

Disable automatic rendering to delay response generation, only necessary if automatic rendering would result in a
response.

  # Delayed rendering
  $c->render_later;
  Mojo::IOLoop->timer(2 => sub { $c->render(text => 'Delayed by 2 seconds!') });

=head2 render_maybe

  my $bool = $c->render_maybe;
  my $bool = $c->render_maybe(foo => 'bar', baz => 23);
  my $bool = $c->render_maybe('foo/index', format => 'html');

Try to render content, but do not call L<Mojolicious::Plugin::DefaultHelpers/"reply-E<gt>not_found"> if no response
could be generated, all arguments get localized automatically and are only available during this render operation,
takes the same arguments as L</"render">.

  # Render template "index_local" only if it exists
  $c->render_maybe('index_local') or $c->render('index');

=head2 render_to_string

  my $output = $c->render_to_string('foo/index', format => 'pdf');

Try to render content and return it wrapped in a L<Mojo::ByteStream> object or return C<undef>, all arguments get
localized automatically and are only available during this render operation, takes the same arguments as L</"render">.

  # Render inline template
  my $two = $c->render_to_string(inline => '<%= 1 + 1 %>');

=head2 rendered

  $c = $c->rendered;
  $c = $c->rendered(302);

Finalize response and emit hook L<Mojolicious/"after_dispatch">, defaults to using a C<200> response code.

  # Custom response
  $c->res->headers->content_type('text/plain');
  $c->res->body('Hello World!');
  $c->rendered(200);

=head2 req

  my $req = $c->req;

Get L<Mojo::Message::Request> object from L</"tx">.

  # Longer version
  my $req = $c->tx->req;

  # Extract request information
  my $id     = $c->req->request_id;
  my $method = $c->req->method;
  my $url    = $c->req->url->to_abs;
  my $info   = $c->req->url->to_abs->userinfo;
  my $host   = $c->req->url->to_abs->host;
  my $agent  = $c->req->headers->user_agent;
  my $custom = $c->req->headers->header('Custom-Header');
  my $bytes  = $c->req->body;
  my $str    = $c->req->text;
  my $hash   = $c->req->params->to_hash;
  my $all    = $c->req->uploads;
  my $value  = $c->req->json;
  my $foo    = $c->req->json('/23/foo');
  my $dom    = $c->req->dom;
  my $bar    = $c->req->dom('div.bar')->first->text;

=head2 res

  my $res = $c->res;

Get L<Mojo::Message::Response> object from L</"tx">.

  # Longer version
  my $res = $c->tx->res;

  # Force file download by setting a response header
  $c->res->headers->content_disposition('attachment; filename=foo.png;');

  # Use a custom response header
  $c->res->headers->header('Custom-Header' => 'whatever');

  # Make sure response is cached correctly
  $c->res->headers->cache_control('public, max-age=300');
  $c->res->headers->append(Vary => 'Accept-Encoding');

=head2 send

  $c = $c->send({binary => $bytes});
  $c = $c->send({text   => $bytes});
  $c = $c->send({json   => {test => [1, 2, 3]}});
  $c = $c->send([$fin, $rsv1, $rsv2, $rsv3, $op, $payload]);
  $c = $c->send($chars);
  $c = $c->send($chars => sub ($c) {...});

Send message or frame non-blocking via WebSocket, the optional drain callback will be executed once all data has been
written. This method will automatically respond to WebSocket handshake requests with a C<101> response status, to
establish the WebSocket connection.

  # Send "Text" message
  $c->send('I ♥ Mojolicious!');

  # Send JSON object as "Text" message
  $c->send({json => {test => 'I ♥ Mojolicious!'}});

  # Send JSON object as "Binary" message
  use Mojo::JSON qw(encode_json);
  $c->send({binary => encode_json({test => 'I ♥ Mojolicious!'})});

  # Send "Ping" frame
  use Mojo::WebSocket qw(WS_PING);
  $c->send([1, 0, 0, 0, WS_PING, 'Hello World!']);

  # Make sure the first message has been written before continuing
  $c->send('First message!' => sub ($c) { $c->send('Second message!') });

For mostly idle WebSockets you might also want to increase the inactivity timeout with
L<Mojolicious::Plugin::DefaultHelpers/"inactivity_timeout">, which usually defaults to C<30> seconds.

  # Increase inactivity timeout for connection to 300 seconds
  $c->inactivity_timeout(300);

=head2 session

  my $session = $c->session;
  my $foo     = $c->session('foo');
  $c          = $c->session({foo => 'bar'});
  $c          = $c->session(foo => 'bar');

Persistent data storage for the next few requests, all session data gets serialized with L<Mojo::JSON> and stored
Base64 encoded in HMAC-SHA256 signed cookies, to prevent tampering. Note that cookies usually have a C<4096> byte
(4KiB) limit, depending on browser.

  # Manipulate session
  $c->session->{foo} = 'bar';
  my $foo = $c->session->{foo};
  delete $c->session->{foo};

  # Expiration date in seconds from now (persists between requests)
  $c->session(expiration => 604800);

  # Expiration date as absolute epoch time (only valid for one request)
  $c->session(expires => time + 604800);

  # Delete whole session by setting an expiration date in the past
  $c->session(expires => 1);

=head2 signed_cookie

  my $value = $c->signed_cookie('foo');
  $c        = $c->signed_cookie(foo => 'bar');
  $c        = $c->signed_cookie(foo => 'bar', {path => '/'});

Access signed request cookie values and create new signed response cookies. If there are multiple values sharing the
same name, and you want to access more than just the last one, you can use L</"every_signed_cookie">. Cookies are
cryptographically signed with HMAC-SHA256, to prevent tampering, and the ones failing signature verification will be
automatically discarded.

=head2 stash

  my $hash = $c->stash;
  my $foo  = $c->stash('foo');
  $c       = $c->stash({foo => 'bar', baz => 23});
  $c       = $c->stash(foo => 'bar', baz => 23);

Non-persistent data storage and exchange for the current request, application wide default values can be set with
L<Mojolicious/"defaults">. Some stash values have a special meaning and are reserved, the full list is currently
C<action>, C<app>, C<cb>, C<controller>, C<data>, C<extends>, C<format>, C<handler>, C<inline>, C<json>, C<layout>,
C<namespace>, C<path>, C<status>, C<template>, C<text> and C<variant>. Note that all stash values with a C<mojo.*>
prefix are reserved for internal use.

  # Remove value
  my $foo = delete $c->stash->{foo};

  # Assign multiple values at once
  $c->stash(foo => 'test', bar => 23);

=head2 url_for

  my $url = $c->url_for;
  my $url = $c->url_for(name => 'sebastian');
  my $url = $c->url_for({name => 'sebastian'});
  my $url = $c->url_for('test', name => 'sebastian');
  my $url = $c->url_for('test', {name => 'sebastian'});
  my $url = $c->url_for('/index.html');
  my $url = $c->url_for('//example.com/index.html');
  my $url = $c->url_for('http://example.com/index.html');
  my $url = $c->url_for('mailto:sri@example.com');
  my $url = $c->url_for('#whatever');

Generate a portable L<Mojo::URL> object with base for a path, URL or route.

  # Rebuild URL for the current route
  $c->url_for;

  # Rebuild URL for the current route, but replace the "name" placeholder value
  $c->url_for(name => 'sebastian');

  # Absolute URL for the current route
  $c->url_for->to_abs;

  # Build URL for route "test" with two placeholder values
  $c->url_for('test', name => 'sebastian', foo => 'bar');

  # "http://127.0.0.1:3000/index.html" if application was started with Morbo
  $c->url_for('/index.html')->to_abs;

  # "https://127.0.0.1:443/index.html" if application was started with Morbo
  $c->url_for('/index.html')->to_abs->scheme('https')->port(443);

  # "/index.html?foo=bar" if application is deployed under "/"
  $c->url_for('/index.html')->query(foo => 'bar');

  # "/myapp/index.html?foo=bar" if application is deployed under "/myapp"
  $c->url_for('/index.html')->query(foo => 'bar');

You can also use the helper L<Mojolicious::Plugin::DefaultHelpers/"url_with"> to inherit query parameters from the
current request.

  # "/list?q=mojo&page=2" if current request was for "/list?q=mojo&page=1"
  $c->url_with->query({page => 2});


=head2 url_for_asset

  my $url = $c->url_for_asset('/app.js');

Generate a portable L<Mojo::URL> object with base for a static asset.

=head2 url_for_file

  my $url = $c->url_for_file('/index.html');

Generate a portable L<Mojo::URL> object with base for a static file.

=head2 write

  $c = $c->write;
  $c = $c->write('');
  $c = $c->write($bytes);
  $c = $c->write($bytes => sub ($c) {...});

Write dynamic content non-blocking, the optional drain callback will be executed once all data has been written.
Calling this method without a chunk of data will finalize the response headers and allow for dynamic content to be
written later.

  # Keep connection alive (with Content-Length header)
  $c->res->headers->content_length(6);
  $c->write('Hel' => sub ($c) { $c->write('lo!') });

  # Close connection when finished (without Content-Length header)
  $c->write('Hel' => sub ($c) {
    $c->write('lo!' => sub ($c) { $c->finish });
  });

You can call L</"finish"> or write an empty chunk of data at any time to end the stream.

  HTTP/1.1 200 OK
  Date: Sat, 13 Sep 2014 16:48:29 GMT
  Content-Length: 6
  Server: Mojolicious (Perl)

  Hello!

  HTTP/1.1 200 OK
  Connection: close
  Date: Sat, 13 Sep 2014 16:48:29 GMT
  Server: Mojolicious (Perl)

  Hello!

For Comet (long polling) you might also want to increase the inactivity timeout with
L<Mojolicious::Plugin::DefaultHelpers/"inactivity_timeout">, which usually defaults to C<30> seconds.

  # Increase inactivity timeout for connection to 300 seconds
  $c->inactivity_timeout(300);

=head2 write_chunk

  $c = $c->write_chunk;
  $c = $c->write_chunk('');
  $c = $c->write_chunk($bytes);
  $c = $c->write_chunk($bytes => sub ($c) {...});

Write dynamic content non-blocking with chunked transfer encoding, the optional drain callback will be executed once
all data has been written. Calling this method without a chunk of data will finalize the response headers and allow for
dynamic content to be written later.

  # Make sure previous chunk has been written before continuing
  $c->write_chunk('H' => sub ($c) {
    $c->write_chunk('ell' => sub ($c) { $c->finish('o!') });
  });

You can call L</"finish"> or write an empty chunk of data at any time to end the stream.

  HTTP/1.1 200 OK
  Date: Sat, 13 Sep 2014 16:48:29 GMT
  Transfer-Encoding: chunked
  Server: Mojolicious (Perl)

  1
  H
  3
  ell
  2
  o!
  0

=head1 HELPERS

In addition to the L</"ATTRIBUTES"> and L</"METHODS"> above you can also call helpers provided by L</"app"> on
L<Mojolicious::Controller> objects. This includes all helpers from L<Mojolicious::Plugin::DefaultHelpers> and
L<Mojolicious::Plugin::TagHelpers>.

  # Call helpers
  $c->layout('green');
  $c->title('Welcome!');

  # Longer version
  $c->helpers->layout('green');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
