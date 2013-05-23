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
use Mojo::JSON;
use Mojo::JSON::Pointer;
use Mojo::Server;
use Mojo::UserAgent;
use Mojo::Util qw(decode encode);
use Test::More ();

has [qw(message tx)];
has ua => sub { Mojo::UserAgent->new->ioloop(Mojo::IOLoop->singleton) };

# Silent or loud tests
$ENV{MOJO_LOG_LEVEL} ||= $ENV{HARNESS_IS_VERBOSE} ? 'debug' : 'fatal';

sub new {
  my $self = shift->SUPER::new;
  return $self unless my $app = shift;
  return $self->app(ref $app ? $app : Mojo::Server->new->build_app($app));
}

sub app {
  my ($self, $app) = @_;
  return $self->ua->app unless $app;
  $self->ua->app($app);
  return $self;
}

sub content_is {
  my ($self, $value, $desc) = @_;
  $desc ||= 'exact match for content';
  return $self->_test('is', $self->_get_content($self->tx), $value, $desc);
}

sub content_isnt {
  my ($self, $value, $desc) = @_;
  $desc ||= 'no match for content';
  return $self->_test('isnt', $self->_get_content($self->tx), $value, $desc);
}

sub content_like {
  my ($self, $regex, $desc) = @_;
  $desc ||= 'content is similar';
  return $self->_test('like', $self->_get_content($self->tx), $regex, $desc);
}

sub content_unlike {
  my ($self, $regex, $desc) = @_;
  $desc ||= 'content is not similar';
  return $self->_test('unlike', $self->_get_content($self->tx), $regex, $desc);
}

sub content_type_is {
  my ($self, $type, $desc) = @_;
  $desc ||= "Content-Type: $type";
  return $self->_test('is', $self->tx->res->headers->content_type, $type,
    $desc);
}

sub content_type_isnt {
  my ($self, $type, $desc) = @_;
  $desc ||= "not Content-Type: $type";
  return $self->_test('isnt', $self->tx->res->headers->content_type, $type,
    $desc);
}

sub content_type_like {
  my ($self, $regex, $desc) = @_;
  $desc ||= 'Content-Type is similar';
  return $self->_test('like', $self->tx->res->headers->content_type, $regex,
    $desc);
}

sub content_type_unlike {
  my ($self, $regex, $desc) = @_;
  $desc ||= 'Content-Type is not similar';
  return $self->_test('unlike', $self->tx->res->headers->content_type,
    $regex, $desc);
}

sub delete_ok { shift->_request_ok(delete => @_) }

sub element_exists {
  my ($self, $selector, $desc) = @_;
  $desc ||= encode 'UTF-8', qq{element for selector "$selector" exists};
  return $self->_test('ok', $self->tx->res->dom->at($selector), $desc);
}

sub element_exists_not {
  my ($self, $selector, $desc) = @_;
  $desc ||= encode 'UTF-8', qq{no element for selector "$selector"};
  return $self->_test('ok', !$self->tx->res->dom->at($selector), $desc);
}

sub finish_ok {
  my $self = shift;
  $self->tx->finish(@_);
  Mojo::IOLoop->one_tick while !$self->{finished};
  return $self->_test('ok', 1, 'closed WebSocket');
}

sub finished_ok {
  my ($self, $code) = @_;
  Mojo::IOLoop->one_tick while !$self->{finished};
  Test::More::diag "WebSocket closed with status $self->{finished}[0]"
    unless my $ok = grep { $self->{finished}[0] == $_ } $code, 1006;
  return $self->_test('ok', $ok, "WebSocket closed with status $code");
}

sub get_ok  { shift->_request_ok(get  => @_) }
sub head_ok { shift->_request_ok(head => @_) }

sub header_is {
  my ($self, $name, $value, $desc) = @_;
  $desc ||= "$name: " . ($value ? $value : '');
  return $self->_test('is', scalar $self->tx->res->headers->header($name),
    $value, $desc);
}

sub header_isnt {
  my ($self, $name, $value, $desc) = @_;
  $desc ||= "not $name: " . ($value ? $value : '');
  return $self->_test('isnt', scalar $self->tx->res->headers->header($name),
    $value, $desc);
}

sub header_like {
  my ($self, $name, $regex, $desc) = @_;
  return $self->_test('like', scalar $self->tx->res->headers->header($name),
    $regex, $desc || "$name is similar");
}

sub header_unlike {
  my ($self, $name, $regex, $desc) = @_;
  return $self->_test('unlike',
    scalar $self->tx->res->headers->header($name) // '',
    $regex, $desc || "$name is not similar");
}

