package Mojolicious::Controller;
use Mojo::Base -base;

# No imports, for security reasons!
use Carp ();
use Mojo::ByteStream;
use Mojo::Exception;
use Mojo::Transaction::HTTP;
use Mojo::URL;
use Mojo::Util;
use Mojolicious;
use Mojolicious::Routes::Match;
use Scalar::Util ();
use Time::HiRes  ();

has app => sub { Mojolicious->new };
has match =>
  sub { Mojolicious::Routes::Match->new(root => shift->app->routes) };
has tx => sub { Mojo::Transaction::HTTP->new };

# Reserved stash values
my %RESERVED = map { $_ => 1 } (
  qw(action app cb controller data extends format handler json layout),
  qw(namespace partial path status template text)
);

sub AUTOLOAD {
  my $self = shift;

  my ($package, $method) = our $AUTOLOAD =~ /^([\w:]+)::(\w+)$/;
  Carp::croak "Undefined subroutine &${package}::$method called"
    unless Scalar::Util::blessed $self && $self->isa(__PACKAGE__);

  # Call helper with current controller
  Carp::croak qq{Can't locate object method "$method" via package "$package"}
    unless my $helper = $self->app->renderer->helpers->{$method};
  return $self->$helper(@_);
}

sub DESTROY { }

sub cookie {
  my ($self, $name) = (shift, shift);

  # Response cookie
  if (@_) {

    # Cookie too big
    my $cookie = {name => $name, value => shift, %{shift || {}}};
    $self->app->log->error(qq{Cookie "$name" is bigger than 4096 bytes.})
      if length $cookie->{value} > 4096;

    $self->res->cookies($cookie);
    return $self;
  }

  # Request cookies
  return map { $_->value } $self->req->cookie($name) if wantarray;
  return undef unless my $cookie = $self->req->cookie($name);
  return $cookie->value;
}

sub finish {
  my $self = shift;

  # WebSocket
  my $tx = $self->tx;
  $tx->finish(@_) and return $self if $tx->is_websocket;

  # Chunked stream
  if ($tx->res->content->is_chunked) {
    $self->write_chunk(@_) if @_;
    return $self->write_chunk('');
  }

  # Normal stream
  $self->write(@_) if @_;
  return $self->write('');
}

sub flash {
  my $self = shift;

  # Check old flash
  my $session = $self->session;
  return $session->{flash} ? $session->{flash}{$_[0]} : undef
    if @_ == 1 && !ref $_[0];

  # Initialize new flash and merge values
  my $flash = $session->{new_flash} ||= {};
  %$flash = (%$flash, %{@_ > 1 ? {@_} : $_[0]});

  return $self;
}

sub on {
  my ($self, $name, $cb) = @_;
  my $tx = $self->tx;
  $self->rendered(101) if $tx->is_websocket;
  return $tx->on($name => sub { shift and $self->$cb(@_) });
}

sub param {
  my ($self, $name) = (shift, shift);

  # Multiple names
  return map { scalar $self->param($_) } @$name if ref $name eq 'ARRAY';

  # List names
  my $captures = $self->stash->{'mojo.captures'} ||= {};
  my $req = $self->req;
  unless (defined $name) {
    my %seen;
    my @keys = grep { !$seen{$_}++ } $req->param;
    push @keys, grep { !$seen{$_}++ } map { $_->name } @{$req->uploads};
    push @keys, grep { !$RESERVED{$_} && !$seen{$_}++ } keys %$captures;
    return sort @keys;
  }

  # Override values
  if (@_) {
    $captures->{$name} = @_ > 1 ? [@_] : $_[0];
    return $self;
  }

  # Captured unreserved values
  if (!$RESERVED{$name} && defined(my $value = $captures->{$name})) {
    return ref $value eq 'ARRAY' ? wantarray ? @$value : $$value[0] : $value;
  }

  # Uploads
  return $req->upload($name) if $req->upload($name);

  # Param values
  return $req->param($name);
}

sub redirect_to {
  my $self = shift;

  # Don't override 3xx status
  my $res = $self->res;
  $res->headers->location($self->url_for(@_)->to_abs);
  return $self->rendered($res->is_status_class(300) ? () : 302);
}

sub render {
  my $self = shift;

  # Template may be first argument
  my ($template, $args) = (@_ % 2 ? shift : undef, {@_});
  $args->{template} = $template if $template;
  my $maybe = delete $args->{'mojo.maybe'};

  # Render
  my $app = $self->app;
  my ($output, $format) = $app->renderer->render($self, $args);
  return defined $output ? Mojo::ByteStream->new($output) : undef
    if $args->{partial};

  # Maybe
  return $maybe ? undef : !$self->render_not_found unless defined $output;

  # Prepare response
  $app->plugins->emit_hook(after_render => $self, \$output, $format);
  my $headers = $self->res->body($output)->headers;
  $headers->content_type($app->types->type($format) || 'text/plain')
    unless $headers->content_type;
  return !!$self->rendered($self->stash->{status});
}

sub render_exception {
  my ($self, $e) = @_;

  my $app = $self->app;
  $app->log->error($e = Mojo::Exception->new($e));

  # Filtered stash snapshot
  my $stash = $self->stash;
  my %snapshot = map { $_ => $stash->{$_} }
    grep { !/^mojo\./ and defined $stash->{$_} } keys %$stash;

  # Render with fallbacks
  my $mode     = $app->mode;
  my $renderer = $app->renderer;
  my $options  = {
    exception => $e,
    snapshot  => \%snapshot,
    template  => "exception.$mode",
    format    => $stash->{format} || $renderer->default_format,
    handler   => undef,
    status    => 500
  };
  my $inline = $renderer->_bundled(
    $mode eq 'development' ? 'exception.development' : 'exception');
  return $self if $self->_fallbacks($options, 'exception', $inline);
  $self->_fallbacks({%$options, format => 'html'}, 'exception', $inline);
  return $self;
}

sub render_later { shift->stash('mojo.rendered' => 1) }

sub render_maybe { shift->render(@_, 'mojo.maybe' => 1) }

sub render_not_found {
  my $self = shift;

  # Render with fallbacks
  my $app      = $self->app;
  my $mode     = $app->mode;
  my $renderer = $app->renderer;
  my $format   = $self->stash->{format} || $renderer->default_format;
  my $options
    = {template => "not_found.$mode", format => $format, status => 404};
  my $inline = $renderer->_bundled(
    $mode eq 'development' ? 'not_found.development' : 'not_found');
  return $self if $self->_fallbacks($options, 'not_found', $inline);
  $self->_fallbacks({%$options, format => 'html'}, 'not_found', $inline);
  return $self;
}

sub render_static {
  my ($self, $file) = @_;
  my $app = $self->app;
  return !!$self->rendered if $app->static->serve($self, $file);
  $app->log->debug(qq{File "$file" not found, public directory missing?});
  return !$self->render_not_found;
}

sub rendered {
  my ($self, $status) = @_;

  # Disable auto rendering and make sure we have a status
  my $res = $self->render_later->res;
  $res->code($status || 200) if $status || !$res->code;

  # Finish transaction
  my $stash = $self->stash;
  unless ($stash->{'mojo.finished'}++) {

    # Stop timer
    my $app = $self->app;
    if (my $started = delete $stash->{'mojo.started'}) {
      my $elapsed = sprintf '%f',
        Time::HiRes::tv_interval($started, [Time::HiRes::gettimeofday()]);
      my $rps  = $elapsed == 0 ? '??' : sprintf '%.3f', 1 / $elapsed;
      my $code = $res->code;
      my $msg  = $res->message || $res->default_message($code);
      $app->log->debug("$code $msg (${elapsed}s, $rps/s).");
    }

    $app->plugins->emit_hook_reverse(after_dispatch => $self);
    $app->sessions->store($self);
  }
  $self->tx->resume;
  return $self;
}

sub req { shift->tx->req }
sub res { shift->tx->res }

sub respond_to {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # Detect formats
  my $app     = $self->app;
  my $req     = $self->req;
  my @formats = @{$app->types->detect($req->headers->accept, $req->is_xhr)};
  my $stash   = $self->stash;
  unless (@formats) {
    my $format = $stash->{format} || $req->param('format');
    push @formats, $format ? $format : $app->renderer->default_format;
  }

  # Find target
  my $target;
  for my $format (@formats) {
    next unless $target = $args->{$format};
    $stash->{format} = $format;
    last;
  }

  # Fallback
  unless ($target) {
    return $self->rendered(204) unless $target = $args->{any};
    delete $stash->{format};
  }

  # Dispatch
  ref $target eq 'CODE' ? $target->($self) : $self->render(%$target);

  return $self;
}

sub send {
  my ($self, $msg, $cb) = @_;
  my $tx = $self->tx;
  Carp::croak 'No WebSocket connection to send message to'
    unless $tx->is_websocket;
  $tx->send($msg => sub { shift and $self->$cb(@_) if $cb });
  return $self->rendered(101);
}

sub session {
  my $self = shift;

  # Hash
  my $session = $self->stash->{'mojo.session'} ||= {};
  return $session unless @_;

  # Get
  return $session->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  %$session = (%$session, %{ref $_[0] ? $_[0] : {@_}});

  return $self;
}

sub signed_cookie {
  my ($self, $name, $value, $options) = @_;

  # Response cookie
  my $secret = $self->stash->{'mojo.secret'};
  return $self->cookie($name,
    "$value--" . Mojo::Util::hmac_sha1_sum($value, $secret), $options)
    if defined $value;

  # Request cookies
  my @results;
  for my $value ($self->cookie($name)) {

    # Check signature
    if ($value =~ s/--([^\-]+)$//) {
      my $sig = $1;

      # Verified
      my $check = Mojo::Util::hmac_sha1_sum $value, $secret;
      if (Mojo::Util::secure_compare $sig, $check) { push @results, $value }

      # Bad cookie
      else {
        $self->app->log->debug(
          qq{Bad signed cookie "$name", possible hacking attempt.});
      }
    }

    # Not signed
    else { $self->app->log->debug(qq{Cookie "$name" not signed.}) }
  }

  return wantarray ? @results : $results[0];
}

sub stash {
  my $self = shift;

  # Hash
  my $stash = $self->{stash} ||= {};
  return $stash unless @_;

  # Get
  return $stash->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  for my $key (keys %$values) {
    $self->app->log->debug(qq{Careful, "$key" is a reserved stash value.})
      if $RESERVED{$key};
    $stash->{$key} = $values->{$key};
  }

  return $self;
}

sub ua { shift->app->ua }

sub url_for {
  my $self = shift;
  my $target = shift // '';

  # Absolute URL
  return $target if Scalar::Util::blessed $target && $target->isa('Mojo::URL');
  return Mojo::URL->new($target) if $target =~ m!^\w+://!;

  # Base
  my $url  = Mojo::URL->new;
  my $req  = $self->req;
  my $base = $url->base($req->url->base->clone)->base->userinfo(undef);

  # Relative URL
  my $path = $url->path;
  if ($target =~ m!^/!) {
    if (my $prefix = $self->stash->{path}) {
      my $real = $req->url->path->to_route;
      $real =~ s!/?$prefix$!$target!;
      $target = $real;
    }
    $url->parse($target);
  }

  # Route
  else {
    my ($generated, $ws) = $self->match->path_for($target, @_);
    $path->parse($generated) if $generated;

    # Fix trailing slash
    $path->trailing_slash(1)
      if (!$target || $target eq 'current') && $req->url->path->trailing_slash;

    # Fix scheme for WebSockets
    $base->scheme($base->protocol eq 'https' ? 'wss' : 'ws') if $ws;
  }

  # Make path absolute
  my $base_path = $base->path;
  unshift @{$path->parts}, @{$base_path->parts};
  $base_path->parts([])->trailing_slash(0);

  return $url;
}

sub write {
  my ($self, $chunk, $cb) = @_;
  ($cb, $chunk) = ($chunk, undef) if ref $chunk eq 'CODE';
  my $content = $self->res->content;
  $content->write($chunk => sub { shift and $self->$cb(@_) if $cb });
  return $self->rendered;
}

sub write_chunk {
  my ($self, $chunk, $cb) = @_;
  ($cb, $chunk) = ($chunk, undef) if ref $chunk eq 'CODE';
  my $content = $self->res->content;
  $content->write_chunk($chunk => sub { shift and $self->$cb(@_) if $cb });
  return $self->rendered;
}

sub _fallbacks {
  my ($self, $options, $template, $inline) = @_;

  # Mode specific template
  return 1 if $self->render_maybe(%$options);

  # Normal template
  return 1 if $self->render_maybe(%$options, template => $template);

  # Inline template
  my $stash = $self->stash;
  return undef unless $stash->{format} eq 'html';
  delete $stash->{$_} for qw(extends layout);
  return $self->render_maybe(%$options, inline => $inline, handler => 'ep');
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Controller - Controller base class

=head1 SYNOPSIS

  # Controller
  package MyApp::Foo;
  use Mojo::Base 'Mojolicious::Controller';

  # Action
  sub bar {
    my $self = shift;
    my $name = $self->param('name');
    $self->res->headers->cache_control('max-age=1, no-cache');
    $self->render(json => {hello => $name});
  }

=head1 DESCRIPTION

L<Mojolicious::Controller> is the base class for your L<Mojolicious>
controllers. It is also the default controller class for L<Mojolicious>
unless you set C<controller_class> in your application.

=head1 ATTRIBUTES

L<Mojolicious::Controller> inherits all attributes from L<Mojo::Base> and
implements the following new ones.

=head2 app

  my $app = $c->app;
  $c      = $c->app(Mojolicious->new);

A reference back to the application that dispatched to this controller,
defaults to a L<Mojolicious> object.

  # Use application logger
  $c->app->log->debug('Hello Mojo!');

=head2 match

  my $m = $c->match;
  $c    = $c->match(Mojolicious::Routes::Match->new);

Router results for the current request, defaults to a
L<Mojolicious::Routes::Match> object.

  # Introspect
  my $foo = $c->match->endpoint->pattern->defaults->{foo};

=head2 tx

  my $tx = $c->tx;
  $c     = $c->tx(Mojo::Transaction::HTTP->new);

The transaction that is currently being processed, usually a
L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket> object.

  # Check peer information
  my $address = $c->tx->remote_address;

=head1 METHODS

L<Mojolicious::Controller> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 cookie

  my $value  = $c->cookie('foo');
  my @values = $c->cookie('foo');
  $c         = $c->cookie(foo => 'bar');
  $c         = $c->cookie(foo => 'bar', {path => '/'});

Access request cookie values and create new response cookies.

  # Create response cookie with domain and expiration date
  $c->cookie(user => 'sri', {domain => 'example.com', expires => time + 60});

=head2 finish

  $c = $c->finish;
  $c = $c->finish(1000);
  $c = $c->finish(1003 => 'Cannot accept data!');
  $c = $c->finish('Bye!');

Close WebSocket connection or long poll stream gracefully.

=head2 flash

  my $foo = $c->flash('foo');
  $c      = $c->flash({foo => 'bar'});
  $c      = $c->flash(foo => 'bar');

Data storage persistent only for the next request, stored in the C<session>.

  # Show message after redirect
  $c->flash(message => 'User created successfully!');
  $c->redirect_to('show_user', id => 23);

=head2 on

  my $cb = $c->on(finish => sub {...});

Subscribe to events of C<tx>, which is usually a L<Mojo::Transaction::HTTP> or
L<Mojo::Transaction::WebSocket> object.

  # Do something after the transaction has been finished
  $c->on(finish => sub {
    my $c = shift;
    $c->app->log->debug('We are done!');
  });

  # Receive WebSocket message
  $c->on(message => sub {
    my ($c, $msg) = @_;
    $c->app->log->debug("Message: $msg");
  });

  # Receive JSON object via WebSocket message
  $c->on(json => sub {
    my ($c, $hash) = @_;
    $c->app->log->debug("Test: $hash->{test}");
  });

  # Receive WebSocket "Binary" message
  $c->on(binary => sub {
    my ($c, $bytes) = @_;
    my $len = length $bytes;
    $c->app->log->debug("Received $len bytes.");
  });

=head2 param

  my @names       = $c->param;
  my $foo         = $c->param('foo');
  my @foo         = $c->param('foo');
  my ($foo, $bar) = $c->param(['foo', 'bar']);
  $c              = $c->param(foo => 'ba;r');
  $c              = $c->param(foo => qw(ba;r ba;z));

Access GET/POST parameters, file uploads and route placeholder values that are
not reserved stash values. Note that this method is context sensitive in some
cases and therefore needs to be used with care, there can always be multiple
values, which might have unexpected consequences.

  # List context is ambiguous and should be avoided
  my $hash = {foo => $self->param('foo')};

  # Better enforce scalar context
  my $hash = {foo => scalar $self->param('foo')};

  # The multi name form can also enforce scalar context
  my $hash = {foo => $self->param(['foo'])};

For more control you can also access request information directly.

  # Only GET parameters
  my $foo = $c->req->url->query->param('foo');

  # Only GET and POST parameters
  my $foo = $c->req->param('foo');

  # Only file uploads
  my $foo = $c->req->upload('foo');

=head2 redirect_to

  $c = $c->redirect_to('named');
  $c = $c->redirect_to('named', foo => 'bar');
  $c = $c->redirect_to('/path');
  $c = $c->redirect_to('http://127.0.0.1/foo/bar');

Prepare a C<302> redirect response, takes the same arguments as C<url_for>.

  # Conditional redirect
  return $c->redirect_to('login') unless $c->session('user');

  # Moved permanently
  $c->res->code(301);
  $c->redirect_to('some_route');

=head2 render

  my $success = $c->render;
  my $success = $c->render(controller => 'foo', action => 'bar');
  my $success = $c->render(template => 'foo/index');
  my $success = $c->render(template => 'index', format => 'html');
  my $success = $c->render(data => $bytes);
  my $success = $c->render(text => 'Hello!');
  my $success = $c->render(json => {foo => 'bar'});
  my $success = $c->render(handler => 'something');
  my $success = $c->render('foo/index');
  my $output  = $c->render('foo/index', partial => 1);

Render content using L<Mojolicious::Renderer/"render"> and emit
C<after_render> hook unless the result is C<partial>. If no template is
provided a default one based on controller and action or route name will be
generated, all additional values get merged into the C<stash>.

=head2 render_exception

  $c = $c->render_exception('Oops!');
  $c = $c->render_exception(Mojo::Exception->new('Oops!'));

Render the exception template C<exception.$mode.$format.*> or
C<exception.$format.*> and set the response status code to C<500>. Also sets
the stash values C<exception> to a L<Mojo::Exception> object and C<snapshot>
to a copy of the C<stash> for use in the templates.

=head2 render_later

  $c = $c->render_later;

Disable automatic rendering to delay response generation, only necessary if
automatic rendering would result in a response.

  # Delayed rendering
  $c->render_later;
  Mojo::IOLoop->timer(2 => sub {
    $c->render(text => 'Delayed by 2 seconds!');
  });

=head2 render_maybe

  my $success = $c->render_maybe;
  my $success = $c->render_maybe(controller => 'foo', action => 'bar');
  my $success = $c->render_maybe('foo/index', format => 'html');

Try to render content but do not call C<render_not_found> if no response could
be generated, takes the same arguments as C<render>.

  # Render template "index_local" only if it exists
  $self->render_maybe('index_local') or $self->render('index');

=head2 render_not_found

  $c = $c->render_not_found;

Render the not found template C<not_found.$mode.$format.*> or
C<not_found.$format.*> and set the response status code to C<404>.

=head2 render_static

  my $success = $c->render_static('images/logo.png');
  my $success = $c->render_static('../lib/MyApp.pm');

Render a static file using L<Mojolicious::Static/"serve">, usually from the
C<public> directories or C<DATA> sections of your application. Note that this
method does not protect from traversing to parent directories.

=head2 rendered

  $c = $c->rendered;
  $c = $c->rendered(302);

Finalize response and emit C<after_dispatch> hook, defaults to using a C<200>
response code.

=head2 req

  my $req = $c->req;

Get L<Mojo::Message::Request> object from L<Mojo::Transaction/"req">.

  # Longer version
  my $req = $c->tx->req;

  # Extract request information
  my $url      = $c->req->url->to_abs;
  my $userinfo = $c->req->url->to_abs->userinfo;
  my $host     = $c->req->url->to_abs->host;
  my $agent    = $c->req->headers->user_agent;
  my $body     = $c->req->body;
  my $foo      = $c->req->json('/23/foo');
  my $bar      = $c->req->dom('div.bar')->first->text;

=head2 res

  my $res = $c->res;

Get L<Mojo::Message::Response> object from L<Mojo::Transaction/"res">.

  # Longer version
  my $res = $c->tx->res;

  # Force file download by setting a custom response header
  $c->res->headers->content_disposition('attachment; filename=foo.png;');

=head2 respond_to

  $c = $c->respond_to(
    json => {json => {message => 'Welcome!'}},
    html => {template => 'welcome'},
    any  => sub {...}
  );

Automatically select best possible representation for resource from C<Accept>
request header, C<format> stash value or C<format> GET/POST parameter,
defaults to rendering an empty C<204> response. Since browsers often don't
really know what they actually want, unspecific C<Accept> request headers with
more than one MIME type will be ignored, unless the C<X-Requested-With> header
is set to the value C<XMLHttpRequest>.

  $c->respond_to(
    json => sub { $c->render(json => {just => 'works'}) },
    xml  => {text => '<just>works</just>'},
    any  => {data => '', status => 204}
  );

=head2 send

  $c = $c->send({binary => $bytes});
  $c = $c->send({text   => $bytes});
  $c = $c->send({json   => {test => [1, 2, 3]}});
  $c = $c->send([$fin, $rsv1, $rsv2, $rsv3, $op, $bytes]);
  $c = $c->send(Mojo::ByteStream->new($chars));
  $c = $c->send($chars);
  $c = $c->send($chars => sub {...});

Send message or frame non-blocking via WebSocket, the optional drain callback
will be invoked once all data has been written.

  # Send "Text" message
  $c->send('I ♥ Mojolicious!');

  # Send JSON object as "Text" message
  $c->send({json => {test => 'I ♥ Mojolicious!'}});

  # Send JSON object as "Binary" message
  use Mojo::JSON 'j';
  $c->send({binary => j({test => 'I ♥ Mojolicious!'})});

  # Send "Ping" frame
  $c->send([1, 0, 0, 0, 9, 'Hello World!']);

For mostly idle WebSockets you might also want to increase the inactivity
timeout, which usually defaults to C<15> seconds.

  # Increase inactivity timeout for connection to 300 seconds
  Mojo::IOLoop->stream($c->tx->connection)->timeout(300);

=head2 session

  my $session = $c->session;
  my $foo     = $c->session('foo');
  $c          = $c->session({foo => 'bar'});
  $c          = $c->session(foo => 'bar');

Persistent data storage, all session data gets serialized with L<Mojo::JSON>
and stored C<Base64> encoded in C<HMAC-SHA1> signed cookies. Note that cookies
usually have a 4096 byte limit, depending on browser.

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

  my $value  = $c->signed_cookie('foo');
  my @values = $c->signed_cookie('foo');
  $c         = $c->signed_cookie(foo => 'bar');
  $c         = $c->signed_cookie(foo => 'bar', {path => '/'});

Access signed request cookie values and create new signed response cookies.
Cookies failing C<HMAC-SHA1> signature verification will be automatically
discarded.

=head2 stash

  my $hash = $c->stash;
  my $foo  = $c->stash('foo');
  $c       = $c->stash({foo => 'bar'});
  $c       = $c->stash(foo => 'bar');

Non persistent data storage and exchange, application wide default values can
be set with L<Mojolicious/"defaults">. Many stash values have a special
meaning and are reserved, the full list is currently C<action>, C<app>, C<cb>,
C<controller>, C<data>, C<extends>, C<format>, C<handler>, C<json>, C<layout>,
C<namespace>, C<partial>, C<path>, C<status>, C<template> and C<text>. Note
that all stash values with a C<mojo.*> prefix are reserved for internal use.

  # Remove value
  my $foo = delete $c->stash->{foo};

=head2 ua

  my $ua = $c->ua;

Get L<Mojo::UserAgent> object from L<Mojo/"ua">.

  # Longer version
  my $ua = $c->app->ua;

  # Blocking
  my $tx = $c->ua->get('http://example.com');
  my $tx = $c->ua->post('example.com/login' => form => {user => 'mojo'});

  # Non-blocking
  $c->ua->get('http://example.com' => sub {
    my ($ua, $tx) = @_;
    $c->render(data => $tx->res->body);
  });

  # Parallel non-blocking
  my $delay = Mojo::IOLoop->delay(sub {
    my ($delay, @titles) = @_;
    $c->render(json => \@titles);
  });
  for my $url ('http://mojolicio.us', 'https://metacpan.org') {
    my $end = $delay->begin(0);
    $c->ua->get($url => sub {
      my ($ua, $tx) = @_;
      $end->($tx->res->dom->html->head->title->text);
    });
  }

=head2 url_for

  my $url = $c->url_for;
  my $url = $c->url_for(name => 'sebastian');
  my $url = $c->url_for({name => 'sebastian'});
  my $url = $c->url_for('test', name => 'sebastian');
  my $url = $c->url_for('test', {name => 'sebastian'});
  my $url = $c->url_for('/perldoc');
  my $url = $c->url_for('http://mojolicio.us/perldoc');

Generate a portable L<Mojo::URL> object with base for a route, path or URL.

  # "/perldoc?foo=bar" if application is deployed under "/"
  $c->url_for('/perldoc')->query(foo => 'bar');

  # "/myapp/perldoc?foo=bar" if application is deployed under "/myapp"
  $c->url_for('/perldoc')->query(foo => 'bar');

You can also use the helper L<Mojolicious::Plugin::DefaultHelpers/"url_with">
to inherit query parameters from the current request.

  # "/list?q=mojo&page=2" if current request was for "/list?q=mojo&page=1"
  $c->url_with->query([page => 2]);

=head2 write

  $c = $c->write;
  $c = $c->write($bytes);
  $c = $c->write(sub {...});
  $c = $c->write($bytes => sub {...});

Write dynamic content non-blocking, the optional drain callback will be
invoked once all data has been written.

  # Keep connection alive (with Content-Length header)
  $c->res->headers->content_length(6);
  $c->write('Hel' => sub {
    my $c = shift;
    $c->write('lo!')
  });

  # Close connection when finished (without Content-Length header)
  $c->write('Hel' => sub {
    my $c = shift;
    $c->write('lo!' => sub {
      my $c = shift;
      $c->finish;
    });
  });

For Comet (long polling) you might also want to increase the inactivity
timeout, which usually defaults to C<15> seconds.

  # Increase inactivity timeout for connection to 300 seconds
  Mojo::IOLoop->stream($c->tx->connection)->timeout(300);

=head2 write_chunk

  $c = $c->write_chunk;
  $c = $c->write_chunk($bytes);
  $c = $c->write_chunk(sub {...});
  $c = $c->write_chunk($bytes => sub {...});

Write dynamic content non-blocking with C<chunked> transfer encoding, the
optional drain callback will be invoked once all data has been written.

  # Make sure previous chunk has been written before continuing
  $c->write_chunk('He' => sub {
    my $c = shift;
    $c->write_chunk('ll' => sub {
      my $c = shift;
      $c->finish('o!');
    });
  });

You can call C<finish> at any time to end the stream.

  2
  He
  2
  ll
  2
  o!
  0

=head1 HELPERS

In addition to the attributes and methods above you can also call helpers on
L<Mojolicious::Controller> objects. This includes all helpers from
L<Mojolicious::Plugin::DefaultHelpers> and L<Mojolicious::Plugin::TagHelpers>.

  $c->layout('green');
  $c->title('Welcome!');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
