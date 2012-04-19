package Test::Mojo;
use Mojo::Base -base;

use Mojo::IOLoop;
use Mojo::Message::Response;
use Mojo::UserAgent;
use Mojo::Util qw/decode encode/;
use Test::More ();

has ua => sub { Mojo::UserAgent->new->ioloop(Mojo::IOLoop->singleton) };
has 'tx';

# Silent or loud tests
$ENV{MOJO_LOG_LEVEL} ||= $ENV{HARNESS_IS_VERBOSE} ? 'debug' : 'fatal';

# "Ooh, a graduate student huh?
#  How come you guys can go to the moon but can't make my shoes smell good?"
sub new {
  my $self = shift->SUPER::new;
  return @_ ? $self->app(shift) : $self;
}

sub app {
  my ($self, $app) = @_;
  return $self->ua->app unless $app;
  $ENV{MOJO_APP} ||= $app;
  $self->ua->app($app);
  return $self;
}

sub content_is {
  my ($self, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is $self->_get_content($self->tx), $value,
    $desc || 'exact match for content';
  return $self;
}

sub content_isnt {
  my ($self, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::isnt $self->_get_content($self->tx), $value,
    $desc || 'no match for content';
  return $self;
}

sub content_like {
  my ($self, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like $self->_get_content($self->tx), $regex,
    $desc || 'content is similar';
  return $self;
}

sub content_unlike {
  my ($self, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::unlike $self->_get_content($self->tx), $regex,
    $desc || 'content is not similar';
  return $self;
}

# "Marge, I can't wear a pink shirt to work.
#  Everybody wears white shirts.
#  I'm not popular enough to be different."
sub content_type_is {
  my ($self, $type) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is $self->tx->res->headers->content_type, $type,
    "Content-Type: $type";
  return $self;
}

sub content_type_isnt {
  my ($self, $type) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::isnt $self->tx->res->headers->content_type, $type,
    "not Content-Type: $type";
  return $self;
}

sub content_type_like {
  my ($self, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like $self->tx->res->headers->content_type, $regex,
    $desc || 'Content-Type is similar';
  return $self;
}

sub content_type_unlike {
  my ($self, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::unlike $self->tx->res->headers->content_type, $regex,
    $desc || 'Content-Type is not similar';
  return $self;
}

# "A job's a job. I mean, take me.
#  If my plant pollutes the water and poisons the town,
#  by your logic, that would make me a criminal."
sub delete_ok { shift->_request_ok(delete => @_) }

sub element_exists {
  my ($self, $selector, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok $self->tx->res->dom->at($selector),
    $desc || qq/"$selector" exists/;
  return $self;
}

sub element_exists_not {
  my ($self, $selector, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok !$self->tx->res->dom->at($selector),
    $desc || qq/"$selector" exists not/;
  return $self;
}

sub finish_ok {
  my ($self, $desc) = @_;

  $self->tx->finish;
  Mojo::IOLoop->one_tick while !$self->{finished};
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok 1, $desc || 'finished websocket';

  return $self;
}

sub get_ok  { shift->_request_ok(get  => @_) }
sub head_ok { shift->_request_ok(head => @_) }

sub header_is {
  my ($self, $name, $value) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is scalar $self->tx->res->headers->header($name), $value,
    "$name: " . ($value ? $value : '');
  return $self;
}

sub header_isnt {
  my ($self, $name, $value) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::isnt scalar $self->tx->res->headers->header($name), $value,
    "not $name: " . ($value ? $value : '');
  return $self;
}

sub header_like {
  my ($self, $name, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like scalar $self->tx->res->headers->header($name), $regex,
    $desc || "$name is similar";
  return $self;
}

sub header_unlike {
  my ($self, $name, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::unlike scalar $self->tx->res->headers->header($name), $regex,
    $desc || "$name is not similar";
  return $self;
}

sub json_content_is {
  my ($self, $data, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is_deeply $self->tx->res->json, $data,
    $desc || 'exact match for JSON structure';
  return $self;
}

sub json_is {
  my ($self, $p, $data, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is_deeply $self->tx->res->json($p), $data,
    $desc || qq/exact match for JSON Pointer "$p"/;
  return $self;
}

sub json_has {
  my ($self, $p, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok(
    Mojo::JSON::Pointer->contains($self->tx->res->json, $p),
    $desc || qq/has value for JSON Pointer "$p"/
  );
  return $self;
}

sub json_hasnt {
  my ($self, $p, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok(
    !Mojo::JSON::Pointer->contains($self->tx->res->json, $p),
    $desc || qq/has no value for JSON Pointer "$p"/
  );
  return $self;
}

sub message_is {
  my ($self, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is $self->_message, $value, $desc || 'exact match for message';
  return $self;
}

sub message_isnt {
  my ($self, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::isnt $self->_message, $value, $desc || 'no match for message';
  return $self;
}

sub message_like {
  my ($self, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like $self->_message, $regex, $desc || 'message is similar';
  return $self;
}

sub message_unlike {
  my ($self, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::unlike $self->_message, $regex,
    $desc || 'message is not similar';
  return $self;
}

# "God bless those pagans."
sub options_ok { shift->_request_ok(options => @_) }
sub patch_ok   { shift->_request_ok(patch   => @_) }
sub post_ok    { shift->_request_ok(post    => @_) }

sub post_form_ok {
  my ($self, $url) = (shift, shift);

  $self->tx($self->ua->post_form($url, @_));
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok $self->tx->is_finished, encode('UTF-8', "post $url");

  return $self;
}

# "WHO IS FONZY!?! Don't they teach you anything at school?"
sub put_ok { shift->_request_ok(put => @_) }

sub reset_session {
  my $self = shift;
  $self->ua->cookie_jar->empty;
  $self->tx(undef);
  return $self;
}

sub send_ok {
  my ($self, $message, $desc) = @_;

  $self->tx->send($message, sub { Mojo::IOLoop->stop });
  Mojo::IOLoop->start;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok 1, $desc || 'send message';

  return $self;
}

# "Internet! Is that thing still around?"
sub status_is {
  my ($self, $status) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is $self->tx->res->code, $status, "$status "
    . Mojo::Message::Response->new(code => $status)->default_message;
  return $self;
}

sub status_isnt {
  my ($self, $status) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::isnt $self->tx->res->code, $status, "not $status "
    . Mojo::Message::Response->new(code => $status)->default_message;
  return $self;
}

sub text_is {
  my ($self, $selector, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is $self->_text($selector), $value, $desc || $selector;
  return $self;
}

sub text_isnt {
  my ($self, $selector, $value, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::isnt $self->_text($selector), $value, $desc || $selector;
  return $self;
}

# "Hello, my name is Barney Gumble, and I'm an alcoholic.
#  Mr Gumble, this is a girl scouts meeting.
#  Is it, or is it you girls can't admit that you have a problem?"
sub text_like {
  my ($self, $selector, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like $self->_text($selector), $regex, $desc || $selector;
  return $self;
}

sub text_unlike {
  my ($self, $selector, $regex, $desc) = @_;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::unlike $self->_text($selector), $regex, $desc || $selector;
  return $self;
}

sub websocket_ok {
  my ($self, $url) = (shift, shift);

  $self->{messages} = [];
  $self->{finished} = 0;
  $self->ua->websocket(
    $url, @_,
    sub {
      $self->tx(my $tx = pop);
      $tx->on(finish => sub { $self->{finished} = 1 });
      $tx->on(message => sub { push @{$self->{messages}}, pop });
      Mojo::IOLoop->stop;
    }
  );
  Mojo::IOLoop->start;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok $self->tx->res->code eq 101,
    encode('UTF-8', "websocket $url");

  return $self;
}

sub _get_content {
  my ($self, $tx) = @_;
  my $content = $tx->res->body;
  my $charset = $tx->res->content->charset;
  return $charset ? decode($charset, $content) : $content;
}

sub _message {
  my $self = shift;
  Mojo::IOLoop->one_tick while !$self->{finished} && !@{$self->{messages}};
  return shift @{$self->{messages}};
}

# "Are you sure this is the Sci-Fi Convention? It's full of nerds!"
sub _request_ok {
  my ($self, $method, $url, $headers, $body) = @_;
  $body = $headers if !ref $headers && @_ > 3;
  $headers = {} if !ref $headers;

  # Perform request against application
  $self->tx($self->ua->$method($url, %$headers, $body));
  local $Test::Builder::Level = $Test::Builder::Level + 2;
  my ($err, $code) = $self->tx->error;
  Test::More::diag $err if !(my $ok = !$err || $code) && $err;
  Test::More::ok $ok, encode('UTF-8', "$method $url");

  return $self;
}

sub _text {
  my ($self, $selector) = @_;
  my $text;
  if (my $e = $self->tx->res->dom->at($selector)) { $text = $e->text }
  return $text;
}

1;
__END__

=head1 NAME

Test::Mojo - Testing Mojo!

=head1 SYNOPSIS

  use Test::More tests => 12;
  use Test::Mojo;

  my $t = Test::Mojo->new('MyApp');

  $t->get_ok('/welcome')->status_is(200)->text_is('div#message' => 'Hello!');

  $t->post_form_ok('/search.json' => {q => 'Perl'})
    ->status_is(200)
    ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
    ->header_isnt('X-Bender' => 'Bite my shiny metal ass!');
    ->json_is('/results/4/title' => 'Perl rocks!');

  $t->websocket_ok('/echo')
    ->send_ok('hello')
    ->message_is('echo: hello')
    ->finish_ok;

=head1 DESCRIPTION

L<Test::Mojo> is a collection of testing helpers for everyone developing
L<Mojo> and L<Mojolicious> applications.

=head1 ATTRIBUTES

L<Test::Mojo> implements the following attributes.

=head2 C<tx>

  my $tx = $t->tx;
  $t     = $t->tx(Mojo::Transaction::HTTP->new);

Current transaction, usually a L<Mojo::Transaction::HTTP> object.

  # More specific tests
  is $t->tx->res->json->{foo}, 'bar', 'right value';
  ok $t->tx->res->is_multipart, 'multipart content';

  # Test custom transaction
  my $tx = $t->ua->build_form_tx('/user/99' => {name => 'sri'});
  $tx->req->method('PUT');
  $t->tx($t->ua->start($tx))
    ->status_is(200)
    ->text_is('div#message' => 'User has been replaced.');

=head2 C<ua>

  my $ua = $t->ua;
  $t     = $t->ua(Mojo::UserAgent->new);

User agent used for testing, defaults to a L<Mojo::UserAgent> object.

  # Allow redirects
  $t->ua->max_redirects(10);

  # Customize all transactions (including followed redirects)
  $t->ua->on(start => sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->accept_language('en-US');
  });

  # Request with Basic authentication
  $t->get_ok($t->ua->app_url->userinfo('sri:secr3t')->path('/secrets'));

=head1 METHODS

L<Test::Mojo> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $t = Test::Mojo->new;
  my $t = Test::Mojo->new('MyApp');
  my $t = Test::Mojo->new(MyApp->new);

Construct a new L<Test::Mojo> object.

=head2 C<app>

  my $app = $t->app;
  $t      = $t->app(MyApp->new);

Alias for L<Mojo::UserAgent/"app">.

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

=head2 C<content_is>

  $t = $t->content_is('working!');
  $t = $t->content_is('working!', 'right content');

Check response content for exact match.

=head2 C<content_isnt>

  $t = $t->content_isnt('working!');
  $t = $t->content_isnt('working!', 'different content');

Opposite of C<content_is>.

=head2 C<content_like>

  $t = $t->content_like(qr/working!/);
  $t = $t->content_like(qr/working!/, 'right content');

Check response content for similar match.

=head2 C<content_unlike>

  $t = $t->content_unlike(qr/working!/);
  $t = $t->content_unlike(qr/working!/, 'different content');

Opposite of C<content_like>.

=head2 C<content_type_is>

  $t = $t->content_type_is('text/html');

Check response C<Content-Type> header for exact match.

=head2 C<content_type_isnt>

  $t = $t->content_type_isnt('text/html');

Opposite of C<content_type_is>.

=head2 C<content_type_like>

  $t = $t->content_type_like(qr/text/);
  $t = $t->content_type_like(qr/text/, 'right content type');

Check response C<Content-Type> header for similar match.

=head2 C<content_type_unlike>

  $t = $t->content_type_unlike(qr/text/);
  $t = $t->content_type_unlike(qr/text/, 'different content type');

Opposite of C<content_type_like>.

=head2 C<delete_ok>

  $t = $t->delete_ok('/foo');
  $t = $t->delete_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<DELETE> request and check for transport errors, takes the exact
same arguments as L<Mojo::UserAgent/"delete">.

=head2 C<element_exists>

  $t = $t->element_exists('div.foo[x=y]');
  $t = $t->element_exists('html head title', 'has a title');

Checks for existence of the CSS3 selectors first matching XML/HTML element
with L<Mojo::DOM>.

=head2 C<element_exists_not>

  $t = $t->element_exists_not('div.foo[x=y]');
  $t = $t->element_exists_not('html head title', 'has no title');

Opposite of C<element_exists>.

=head2 C<finish_ok>

  $t = $t->finish_ok;
  $t = $t->finish_ok('finished successfully');

Finish C<WebSocket> connection.

=head2 C<get_ok>

  $t = $t->get_ok('/foo');
  $t = $t->get_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<GET> request and check for transport errors, takes the exact same
arguments as L<Mojo::UserAgent/"get">.

=head2 C<head_ok>

  $t = $t->head_ok('/foo');
  $t = $t->head_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<HEAD> request and check for transport errors, takes the exact same
arguments as L<Mojo::UserAgent/"head">.

=head2 C<header_is>

  $t = $t->header_is(Expect => 'fun');

Check response header for exact match.

=head2 C<header_isnt>

  $t = $t->header_isnt(Expect => 'fun');

Opposite of C<header_is>.

=head2 C<header_like>

  $t = $t->header_like(Expect => qr/fun/);
  $t = $t->header_like(Expect => qr/fun/, 'right header');

Check response header for similar match.

=head2 C<header_unlike>

  $t = $t->header_like(Expect => qr/fun/);
  $t = $t->header_like(Expect => qr/fun/, 'different header');

Opposite of C<header_like>.

=head2 C<json_content_is>

  $t = $t->json_content_is([1, 2, 3]);
  $t = $t->json_content_is([1, 2, 3], 'right content');
  $t = $t->json_content_is({foo => 'bar', baz => 23}, 'right content');

Check response content for JSON data.

=head2 C<json_is>

  $t = $t->json_is('/foo' => {bar => [1, 2, 3]});
  $t = $t->json_is('/foo/bar' => [1, 2, 3]);
  $t = $t->json_is('/foo/bar/1' => 2, 'right value');

Check the value extracted from JSON response using the given JSON Pointer with
L<Mojo::JSON::Pointer>.

=head2 C<json_has>

  $t = $t->json_has('/foo');
  $t = $t->json_has('/minibar', 'has a minibar');

Check if JSON response contains a value that can be identified using the given
JSON Pointer with L<Mojo::JSON::Pointer>.

=head2 C<json_hasnt>

  $t = $t->json_hasnt('/foo');
  $t = $t->json_hasnt('/minibar', 'no minibar');

Opposite of C<json_has>.

=head2 C<message_is>

  $t = $t->message_is('working!');
  $t = $t->message_is('working!', 'right message');

Check WebSocket message for exact match.

=head2 C<message_isnt>

  $t = $t->message_isnt('working!');
  $t = $t->message_isnt('working!', 'different message');

Opposite of C<message_is>.

=head2 C<message_like>

  $t = $t->message_like(qr/working!/);
  $t = $t->message_like(qr/working!/, 'right message');

Check WebSocket message for similar match.

=head2 C<message_unlike>

  $t = $t->message_unlike(qr/working!/);
  $t = $t->message_unlike(qr/working!/, 'different message');

Opposite of C<message_like>.

=head2 C<options_ok>

  $t = $t->options_ok('/foo');
  $t = $t->options_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<OPTIONS> request and check for transport errors, takes the exact
same arguments as L<Mojo::UserAgent/"options">.

=head2 C<patch_ok>

  $t = $t->patch_ok('/foo');
  $t = $t->patch_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<PATCH> request and check for transport errors, takes the exact
same arguments as L<Mojo::UserAgent/"patch">.

=head2 C<post_ok>

  $t = $t->post_ok('/foo');
  $t = $t->post_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<POST> request and check for transport errors, takes the exact same
arguments as L<Mojo::UserAgent/"post">.

=head2 C<post_form_ok>

  $t = $t->post_form_ok('/foo' => {a => 'b'});
  $t = $t->post_form_ok('/foo' => 'UTF-8' => {a => 'b'} => {DNT => 1});

Submit a C<POST> form and check for transport errors, takes the exact same
arguments as L<Mojo::UserAgent/"post_form">.

=head2 C<put_ok>

  $t = $t->put_ok('/foo');
  $t = $t->put_ok('/foo' => {DNT => 1} => 'Hi!');

Perform a C<PUT> request and check for transport errors, takes the exact same
arguments as L<Mojo::UserAgent/"put">.

=head2 C<reset_session>

  $t = $t->reset_session;

Reset user agent session.

=head2 C<send_ok>

  $t = $t->send_ok({binary => $bytes});
  $t = $t->send_ok({text   => $bytes});
  $t = $t->send_ok([$fin, $rsv1, $rsv2, $rsv3, $op, $payload]);
  $t = $t->send_ok('hello');
  $t = $t->send_ok('hello', 'sent successfully');

Send message or frame via WebSocket.

=head2 C<status_is>

  $t = $t->status_is(200);

Check response status for exact match.

=head2 C<status_isnt>

  $t = $t->status_isnt(200);

Opposite of C<status_is>.

=head2 C<text_is>

  $t = $t->text_is('div.foo[x=y]' => 'Hello!');
  $t = $t->text_is('html head title' => 'Hello!', 'right title');

Checks text content of the CSS3 selectors first matching XML/HTML element for
exact match with L<Mojo::DOM>.

=head2 C<text_isnt>

  $t = $t->text_isnt('div.foo[x=y]' => 'Hello!');
  $t = $t->text_isnt('html head title' => 'Hello!', 'different title');

Opposite of C<text_is>.

=head2 C<text_like>

  $t = $t->text_like('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_like('html head title' => qr/Hello/, 'right title');

Checks text content of the CSS3 selectors first matching XML/HTML element for
similar match with L<Mojo::DOM>.

=head2 C<text_unlike>

  $t = $t->text_unlike('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_unlike('html head title' => qr/Hello/, 'different title');

Opposite of C<text_like>.

=head2 C<websocket_ok>

  $t = $t->websocket_ok('/echo');
  $t = $t->websocket_ok('/echo' => {DNT => 1});

Open a C<WebSocket> connection with transparent handshake, takes the exact
same arguments as L<Mojo::UserAgent/"websocket">.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
