package Test::Mojo;
use Mojo::Base -base;

# "Amy: He knows when you are sleeping.
#  Professor: He knows when you're on the can.
#  Leela: He'll hunt you down and blast your ass from here to Pakistan.
#  Zoidberg: Oh.
#  Hermes: You'd better not breathe, you'd better not move.
#  Bender: You're better off dead, I'm telling you, dude.
#  Fry: Santa Claus is gunning you down!"
use Mojo::IOLoop;
use Mojo::JSON qw(j);
use Mojo::JSON::Pointer;
use Mojo::Server;
use Mojo::UserAgent;
use Mojo::Util qw(decode encode);
use Test::More ();

has handler => sub { \&_handler };
has [qw(message success tx)];
has ua => sub { Mojo::UserAgent->new(insecure => 1)->ioloop(Mojo::IOLoop->singleton) };

# Silent or loud tests
$ENV{MOJO_LOG_LEVEL} ||= $ENV{HARNESS_IS_VERBOSE} ? 'debug' : 'fatal';

sub app {
  my ($self, $app) = @_;
  return $self->ua->server->app unless $app;
  $self->ua->server->app($app);
  return $self;
}

sub attr_is {
  my ($self, $selector, $attr, $value, $desc) = @_;
  $desc = _desc($desc, qq{exact match for attribute "$attr" at selector "$selector"});
  return $self->test('is', $self->_attr($selector, $attr), $value, $desc);
}

sub attr_isnt {
  my ($self, $selector, $attr, $value, $desc) = @_;
  $desc = _desc($desc, qq{no match for attribute "$attr" at selector "$selector"});
  return $self->test('isnt', $self->_attr($selector, $attr), $value, $desc);
}

sub attr_like {
  my ($self, $selector, $attr, $regex, $desc) = @_;
  $desc = _desc($desc, qq{similar match for attribute "$attr" at selector "$selector"});
  return $self->test('like', $self->_attr($selector, $attr), $regex, $desc);
}

sub attr_unlike {
  my ($self, $selector, $attr, $regex, $desc) = @_;
  $desc = _desc($desc, qq{no similar match for attribute "$attr" at selector "$selector"});
  return $self->test('unlike', $self->_attr($selector, $attr), $regex, $desc);
}

sub content_is {
  my ($self, $value, $desc) = @_;
  return $self->test('is', $self->tx->res->text, $value, _desc($desc, 'exact match for content'));
}

sub content_isnt {
  my ($self, $value, $desc) = @_;
  return $self->test('isnt', $self->tx->res->text, $value, _desc($desc, 'no match for content'));
}

sub content_like {
  my ($self, $regex, $desc) = @_;
  return $self->test('like', $self->tx->res->text, $regex, _desc($desc, 'content is similar'));
}

sub content_type_is {
  my ($self, $type, $desc) = @_;
  return $self->test('is', $self->tx->res->headers->content_type, $type, _desc($desc, "Content-Type: $type"));
}

sub content_type_isnt {
  my ($self, $type, $desc) = @_;
  return $self->test('isnt', $self->tx->res->headers->content_type, $type, _desc($desc, "not Content-Type: $type"));
}

sub content_type_like {
  my ($self, $regex, $desc) = @_;
  return $self->test('like', $self->tx->res->headers->content_type, $regex, _desc($desc, 'Content-Type is similar'));
}

sub content_type_unlike {
  my ($self, $regex, $desc) = @_;
  $desc = _desc($desc, 'Content-Type is not similar');
  return $self->test('unlike', $self->tx->res->headers->content_type, $regex, $desc);
}

sub content_unlike {
  my ($self, $regex, $desc) = @_;
  return $self->test('unlike', $self->tx->res->text, $regex, _desc($desc, 'content is not similar'));
}

sub delete_ok { shift->_build_ok(DELETE => @_) }

sub element_count_is {
  my ($self, $selector, $count, $desc) = @_;
  my $size = $self->tx->res->dom->find($selector)->size;
  return $self->test('is', $size, $count, _desc($desc, qq{element count for selector "$selector"}));
}

sub element_exists {
  my ($self, $selector, $desc) = @_;
  $desc = _desc($desc, qq{element for selector "$selector" exists});
  return $self->test('ok', $self->tx->res->dom->at($selector), $desc);
}

sub element_exists_not {
  my ($self, $selector, $desc) = @_;
  return $self->test('ok', !$self->tx->res->dom->at($selector), _desc($desc, qq{no element for selector "$selector"}));
}

sub finish_ok {
  my $self = shift;
  $self->tx->finish(@_) if $self->tx->is_websocket;
  Mojo::IOLoop->one_tick while !$self->{finished};
  return $self->test('ok', 1, 'closed WebSocket');
}