sub json_has {
  my ($self, $p, $desc) = @_;
  $desc ||= qq{has value for JSON Pointer "$p"};
  return $self->_test('ok',
    !!Mojo::JSON::Pointer->new->contains($self->tx->res->json, $p), $desc);
}

sub json_hasnt {
  my ($self, $p, $desc) = @_;
  $desc ||= qq{has no value for JSON Pointer "$p"};
  return $self->_test('ok',
    !Mojo::JSON::Pointer->new->contains($self->tx->res->json, $p), $desc);
}

sub json_is {
  my $self = shift;
  my ($p, $data) = ref $_[0] ? ('', shift) : (shift, shift);
  my $desc = shift || qq{exact match for JSON Pointer "$p"};
  return $self->_test('is_deeply', $self->tx->res->json($p), $data, $desc);
}

sub json_message_has {
  my ($self, $p, $desc) = @_;
  $desc ||= qq{has value for JSON Pointer "$p"};
  return $self->_test('ok', $self->_json(contains => $p), $desc);
}

sub json_message_hasnt {
  my ($self, $p, $desc) = @_;
  $desc ||= qq{has no value for JSON Pointer "$p"};
  return $self->_test('ok', !$self->_json(contains => $p), $desc);
}

sub json_message_is {
  my $self = shift;
  my ($p, $data) = ref $_[0] ? ('', shift) : (shift, shift);
  my $desc = shift || qq{exact match for JSON Pointer "$p"};
  return $self->_test('is_deeply', $self->_json(get => $p), $data, $desc);
}

sub message_is {
  my ($self, $value, $desc) = @_;
  return $self->_message('is', $value, $desc || 'exact match for message');
}

sub message_isnt {
  my ($self, $value, $desc) = @_;
  return $self->_message('isnt', $value, $desc || 'no match for message');
}

sub message_like {
  my ($self, $regex, $desc) = @_;
  return $self->_message('like', $regex, $desc || 'message is similar');
}

sub message_ok {
  my ($self, $desc) = @_;
  return $self->_test('ok', !!$self->_wait, $desc || 'message received');
}

sub message_unlike {
  my ($self, $regex, $desc) = @_;
  return $self->_message('unlike', $regex, $desc || 'message is not similar');
}

sub options_ok { shift->_request_ok(options => @_) }

sub or {
  my ($self, $cb) = @_;
  $self->$cb unless $self->{latest};
  return $self;
}

sub patch_ok { shift->_request_ok(patch => @_) }
sub post_ok  { shift->_request_ok(post  => @_) }
sub put_ok   { shift->_request_ok(put   => @_) }

sub request_ok {
  my $self = shift;
  my $tx   = $self->tx($self->ua->start(shift))->tx;
  return $self->_test('ok', $tx->is_finished, shift || 'perform request');
}

sub reset_session {
  my $self = shift;
  if (my $jar = $self->ua->cookie_jar) { $jar->empty }
  return $self->tx(undef);
}