sub finished_ok {
  my ($self, $code) = @_;
  Mojo::IOLoop->one_tick while !$self->{finished};
  Test::More::diag "WebSocket closed with status $self->{finished}[0]" unless my $ok = $self->{finished}[0] == $code;
  return $self->test('ok', $ok, "WebSocket closed with status $code");
}

sub get_ok  { shift->_build_ok(GET  => @_) }
sub head_ok { shift->_build_ok(HEAD => @_) }

sub header_exists {
  my ($self, $name, $desc) = @_;
  return $self->test('ok', !!@{$self->tx->res->headers->every_header($name)}, _desc($desc, qq{header "$name" exists}));
}

sub header_exists_not {
  my ($self, $name, $desc) = @_;
  return $self->test('ok', !@{$self->tx->res->headers->every_header($name)}, _desc($desc, qq{no "$name" header}));
}

sub header_is {
  my ($self, $name, $value, $desc) = @_;
  return $self->test('is', $self->tx->res->headers->header($name), $value, _desc($desc, "$name: " . ($value // '')));
}

sub header_isnt {
  my ($self, $name, $value, $desc) = @_;
  $desc = _desc($desc, "not $name: " . ($value // ''));
  return $self->test('isnt', $self->tx->res->headers->header($name), $value, $desc);
}

sub header_like {
  my ($self, $name, $regex, $desc) = @_;
  $desc = _desc($desc, "$name is similar");
  return $self->test('like', $self->tx->res->headers->header($name), $regex, $desc);
}

sub header_unlike {
  my ($self, $name, $regex, $desc) = @_;
  return $self->test('unlike', $self->tx->res->headers->header($name), $regex, _desc($desc, "$name is not similar"));
}

sub json_has {
  my ($self, $p, $desc) = @_;
  $desc = _desc($desc, qq{has value for JSON Pointer "$p"});
  return $self->test('ok', !!Mojo::JSON::Pointer->new($self->tx->res->json)->contains($p), $desc);
}

sub json_hasnt {
  my ($self, $p, $desc) = @_;
  $desc = _desc($desc, qq{has no value for JSON Pointer "$p"});
  return $self->test('ok', !Mojo::JSON::Pointer->new($self->tx->res->json)->contains($p), $desc);
}

sub json_is {
  my $self = shift;
  my ($p, $data) = @_ > 1 ? (shift, shift) : ('', shift);
  my $desc = _desc(shift, qq{exact match for JSON Pointer "$p"});
  return $self->test('is_deeply', $self->tx->res->json($p), $data, $desc);
}

sub json_like {
  my ($self, $p, $regex, $desc) = @_;
  return $self->test('like', $self->tx->res->json($p), $regex, _desc($desc, qq{similar match for JSON Pointer "$p"}));
}

sub json_message_has {
  my ($self, $p, $desc) = @_;
  return $self->test('ok', $self->_json(contains => $p), _desc($desc, qq{has value for JSON Pointer "$p"}));
}

sub json_message_hasnt {
  my ($self, $p, $desc) = @_;
  return $self->test('ok', !$self->_json(contains => $p), _desc($desc, qq{has no value for JSON Pointer "$p"}));
}

sub json_message_is {
  my $self = shift;
  my ($p, $data) = @_ > 1 ? (shift, shift) : ('', shift);
  return $self->test('is_deeply', $self->_json(get => $p), $data, _desc(shift, qq{exact match for JSON Pointer "$p"}));
}

sub json_message_like {
  my ($self, $p, $regex, $desc) = @_;
  return $self->test('like', $self->_json(get => $p), $regex, _desc($desc, qq{similar match for JSON Pointer "$p"}));
}

sub json_message_unlike {
  my ($self, $p, $regex, $desc) = @_;
  $desc = _desc($desc, qq{no similar match for JSON Pointer "$p"});
  return $self->test('unlike', $self->_json(get => $p), $regex, $desc);
}

sub json_unlike {
  my ($self, $p, $regex, $desc) = @_;
  $desc = _desc($desc, qq{no similar match for JSON Pointer "$p"});
  return $self->test('unlike', $self->tx->res->json($p), $regex, $desc);
}

sub message_is {
  my ($self, $value, $desc) = @_;
  return $self->_message('is', $value, _desc($desc, 'exact match for message'));
}

sub message_isnt {
  my ($self, $value, $desc) = @_;
  return $self->_message('isnt', $value, _desc($desc, 'no match for message'));
}

sub message_like {
  my ($self, $regex, $desc) = @_;
  return $self->_message('like', $regex, _desc($desc, 'message is similar'));
}

sub message_ok {
  my ($self, $desc) = @_;
  return $self->test('ok', !!$self->_wait, _desc($desc, 'message received'));
}

sub message_unlike {
  my ($self, $regex, $desc) = @_;
  return $self->_message('unlike', $regex, _desc($desc, 'message is not similar'));
}

sub new {
  my $self = shift->SUPER::new;

  return $self unless my $app = shift;

  my @args = @_ ? {config => {config_override => 1, %{shift()}}} : ();
  return $self->app(Mojo::Server->new->build_app($app, @args)) unless ref $app;
  $app = Mojo::Server->new->load_app($app)                     unless $app->isa('Mojolicious');
  return $self->app(@args ? $app->config($args[0]{config}) : $app);
}

sub options_ok { shift->_build_ok(OPTIONS => @_) }

sub or {
  my ($self, $cb) = @_;
  $self->$cb unless $self->success;
  return $self;
}

sub patch_ok { shift->_build_ok(PATCH => @_) }
sub post_ok  { shift->_build_ok(POST  => @_) }
sub put_ok   { shift->_build_ok(PUT   => @_) }

sub request_ok { shift->_request_ok($_[0], $_[0]->req->url->to_string) }

sub reset_session {
  my $self = shift;
  $self->ua->cookie_jar->empty;
  return $self->tx(undef);
}

sub send_ok {
  my ($self, $msg, $desc) = @_;

  $desc = _desc($desc, 'send message');
  return $self->test('ok', 0, $desc) unless $self->tx->is_websocket;

  $self->tx->send($msg => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;
  return $self->test('ok', 1, $desc);
}

sub status_is {
  my ($self, $status, $desc) = @_;
  $desc = _desc($desc, "$status " . $self->tx->res->default_message($status));
  return $self->test('is', $self->tx->res->code, $status, $desc);
}

sub status_isnt {
  my ($self, $status, $desc) = @_;
  $desc = _desc($desc, "not $status " . $self->tx->res->default_message($status));
  return $self->test('isnt', $self->tx->res->code, $status, $desc);
}

sub test {
  my ($self, $name, @args) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 3;
  return $self->success(!!$self->handler->($name, @args));
}

sub text_is {
  my ($self, $selector, $value, $desc) = @_;
  return $self->test('is', $self->_text($selector), $value, _desc($desc, qq{exact match for selector "$selector"}));
}

sub text_isnt {
  my ($self, $selector, $value, $desc) = @_;
  return $self->test('isnt', $self->_text($selector), $value, _desc($desc, qq{no match for selector "$selector"}));
}

sub text_like {
  my ($self, $selector, $regex, $desc) = @_;
  return $self->test('like', $self->_text($selector), $regex, _desc($desc, qq{similar match for selector "$selector"}));
}

sub text_unlike {
  my ($self, $selector, $regex, $desc) = @_;
  $desc = _desc($desc, qq{no similar match for selector "$selector"});
  return $self->test('unlike', $self->_text($selector), $regex, $desc);
}

sub websocket_ok {
  my $self = shift;
  return $self->_request_ok($self->ua->build_websocket_tx(@_), $_[0]);
}

sub _attr {
  my ($self, $selector, $attr) = @_;
  return '' unless my $e = $self->tx->res->dom->at($selector);
  return $e->attr($attr) // '';
}

sub _build_ok {
  my ($self, $method, $url) = (shift, shift, shift);
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  return $self->_request_ok($self->ua->build_tx($method, $url, @_), $url);
}

sub _desc { encode 'UTF-8', shift || shift }

sub _handler {
  my ($name, @args) = @_;
  return Test::More->can($name)->(@args);
}

sub _json {
  my ($self, $method, $p) = @_;
  return Mojo::JSON::Pointer->new(j(@{$self->message // []}[1]))->$method($p);
}

sub _message {
  my ($self, $name, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my ($type, $msg) = @{$self->message // []};

  # Type check
  if (ref $value eq 'HASH') {
    my $expect = exists $value->{text} ? 'text' : 'binary';
    $value = $value->{$expect};
    $msg   = '' unless ($type // '') eq $expect;
  }

  # Decode text frame if there is no type check
  else { $msg = decode 'UTF-8', $msg if ($type // '') eq 'text' }

  return $self->test($name, $msg // '', $value, $desc);
}

sub _request_ok {
  my ($self, $tx, $url) = @_;

  local $Test::Builder::Level = $Test::Builder::Level + 1;

  # Establish WebSocket connection
  if ($tx->req->is_handshake) {
    @$self{qw(finished messages)} = (undef, []);
    $self->ua->start(
      $tx => sub {
        my ($ua, $tx) = @_;
        $self->{finished} = [] unless $self->tx($tx)->tx->is_websocket;
        $tx->on(finish => sub { shift; $self->{finished} = [@_] });
        $tx->on(binary => sub { push @{$self->{messages}}, [binary => pop] });
        $tx->on(text   => sub { push @{$self->{messages}}, [text   => pop] });
        Mojo::IOLoop->stop;
      }
    );
    Mojo::IOLoop->start;

    return $self->test('ok', $self->tx->is_websocket, _desc("WebSocket handshake with $url"));
  }

  # Perform request
  $self->tx($self->ua->start($tx));
  my $err = $self->tx->error;
  Test::More::diag $err->{message} if !(my $ok = !$err->{message} || $err->{code}) && $err;
  return $self->test('ok', $ok, _desc("@{[uc $tx->req->method]} $url"));
}

sub _text {
  return '' unless my $e = shift->tx->res->dom->at(shift);
  return $e->text;
}

sub _wait {
  my $self = shift;
  Mojo::IOLoop->one_tick while !$self->{finished} && !@{$self->{messages}};
  return $self->message(shift @{$self->{messages}})->message;
}

1;

=encoding utf8

=head1 NAME

Test::Mojo - Testing Mojo

=head1 SYNOPSIS

  use Test::More;
  use Test::Mojo;

  my $t = Test::Mojo->new('MyApp');

  # HTML/XML
  $t->get_ok('/welcome')->status_is(200)->text_is('div#message' => 'Hello!');

  # JSON
  $t->post_ok('/search.json' => form => {q => 'Perl'})
    ->status_is(200)
    ->header_is('Server' => 'Mojolicious (Perl)')
    ->header_isnt('X-Bender' => 'Bite my shiny metal ass!')
    ->json_is('/results/4/title' => 'Perl rocks!')
    ->json_like('/results/7/title' => qr/Perl/);

  # WebSocket
  $t->websocket_ok('/echo')
    ->send_ok('hello')
    ->message_ok
    ->message_is('echo: hello')
    ->finish_ok;

  done_testing();

=head1 DESCRIPTION

L<Test::Mojo> is a test user agent based on L<Mojo::UserAgent>, it is usually used together with L<Test::More> to test
L<Mojolicious> applications. Just run your tests with L<prove>.

  $ prove -l -v
  $ prove -l -v t/foo.t

If it is not already defined, the C<MOJO_LOG_LEVEL> environment variable will be set to C<debug> or C<fatal>, depending
on the value of the C<HARNESS_IS_VERBOSE> environment variable. And to make it esier to test HTTPS/WSS web services
L<Mojo::UserAgent/"insecure"> will be activated by default for L</"ua">.

See L<Mojolicious::Guides::Testing> for more.

=head1 ATTRIBUTES

L<Test::Mojo> implements the following attributes.

=head2 handler

  my $cb = $t->handler;
  $t     = $t->handler(sub {...});

A callback to connect L<Test::Mojo> with L<Test::More>.

  $t->handler(sub ($name, @args) {
    return Test::More->can($name)->(@args);
  });

=head2 message

  my $msg = $t->message;
  $t      = $t->message([text => $bytes]);

Current WebSocket message represented as an array reference containing the frame type and payload.

  # More specific tests
  use Mojo::JSON qw(decode_json);
  my $hash = decode_json $t->message->[1];
  is ref $hash, 'HASH', 'right reference';
  is $hash->{foo}, 'bar', 'right value';

  # Test custom message
  $t->message([binary => $bytes])
    ->json_message_has('/foo/bar')
    ->json_message_hasnt('/bar')
    ->json_message_is('/foo/baz' => {yada => [1, 2, 3]});

=head2 success

  my $bool = $t->success;
  $t       = $t->success($bool);

True if the last test was successful.

  # Build custom tests
  my $location_is = sub ($t, $value, $desc = '') {
    $desc ||= "Location: $value";
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    return $t->success(is($t->tx->res->headers->location, $value, $desc));
  };
  $t->get_ok('/')
    ->status_is(302)
    ->$location_is('https://mojolicious.org')
    ->or(sub { diag 'Must have been Joel!' });

=head2 tx

  my $tx = $t->tx;
  $t     = $t->tx(Mojo::Transaction::HTTP->new);

Current transaction, usually a L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket> object.

  # More specific tests
  is $t->tx->res->json->{foo}, 'bar', 'right value';
  ok $t->tx->res->content->is_multipart, 'multipart content';
  is $t->tx->previous->res->code, 302, 'right status';

=head2 ua

  my $ua = $t->ua;
  $t     = $t->ua(Mojo::UserAgent->new);

User agent used for testing, defaults to a L<Mojo::UserAgent> object.

  # Allow redirects
  $t->ua->max_redirects(10);
  $t->get_ok('/redirect')->status_is(200)->content_like(qr/redirected/);

  # Switch protocol from HTTP to HTTPS
  $t->ua->server->url('https');
  $t->get_ok('/secure')->status_is(200)->content_like(qr/secure/);

  # Use absolute URL for request with Basic authentication
  my $url = $t->ua->server->url->userinfo('sri:secr3t')->path('/secrets.json');
  $t->post_ok($url => json => {limit => 10})
    ->status_is(200)
    ->json_is('/1/content', 'Mojo rocks!');

  # Customize all transactions (including followed redirects)
  $t->ua->on(start => sub ($ua, $tx) { $tx->req->headers->accept_language('en-US') });
  $t->get_ok('/hello')->status_is(200)->content_like(qr/Howdy/);

=head1 METHODS

L<Test::Mojo> inherits all methods from L<Mojo::Base> and implements the following new ones.

=head2 app

  my $app = $t->app;
  $t      = $t->app(Mojolicious->new);

Access application with L<Mojo::UserAgent::Server/"app">.

  # Change log level
  $t->app->log->level('fatal');

  # Test application directly
  is $t->app->defaults->{foo}, 'bar', 'right value';
  ok $t->app->routes->find('echo')->is_websocket, 'WebSocket route';
  my $c = $t->app->build_controller;
  ok $c->render(template => 'foo'), 'rendering was successful';
  is $c->res->status, 200, 'right status';
  is $c->res->body, 'Foo!', 'right content';

  # Change application behavior
  $t->app->hook(before_dispatch => sub ($c) {
    $c->render(text => 'This request did not reach the router.') if $c->req->url->path->contains('/user');
  });
  $t->get_ok('/user')->status_is(200)->content_like(qr/not reach the router/);

  # Extract additional information
  my $stash;
  $t->app->hook(after_dispatch => sub ($c) { $stash = $c->stash });
  $t->get_ok('/hello')->status_is(200);
  is $stash->{foo}, 'bar', 'right value';

=head2 attr_is

  $t = $t->attr_is('img.cat', 'alt', 'Grumpy cat');
  $t = $t->attr_is('img.cat', 'alt', 'Grumpy cat', 'right alt text');

Checks text content of attribute with L<Mojo::DOM/"attr"> at the CSS selectors first matching HTML/XML element for
exact match with L<Mojo::DOM/"at">.

=head2 attr_isnt

  $t = $t->attr_isnt('img.cat', 'alt', 'Calm cat');
  $t = $t->attr_isnt('img.cat', 'alt', 'Calm cat', 'different alt text');

Opposite of L</"attr_is">.

=head2 attr_like

  $t = $t->attr_like('img.cat', 'alt', qr/Grumpy/);
  $t = $t->attr_like('img.cat', 'alt', qr/Grumpy/, 'right alt text');

Checks text content of attribute with L<Mojo::DOM/"attr"> at the CSS selectors first matching HTML/XML element for
similar match with L<Mojo::DOM/"at">.

=head2 attr_unlike

  $t = $t->attr_unlike('img.cat', 'alt', qr/Calm/);
  $t = $t->attr_unlike('img.cat', 'alt', qr/Calm/, 'different alt text');

Opposite of L</"attr_like">.

=head2 content_is

  $t = $t->content_is('working!');
  $t = $t->content_is('working!', 'right content');

Check response content for exact match after retrieving it from L<Mojo::Message/"text">.

=head2 content_isnt

  $t = $t->content_isnt('working!');
  $t = $t->content_isnt('working!', 'different content');

Opposite of L</"content_is">.

=head2 content_like

  $t = $t->content_like(qr/working!/);
  $t = $t->content_like(qr/working!/, 'right content');

Check response content for similar match after retrieving it from L<Mojo::Message/"text">.

=head2 content_type_is

  $t = $t->content_type_is('text/html');
  $t = $t->content_type_is('text/html', 'right content type');

Check response C<Content-Type> header for exact match.

=head2 content_type_isnt

  $t = $t->content_type_isnt('text/html');
  $t = $t->content_type_isnt('text/html', 'different content type');

Opposite of L</"content_type_is">.

=head2 content_type_like

  $t = $t->content_type_like(qr/text/);
  $t = $t->content_type_like(qr/text/, 'right content type');

Check response C<Content-Type> header for similar match.

=head2 content_type_unlike

  $t = $t->content_type_unlike(qr/text/);
  $t = $t->content_type_unlike(qr/text/, 'different content type');

Opposite of L</"content_type_like">.

=head2 content_unlike

  $t = $t->content_unlike(qr/working!/);
  $t = $t->content_unlike(qr/working!/, 'different content');

Opposite of L</"content_like">.

=head2 delete_ok

  $t = $t->delete_ok('http://example.com/foo');
  $t = $t->delete_ok('/foo');
  $t = $t->delete_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->delete_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->delete_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<DELETE> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"delete">,
except for the callback.

=head2 element_count_is

  $t = $t->element_count_is('div.foo[x=y]', 5);
  $t = $t->element_count_is('html body div', 30, 'thirty elements');

Checks the number of HTML/XML elements matched by the CSS selector with L<Mojo::DOM/"find">.

=head2 element_exists

  $t = $t->element_exists('div.foo[x=y]');
  $t = $t->element_exists('html head title', 'has a title');

Checks for existence of the CSS selectors first matching HTML/XML element with L<Mojo::DOM/"at">.

  # Check attribute values
  $t->get_ok('/login')
    ->element_exists('label[for=email]')
    ->element_exists('input[name=email][type=text][value*="example.com"]')
    ->element_exists('label[for=pass]')
    ->element_exists('input[name=pass][type=password]')
    ->element_exists('input[type=submit][value]');

=head2 element_exists_not

  $t = $t->element_exists_not('div.foo[x=y]');
  $t = $t->element_exists_not('html head title', 'has no title');

Opposite of L</"element_exists">.

=head2 finish_ok

  $t = $t->finish_ok;
  $t = $t->finish_ok(1000);
  $t = $t->finish_ok(1003 => 'Cannot accept data!');

Close WebSocket connection gracefully.

=head2 finished_ok

  $t = $t->finished_ok(1000);

Wait for WebSocket connection to be closed gracefully and check status.

=head2 get_ok

  $t = $t->get_ok('http://example.com/foo');
  $t = $t->get_ok('/foo');
  $t = $t->get_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->get_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->get_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<GET> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"get">, except
for the callback.

  # Run tests against remote host
  $t->get_ok('https://docs.mojolicious.org')->status_is(200);

  # Use relative URL for request with Basic authentication
  $t->get_ok('//sri:secr3t@/secrets.json')
    ->status_is(200)
    ->json_is('/1/content', 'Mojo rocks!');

  # Run additional tests on the transaction
  $t->get_ok('/foo')->status_is(200);
  is $t->tx->res->dom->at('input')->val, 'whatever', 'right value';

=head2 head_ok

  $t = $t->head_ok('http://example.com/foo');
  $t = $t->head_ok('/foo');
  $t = $t->head_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->head_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->head_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<HEAD> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"head">, except
for the callback.

=head2 header_exists

  $t = $t->header_exists('ETag');
  $t = $t->header_exists('ETag', 'header exists');

Check if response header exists.

=head2 header_exists_not

  $t = $t->header_exists_not('ETag');
  $t = $t->header_exists_not('ETag', 'header is missing');

Opposite of L</"header_exists">.

=head2 header_is

  $t = $t->header_is(ETag => '"abc321"');
  $t = $t->header_is(ETag => '"abc321"', 'right header');

Check response header for exact match.

=head2 header_isnt

  $t = $t->header_isnt(Etag => '"abc321"');
  $t = $t->header_isnt(ETag => '"abc321"', 'different header');

Opposite of L</"header_is">.

=head2 header_like

  $t = $t->header_like(ETag => qr/abc/);
  $t = $t->header_like(ETag => qr/abc/, 'right header');

Check response header for similar match.

=head2 header_unlike

  $t = $t->header_unlike(ETag => qr/abc/);
  $t = $t->header_unlike(ETag => qr/abc/, 'different header');

Opposite of L</"header_like">.

=head2 json_has

  $t = $t->json_has('/foo');
  $t = $t->json_has('/minibar', 'has a minibar');

Check if JSON response contains a value that can be identified using the given JSON Pointer with
L<Mojo::JSON::Pointer>.

=head2 json_hasnt

  $t = $t->json_hasnt('/foo');
  $t = $t->json_hasnt('/minibar', 'no minibar');

Opposite of L</"json_has">.

=head2 json_is

  $t = $t->json_is({foo => [1, 2, 3]});
  $t = $t->json_is('/foo' => [1, 2, 3]);
  $t = $t->json_is('/foo/1' => 2, 'right value');

Check the value extracted from JSON response using the given JSON Pointer with L<Mojo::JSON::Pointer>, which defaults
to the root value if it is omitted.

  # Use an empty JSON Pointer to test the whole JSON response with a test description
  $t->json_is('' => {foo => [1, 2, 3]}, 'right object');

=head2 json_like

  $t = $t->json_like('/foo/1' => qr/^\d+$/);
  $t = $t->json_like('/foo/1' => qr/^\d+$/, 'right value');

Check the value extracted from JSON response using the given JSON Pointer with L<Mojo::JSON::Pointer> for similar
match.

=head2 json_message_has

  $t = $t->json_message_has('/foo');
  $t = $t->json_message_has('/minibar', 'has a minibar');

Check if JSON WebSocket message contains a value that can be identified using the given JSON Pointer with
L<Mojo::JSON::Pointer>.

=head2 json_message_hasnt

  $t = $t->json_message_hasnt('/foo');
  $t = $t->json_message_hasnt('/minibar', 'no minibar');

Opposite of L</"json_message_has">.

=head2 json_message_is

  $t = $t->json_message_is({foo => [1, 2, 3]});
  $t = $t->json_message_is('/foo' => [1, 2, 3]);
  $t = $t->json_message_is('/foo/1' => 2, 'right value');

Check the value extracted from JSON WebSocket message using the given JSON Pointer with L<Mojo::JSON::Pointer>, which
defaults to the root value if it is omitted.

=head2 json_message_like

  $t = $t->json_message_like('/foo/1' => qr/^\d+$/);
  $t = $t->json_message_like('/foo/1' => qr/^\d+$/, 'right value');

Check the value extracted from JSON WebSocket message using the given JSON Pointer with L<Mojo::JSON::Pointer> for
similar match.

=head2 json_message_unlike

  $t = $t->json_message_unlike('/foo/1' => qr/^\d+$/);
  $t = $t->json_message_unlike('/foo/1' => qr/^\d+$/, 'different value');

Opposite of L</"json_message_like">.

=head2 json_unlike

  $t = $t->json_unlike('/foo/1' => qr/^\d+$/);
  $t = $t->json_unlike('/foo/1' => qr/^\d+$/, 'different value');

Opposite of L</"json_like">.

=head2 message_is

  $t = $t->message_is({binary => $bytes});
  $t = $t->message_is({text   => $bytes});
  $t = $t->message_is('working!');
  $t = $t->message_is('working!', 'right message');

Check WebSocket message for exact match.

=head2 message_isnt

  $t = $t->message_isnt({binary => $bytes});
  $t = $t->message_isnt({text   => $bytes});
  $t = $t->message_isnt('working!');
  $t = $t->message_isnt('working!', 'different message');

Opposite of L</"message_is">.

=head2 message_like

  $t = $t->message_like({binary => qr/$bytes/});
  $t = $t->message_like({text   => qr/$bytes/});
  $t = $t->message_like(qr/working!/);
  $t = $t->message_like(qr/working!/, 'right message');

Check WebSocket message for similar match.

=head2 message_ok

  $t = $t->message_ok;
  $t = $t->message_ok('got a message');

Wait for next WebSocket message to arrive.

  # Wait for message and perform multiple tests on it
  $t->websocket_ok('/time')
    ->message_ok
    ->message_like(qr/\d+/)
    ->message_unlike(qr/\w+/)
    ->finish_ok;

=head2 message_unlike

  $t = $t->message_unlike({binary => qr/$bytes/});
  $t = $t->message_unlike({text   => qr/$bytes/});
  $t = $t->message_unlike(qr/working!/);
  $t = $t->message_unlike(qr/working!/, 'different message');

Opposite of L</"message_like">.

=head2 new

  my $t = Test::Mojo->new;
  my $t = Test::Mojo->new('MyApp');
  my $t = Test::Mojo->new('MyApp', {foo => 'bar'});
  my $t = Test::Mojo->new(Mojo::File->new('/path/to/myapp.pl'));
  my $t = Test::Mojo->new(Mojo::File->new('/path/to/myapp.pl'), {foo => 'bar'});
  my $t = Test::Mojo->new(MyApp->new);
  my $t = Test::Mojo->new(MyApp->new, {foo => 'bar'});

Construct a new L<Test::Mojo> object. In addition to a class name or L<Mojo::File> object pointing to the application
script, you can pass along a hash reference with configuration values that will be used to override the application
configuration. The special configuration value C<config_override> will be set in L<Mojolicious/"config"> as well, which
is used to disable configuration plugins like L<Mojolicious::Plugin::Config>, L<Mojolicious::Plugin::JSONConfig> and
L<Mojolicious::Plugin::NotYAMLConfig> for tests.

  # Load application script relative to the "t" directory
  use Mojo::File qw(curfile);
  my $t = Test::Mojo->new(curfile->dirname->sibling('myapp.pl'));

=head2 options_ok

  $t = $t->options_ok('http://example.com/foo');
  $t = $t->options_ok('/foo');
  $t = $t->options_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->options_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->options_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<OPTIONS> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"options">,
except for the callback.

=head2 or

  $t = $t->or(sub {...});

Execute callback if the value of L</"success"> is false.

  # Diagnostics
  $t->get_ok('/bad')->or(sub { diag 'Must have been Glen!' })
    ->status_is(200)->or(sub { diag $t->tx->res->dom->at('title')->text });

=head2 patch_ok

  $t = $t->patch_ok('http://example.com/foo');
  $t = $t->patch_ok('/foo');
  $t = $t->patch_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->patch_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->patch_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<PATCH> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"patch">,
except for the callback.

=head2 post_ok

  $t = $t->post_ok('http://example.com/foo');
  $t = $t->post_ok('/foo');
  $t = $t->post_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->post_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->post_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<POST> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"post">, except
for the callback.

  # Test file upload
  my $upload = {foo => {content => 'bar', filename => 'baz.txt'}};
  $t->post_ok('/upload' => form => $upload)->status_is(200);

  # Test JSON API
  $t->post_ok('/hello.json' => json => {hello => 'world'})
    ->status_is(200)
    ->json_is({bye => 'world'});

=head2 put_ok

  $t = $t->put_ok('http://example.com/foo');
  $t = $t->put_ok('/foo');
  $t = $t->put_ok('/foo' => {Accept => '*/*'} => 'Content!');
  $t = $t->put_ok('/foo' => {Accept => '*/*'} => form => {a => 'b'});
  $t = $t->put_ok('/foo' => {Accept => '*/*'} => json => {a => 'b'});

Perform a C<PUT> request and check for transport errors, takes the same arguments as L<Mojo::UserAgent/"put">, except
for the callback.

=head2 request_ok

  $t = $t->request_ok(Mojo::Transaction::HTTP->new);

Perform request and check for transport errors.

  # Request with custom method
  my $tx = $t->ua->build_tx(FOO => '/test.json' => json => {foo => 1});
  $t->request_ok($tx)->status_is(200)->json_is({success => 1});

  # Request with custom cookie
  my $tx = $t->ua->build_tx(GET => '/account');
  $tx->req->cookies({name => 'user', value => 'sri'});
  $t->request_ok($tx)->status_is(200)->text_is('head > title' => 'Hello sri');

  # Custom WebSocket handshake
  my $tx = $t->ua->build_websocket_tx('/foo');
  $tx->req->headers->remove('User-Agent');
  $t->request_ok($tx)->message_ok->message_is('bar')->finish_ok;

=head2 reset_session

  $t = $t->reset_session;

Reset user agent session.

=head2 send_ok

  $t = $t->send_ok({binary => $bytes});
  $t = $t->send_ok({text   => $bytes});
  $t = $t->send_ok({json   => {test => [1, 2, 3]}});
  $t = $t->send_ok([$fin, $rsv1, $rsv2, $rsv3, $op, $payload]);
  $t = $t->send_ok($chars);
  $t = $t->send_ok($chars, 'sent successfully');

Send message or frame via WebSocket.

  # Send JSON object as "Text" message
  $t->websocket_ok('/echo.json')
    ->send_ok({json => {test => 'I ♥ Mojolicious!'}})
    ->message_ok
    ->json_message_is('/test' => 'I ♥ Mojolicious!')
    ->finish_ok;

=head2 status_is

  $t = $t->status_is(200);
  $t = $t->status_is(200, 'right status');

Check response status for exact match.

=head2 status_isnt

  $t = $t->status_isnt(200);
  $t = $t->status_isnt(200, 'different status');

Opposite of L</"status_is">.

=head2 test

  $t = $t->test('is', 'first value', 'second value', 'right value');

Call L<Test::More> functions through L</"handler">, used to implement L<Test::Mojo> roles. The result will be stored in
L</"success">.

=head2 text_is

  $t = $t->text_is('div.foo[x=y]' => 'Hello!');
  $t = $t->text_is('html head title' => 'Hello!', 'right title');

Checks text content of the CSS selectors first matching HTML/XML element for exact match with L<Mojo::DOM/"at">.

=head2 text_isnt

  $t = $t->text_isnt('div.foo[x=y]' => 'Hello!');
  $t = $t->text_isnt('html head title' => 'Hello!', 'different title');

Opposite of L</"text_is">.

=head2 text_like

  $t = $t->text_like('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_like('html head title' => qr/Hello/, 'right title');

Checks text content of the CSS selectors first matching HTML/XML element for similar match with L<Mojo::DOM/"at">.

=head2 text_unlike

  $t = $t->text_unlike('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_unlike('html head title' => qr/Hello/, 'different title');

Opposite of L</"text_like">.

=head2 websocket_ok

  $t = $t->websocket_ok('http://example.com/echo');
  $t = $t->websocket_ok('/echo');
  $t = $t->websocket_ok('/echo' => {DNT => 1} => ['v1.proto']);

Open a WebSocket connection with transparent handshake, takes the same arguments as L<Mojo::UserAgent/"websocket">,
except for the callback.

  # WebSocket with permessage-deflate compression
  $t->websocket_ok('/' => {'Sec-WebSocket-Extensions' => 'permessage-deflate'})
    ->send_ok('y' x 50000)
    ->message_ok
    ->message_is('z' x 50000)
    ->finish_ok;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