sub send_ok {
  my ($self, $msg, $desc) = @_;
  $self->tx->send($msg => sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;
  return $self->_test('ok', 1, $desc || 'send message');
}

sub status_is {
  my ($self, $status, $desc) = @_;
  $desc ||= "$status " . $self->tx->res->new(code => $status)->default_message;
  return $self->_test('is', $self->tx->res->code, $status, $desc);
}

sub status_isnt {
  my ($self, $status, $desc) = @_;
  $desc
    ||= "not $status " . $self->tx->res->new(code => $status)->default_message;
  return $self->_test('isnt', $self->tx->res->code, $status, $desc);
}

sub text_is {
  my ($self, $selector, $value, $desc) = @_;
  $desc ||= encode 'UTF-8', qq{exact match for selector "$selector"};
  return $self->_test('is', $self->_text($selector), $value, $desc);
}

sub text_isnt {
  my ($self, $selector, $value, $desc) = @_;
  $desc ||= encode 'UTF-8', qq{no match for selector "$selector"};
  return $self->_test('isnt', $self->_text($selector), $value, $desc);
}

sub text_like {
  my ($self, $selector, $regex, $desc) = @_;
  $desc ||= encode 'UTF-8', qq{similar match for selector "$selector"};
  return $self->_test('like', $self->_text($selector), $regex, $desc);
}

sub text_unlike {
  my ($self, $selector, $regex, $desc) = @_;
  $desc ||= encode 'UTF-8', qq{no similar match for selector "$selector"};
  return $self->_test('unlike', $self->_text($selector), $regex, $desc);
}

sub websocket_ok {
  my ($self, $url) = (shift, shift);

  # Establish WebSocket connection
  $self->{messages} = [];
  $self->{finished} = undef;
  $self->ua->websocket(
    $url => @_ => sub {
      my ($ua, $tx) = @_;
      $self->tx($tx);
      $tx->on(finish => sub { shift; $self->{finished} = [@_] });
      $tx->on(binary => sub { push @{$self->{messages}}, [binary => pop] });
      $tx->on(text   => sub { push @{$self->{messages}}, [text   => pop] });
      Mojo::IOLoop->stop;
    }
  );
  Mojo::IOLoop->start;

  my $desc = encode 'UTF-8', "WebSocket $url";
  return $self->_test('ok', $self->tx->res->code eq 101, $desc);
}

sub _get_content {
  my ($self, $tx) = @_;
  my $content = $tx->res->body;
  my $charset = $tx->res->content->charset;
  return $charset ? decode($charset, $content) : $content;
}

sub _json {
  my ($self, $method, $p) = @_;
  return Mojo::JSON::Pointer->new->$method(
    Mojo::JSON->new->decode(@{$self->message}[1]), $p);
}

sub _message {
  my ($self, $name, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my ($type, $msg) = @{$self->message};

  # Type check
  if (ref $value eq 'HASH') {
    my $expect = exists $value->{text} ? 'text' : 'binary';
    $value = $value->{$expect};
    $msg = '' unless $type eq $expect;
  }

  # Decode text frame if there is no type check
  else { $msg = decode 'UTF-8', $msg if $type eq 'text' }

  return $self->_test($name, $msg // '', $value, $desc);
}

sub _request_ok {
  my ($self, $method, $url) = (shift, shift, shift);

  # Perform request against application
  $self->tx($self->ua->$method($url, @_));
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  my ($err, $code) = $self->tx->error;
  Test::More::diag $err if !(my $ok = !$err || $code) && $err;
  return $self->_test('ok', $ok, encode('UTF-8', "@{[uc $method]} $url"));
}

sub _test {
  my ($self, $name, @args) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 2;
  $self->{latest} = Test::More->can($name)->(@args);
  return $self;
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

Test::Mojo - Testing Mojo!

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
    ->json_is('/results/4/title' => 'Perl rocks!');

  # WebSocket
  $t->websocket_ok('/echo')
    ->send_ok('hello')
    ->message_ok
    ->message_is('echo: hello')
    ->finish_ok;

  done_testing();

=head1 DESCRIPTION

L<Test::Mojo> is a collection of testing helpers for everyone developing
L<Mojo> and L<Mojolicious> applications.

=head1 ATTRIBUTES

L<Test::Mojo> implements the following attributes.

=head2 message

  my $msg = $t->message;
  $t      = $t->message([text => $bytes]);

Current WebSocket message.

  # Test custom message
  $t->message([binary => $bytes])
    ->json_message_has('/foo/bar')
    ->json_message_hasnt('/bar')
    ->json_message_is('/foo/baz' => {yada => [1, 2, 3]});

=head2 tx

  my $tx = $t->tx;
  $t     = $t->tx(Mojo::Transaction::HTTP->new);

Current transaction, usually a L<Mojo::Transaction::HTTP> object.

  # More specific tests
  is $t->tx->res->json->{foo}, 'bar', 'right value';
  ok $t->tx->res->content->is_multipart, 'multipart content';

  # Test custom transactions
  $t->tx($t->tx->previous)->status_is(302)->header_like(Location => qr/foo/);

=head2 ua

  my $ua = $t->ua;
  $t     = $t->ua(Mojo::UserAgent->new);

User agent used for testing, defaults to a L<Mojo::UserAgent> object.

  # Allow redirects
  $t->ua->max_redirects(10);

  # Use absolute URL for request with Basic authentication
  my $url = $t->ua->app_url->userinfo('sri:secr3t')->path('/secrets.json');
  $t->post_ok($url => json => {limit => 10})
    ->status_is(200)
    ->json_is('/1/content', 'Mojo rocks!');

  # Customize all transactions (including followed redirects)
  $t->ua->on(start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->accept_language('en-US');
  });

=head1 METHODS

L<Test::Mojo> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 new

  my $t = Test::Mojo->new;
  my $t = Test::Mojo->new('MyApp');
  my $t = Test::Mojo->new(MyApp->new);

Construct a new L<Test::Mojo> object.

=head2 app

  my $app = $t->app;
  $t      = $t->app(MyApp->new);

Access application with L<Mojo::UserAgent/"app">.

  # Change log level
  $t->app->log->level('fatal');

  # Test application directly
  is $t->app->defaults->{foo}, 'bar', 'right value';
  ok $t->app->routes->find('echo')->is_websocket, 'WebSocket route';

  # Change application behavior
  $t->app->hook(before_dispatch => sub {
    my $self = shift;
    $self->render(text => 'This request did not reach the router.')
      if $self->req->url->path->contains('/user');
  });

  # Extract additional information
  my $stash;
  $t->app->hook(after_dispatch => sub { $stash = shift->stash });

=head2 content_is

  $t = $t->content_is('working!');
  $t = $t->content_is('working!', 'right content');

Check response content for exact match.

=head2 content_isnt

  $t = $t->content_isnt('working!');
  $t = $t->content_isnt('working!', 'different content');

Opposite of C<content_is>.

=head2 content_like

  $t = $t->content_like(qr/working!/);
  $t = $t->content_like(qr/working!/, 'right content');

Check response content for similar match.

=head2 content_unlike

  $t = $t->content_unlike(qr/working!/);
  $t = $t->content_unlike(qr/working!/, 'different content');

Opposite of C<content_like>.

=head2 content_type_is

  $t = $t->content_type_is('text/html');
  $t = $t->content_type_is('text/html', 'right content type');

Check response C<Content-Type> header for exact match.

=head2 content_type_isnt

  $t = $t->content_type_isnt('text/html');
  $t = $t->content_type_isnt('text/html', 'different content type');

Opposite of C<content_type_is>.

=head2 content_type_like

  $t = $t->content_type_like(qr/text/);
  $t = $t->content_type_like(qr/text/, 'right content type');

Check response C<Content-Type> header for similar match.

=head2 content_type_unlike

  $t = $t->content_type_unlike(qr/text/);
  $t = $t->content_type_unlike(qr/text/, 'different content type');

Opposite of C<content_type_like>.

=head2 delete_ok

  $t = $t->delete_ok('/foo');
  $t = $t->delete_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->delete_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->delete_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<DELETE> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"delete">, except for the callback.

=head2 element_exists

  $t = $t->element_exists('div.foo[x=y]');
  $t = $t->element_exists('html head title', 'has a title');

Checks for existence of the CSS selectors first matching HTML/XML element with
L<Mojo::DOM>.

=head2 element_exists_not

  $t = $t->element_exists_not('div.foo[x=y]');
  $t = $t->element_exists_not('html head title', 'has no title');

Opposite of C<element_exists>.

=head2 finish_ok

  $t = $t->finish_ok;
  $t = $t->finish_ok(1000);
  $t = $t->finish_ok(1003 => 'Cannot accept data!');

Close WebSocket connection gracefully.

=head2 finished_ok

  $t = $t->finished_ok(1000);

Wait for WebSocket connection to be closed gracefully and check status.

=head2 get_ok

  $t = $t->get_ok('/foo');
  $t = $t->get_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->get_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->get_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<GET> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"get">, except for the callback.

=head2 head_ok

  $t = $t->head_ok('/foo');
  $t = $t->head_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->head_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->head_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<HEAD> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"head">, except for the callback.

=head2 header_is

  $t = $t->header_is(Expect => 'fun');
  $t = $t->header_is(Expect => 'fun', 'right header');

Check response header for exact match.

=head2 header_isnt

  $t = $t->header_isnt(Expect => 'fun');
  $t = $t->header_isnt(Expect => 'fun', 'different header');

Opposite of C<header_is>.

=head2 header_like

  $t = $t->header_like(Expect => qr/fun/);
  $t = $t->header_like(Expect => qr/fun/, 'right header');

Check response header for similar match.

=head2 header_unlike

  $t = $t->header_like(Expect => qr/fun/);
  $t = $t->header_like(Expect => qr/fun/, 'different header');

Opposite of C<header_like>.

=head2 json_has

  $t = $t->json_has('/foo');
  $t = $t->json_has('/minibar', 'has a minibar');

Check if JSON response contains a value that can be identified using the given
JSON Pointer with L<Mojo::JSON::Pointer>.

=head2 json_hasnt

  $t = $t->json_hasnt('/foo');
  $t = $t->json_hasnt('/minibar', 'no minibar');

Opposite of C<json_has>.

=head2 json_is

  $t = $t->json_is({foo => [1, 2, 3]});
  $t = $t->json_is({foo => [1, 2, 3]}, 'right content');
  $t = $t->json_is('/foo' => [1, 2, 3]);
  $t = $t->json_is('/foo/1' => 2, 'right value');

Check the value extracted from JSON response using the given JSON Pointer with
L<Mojo::JSON::Pointer>, which defaults to the root value if it is omitted.

=head2 json_message_has

  $t = $t->json_message_has('/foo');
  $t = $t->json_message_has('/minibar', 'has a minibar');

Check if JSON WebSocket message contains a value that can be identified using
the given JSON Pointer with L<Mojo::JSON::Pointer>.

=head2 json_message_hasnt

  $t = $t->json_message_hasnt('/foo');
  $t = $t->json_message_hasnt('/minibar', 'no minibar');

Opposite of C<json_message_has>.

=head2 json_message_is

  $t = $t->json_message_is({foo => [1, 2, 3]});
  $t = $t->json_message_is({foo => [1, 2, 3]}, 'right content');
  $t = $t->json_message_is('/foo' => [1, 2, 3]);
  $t = $t->json_message_is('/foo/1' => 2, 'right value');

Check the value extracted from JSON WebSocket message using the given JSON
Pointer with L<Mojo::JSON::Pointer>, which defaults to the root value if it is
omitted.

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

Opposite of C<message_is>.

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

Opposite of C<message_like>.

=head2 options_ok

  $t = $t->options_ok('/foo');
  $t = $t->options_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->options_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->options_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<OPTIONS> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"options">, except for the callback.

=head2 or

  $t = $t->or(sub {...});

Invoke callback if previous test failed.

  # Diagnostics
  $t->get_ok('/bad')->or(sub { diag 'Must have been Glen!' })
    ->status_is(200)->or(sub { diag $t->tx->res->dom->at('title')->text });

=head2 patch_ok

  $t = $t->patch_ok('/foo');
  $t = $t->patch_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->patch_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->patch_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<PATCH> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"patch">, except for the callback.

=head2 post_ok

  $t = $t->post_ok('/foo');
  $t = $t->post_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->post_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->post_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<POST> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"post">, except for the callback.

  # Test file upload
  $t->post_ok('/upload' => form => {foo => {content => 'bar'}})
    ->status_is(200);

  # Test JSON API
  $t->post_json_ok('/hello.json' => json => {hello => 'world'})
    ->status_is(200)
    ->json_is({bye => 'world'});

=head2 put_ok

  $t = $t->put_ok('/foo');
  $t = $t->put_ok('/foo' => {DNT => 1} => 'Hi!');
  $t = $t->put_ok('/foo' => {DNT => 1} => form => {a => 'b'});
  $t = $t->put_ok('/foo' => {DNT => 1} => json => {a => 'b'});

Perform a C<PUT> request and check for transport errors, takes the same
arguments as L<Mojo::UserAgent/"put">, except for the callback.

=head2 request_ok

  $t = $t->request_ok(Mojo::Transaction::HTTP->new);
  $t = $t->request_ok(Mojo::Transaction::HTTP->new, 'request successful');

Perform request and check for transport errors.

  # Request with custom method
  my $tx = $t->ua->build_tx(FOO => '/test.json' => json => {foo => 1});
  $t->request_ok($tx)->status_is(200)->json_is({success => 1});

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

Opposite of C<status_is>.

=head2 text_is

  $t = $t->text_is('div.foo[x=y]' => 'Hello!');
  $t = $t->text_is('html head title' => 'Hello!', 'right title');

Checks text content of the CSS selectors first matching HTML/XML element for
exact match with L<Mojo::DOM>.

=head2 text_isnt

  $t = $t->text_isnt('div.foo[x=y]' => 'Hello!');
  $t = $t->text_isnt('html head title' => 'Hello!', 'different title');

Opposite of C<text_is>.

=head2 text_like

  $t = $t->text_like('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_like('html head title' => qr/Hello/, 'right title');

Checks text content of the CSS selectors first matching HTML/XML element for
similar match with L<Mojo::DOM>.

=head2 text_unlike

  $t = $t->text_unlike('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_unlike('html head title' => qr/Hello/, 'different title');

Opposite of C<text_like>.

=head2 websocket_ok

  $t = $t->websocket_ok('/echo');
  $t = $t->websocket_ok('/echo' => {DNT => 1} => ['v1.proto']);

Open a WebSocket connection with transparent handshake, takes the same
arguments as L<Mojo::UserAgent/"websocket">, except for the callback.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
