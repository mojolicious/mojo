package Test::Mojo;
use Mojo::Base -base;

use Mojo::IOLoop;
use Mojo::Message::Response;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::Util 'decode';

require Test::More;

has app => sub { return $ENV{MOJO_APP} if ref $ENV{MOJO_APP} };
has ua => sub {
  Mojo::UserAgent->new->ioloop(Mojo::IOLoop->singleton)->app(shift->app);
};
has max_redirects => 0;
has 'tx';

# Silent or loud tests
$ENV{MOJO_LOG_LEVEL} ||= $ENV{HARNESS_IS_VERBOSE} ? 'debug' : 'fatal';

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
sub client {
  warn <<EOF;
Test::Mojo->client is DEPRECATED in favor of Test::Mojo->ua!!!
EOF
  return shift->ua;
}

sub build_url {
  Mojo::URL->new('http://localhost:' . shift->ua->test_server . '/');
}

# "Ooh, a graduate student huh?
#  How come you guys can go to the moon but can't make my shoes smell good?"
sub content_is {
  my ($self, $value, $desc) = @_;

  $desc ||= 'exact match for content';
  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is($self->_get_content($tx), $value, $desc);

  return $self;
}

sub content_like {
  my ($self, $regex, $desc) = @_;

  $desc ||= 'content is similar';
  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like($self->_get_content($tx), $regex, $desc);

  return $self;
}

# "Marge, I can't wear a pink shirt to work.
#  Everybody wears white shirts.
#  I'm not popular enough to be different."
sub content_type_is {
  my ($self, $type) = @_;
  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is($tx->res->headers->content_type,
    $type, "Content-Type: $type");
  return $self;
}

sub content_type_like {
  my ($self, $regex, $desc) = @_;

  $desc ||= 'Content-Type is similar';
  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like($tx->res->headers->content_type, $regex, $desc);

  return $self;
}

# "A job's a job. I mean, take me.
#  If my plant pollutes the water and poisons the town,
#  by your logic, that would make me a criminal."
sub delete_ok { shift->_request_ok('delete', @_) }

sub element_exists {
  my ($self, $selector, $desc) = @_;
  $desc ||= $selector;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok($self->tx->res->dom->at($selector), $desc);
  return $self;
}

sub get_ok  { shift->_request_ok('get',  @_) }
sub head_ok { shift->_request_ok('head', @_) }

sub header_is {
  my ($self, $name, $value) = @_;

  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is(scalar $tx->res->headers->header($name),
    $value, "$name: " . ($value ? $value : ''));

  return $self;
}

sub header_like {
  my ($self, $name, $regex, $desc) = @_;

  $desc ||= "$name is similar";
  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like(scalar $tx->res->headers->header($name), $regex, $desc);

  return $self;
}

sub json_content_is {
  my ($self, $struct, $desc) = @_;

  $desc ||= 'exact match for JSON structure';
  my $tx = $self->tx;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is_deeply($tx->res->json, $struct, $desc);

  return $self;
}

# "God bless those pagans."
sub post_ok { shift->_request_ok('post', @_) }

# "Hey, I asked for ketchup! I'm eatin' salad here!"
sub post_form_ok {
  my $self = shift;
  my $url  = $_[0];

  my $desc = "post $url";
  utf8::encode $desc;
  my $ua = $self->ua;
  $ua->app($self->app);
  $ua->max_redirects($self->max_redirects);
  $self->tx($ua->post_form(@_));
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::ok($self->tx->is_done, $desc);

  return $self;
}

# "WHO IS FONZY!?! Don't they teach you anything at school?"
sub put_ok { shift->_request_ok('put', @_) }

sub reset_session {
  my $self = shift;
  $self->ua->cookie_jar->empty;
  $self->ua->max_redirects($self->max_redirects);
  $self->tx(undef);
  return $self;
}

# "Internet! Is that thing still around?"
sub status_is {
  my ($self, $status) = @_;

  my $message =
    Mojo::Message::Response->new(code => $status)->default_message;
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is($self->tx->res->code, $status, "$status $message");

  return $self;
}

sub text_is {
  my ($self, $selector, $value, $desc) = @_;

  $desc ||= $selector;
  my $text;
  if (my $element = $self->tx->res->dom->at($selector)) {
    $text = $element->text;
  }
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::is($text, $value, $desc);

  return $self;
}

# "Hello, my name is Barney Gumble, and I'm an alcoholic.
#  Mr Gumble, this is a girl scouts meeting.
#  Is it, or is it you girls can't admit that you have a problem?"
sub text_like {
  my ($self, $selector, $regex, $desc) = @_;

  $desc ||= $selector;
  my $text;
  if (my $element = $self->tx->res->dom->at($selector)) {
    $text = $element->text;
  }
  local $Test::Builder::Level = $Test::Builder::Level + 1;
  Test::More::like($text, $regex, $desc);

  return $self;
}

sub _get_content {
  my ($self, $tx) = @_;

  # Charset
  my $charset;
  ($tx->res->headers->content_type || '') =~ /charset=\"?([^"\s]+)\"?/
    and $charset = $1;

  # Content
  my $content = $tx->res->body;
  decode $charset, $content if $charset;
  return $content;
}

# "Are you sure this is the Sci-Fi Convention? It's full of nerds!"
sub _request_ok {
  my ($self, $method, $url, $headers, $body) = @_;

  my $desc = "$method $url";
  utf8::encode $desc;

  # Body without headers
  $body = $headers if !ref $headers && @_ > 3;
  $headers = {} if !ref $headers;

  my $ua = $self->ua;
  $ua->app($self->app);
  $ua->max_redirects($self->max_redirects);
  $self->tx($ua->$method($url, %$headers, $body));
  local $Test::Builder::Level = $Test::Builder::Level + 2;
  Test::More::ok($self->tx->is_done, $desc);

  return $self;
}

1;
__END__

=head1 NAME

Test::Mojo - Testing Mojo!

=head1 SYNOPSIS

  use Test::More tests => 10;
  use Test::Mojo;

  my $t = Test::Mojo->new(app => 'MyApp');

  $t->get_ok('/welcome')
    ->status_is(200)
    ->content_like(qr/Hello!/, 'welcome message!');

  $t->post_form_ok('/search', {title => 'Perl', author => 'taro'})
    ->status_is(200)
    ->content_like(qr/Perl.+taro/);

  $t->delete_ok('/something')
    ->status_is(200)
    ->header_is('X-Powered-By' => 'Mojolicious (Perl)')
    ->content_is('Hello world!');

=head1 DESCRIPTION

L<Test::Mojo> is a collection of testing helpers for everyone developing
L<Mojo> and L<Mojolicious> applications.

=head1 ATTRIBUTES

L<Test::Mojo> implements the following attributes.

=head2 C<app>

  my $app = $t->app;
  $t      = $t->app(MyApp->new);

Application to be tested.

=head2 C<tx>

  my $tx = $t->tx;
  $t     = $t->tx(Mojo::Transaction::HTTP->new);

Current transaction, usually a L<Mojo::Transaction::HTTP> object.

=head2 C<ua>

  my $ua = $t->ua;
  $t     = $t->ua(Mojo::UserAgent->new);

User agent used for testing.

=head2 C<max_redirects>

  my $max_redirects = $t->max_redirects;
  $t                = $t->max_redirects(3);

Maximum number of redirects, defaults to C<0>.

=head1 METHODS

L<Test::Mojo> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<build_url>

  my $url = $t->build_url;

Build absolute L<Mojo::URL> object for test server.
Note that this method is EXPERIMENTAL and might change without warning!

  $t->get_ok($t->build_url->userinfo('sri:secr3t')->path('/protected'));

=head2 C<content_is>

  $t = $t->content_is('working!');
  $t = $t->content_is('working!', 'right content!');

Check response content for exact match.

=head2 C<content_like>

  $t = $t->content_like(qr/working!/);
  $t = $t->content_like(qr/working!/, 'right content!');

Check response content for similar match.

=head2 C<content_type_is>

  $t = $t->content_type_is('text/html');

Check response C<Content-Type> header for exact match.

=head2 C<content_type_like>

  $t = $t->content_type_like(qr/text/);
  $t = $t->content_type_like(qr/text/, 'right content type!');

Check response C<Content-Type> header for similar match.

=head2 C<delete_ok>

  $t = $t->delete_ok('/foo');
  $t = $t->delete_ok('/foo', {Accept => '*/*'});
  $t = $t->delete_ok('/foo', 'Hi!');
  $t = $t->delete_ok('/foo', {Accept => '*/*'}, 'Hi!');

Perform a C<DELETE> request and check for success.

=head2 C<element_exists>

  $t = $t->element_exists('div.foo[x=y]');
  $t = $t->element_exists('html head title', 'has a title');

Checks for existence of the CSS3 selectors first matching XML/HTML element
with L<Mojo::DOM>.

=head2 C<get_ok>

  $t = $t->get_ok('/foo');
  $t = $t->get_ok('/foo', {Accept => '*/*'});
  $t = $t->get_ok('/foo', 'Hi!');
  $t = $t->get_ok('/foo', {Accept => '*/*'}, 'Hi!');

Perform a C<GET> request and check for success.

=head2 C<head_ok>

  $t = $t->head_ok('/foo');
  $t = $t->head_ok('/foo', {Accept => '*/*'});
  $t = $t->head_ok('/foo', 'Hi!');
  $t = $t->head_ok('/foo', {Accept => '*/*'}, 'Hi!');

Perform a C<HEAD> request and check for success.

=head2 C<header_is>

  $t = $t->header_is(Expect => 'fun');

Check response header for exact match.

=head2 C<header_like>

  $t = $t->header_like(Expect => qr/fun/);
  $t = $t->header_like(Expect => qr/fun/, 'right header!');

Check response header for similar match.

=head2 C<json_content_is>

  $t = $t->json_content_is([1, 2, 3]);
  $t = $t->json_content_is([1, 2, 3], 'right content!');
  $t = $t->json_content_is({foo => 'bar', baz => 23}, 'right content!');

Check response content for JSON data.

=head2 C<post_ok>

  $t = $t->post_ok('/foo');
  $t = $t->post_ok('/foo', {Accept => '*/*'});
  $t = $t->post_ok('/foo', 'Hi!');
  $t = $t->post_ok('/foo', {Accept => '*/*'}, 'Hi!');
  $t = $t->post_ok('/foo', 'Hi!', 'request worked!');

Perform a C<POST> request and check for success.

=head2 C<post_form_ok>

  $t = $t->post_form_ok('/foo' => {test => 123});
  $t = $t->post_form_ok('/foo' => 'UTF-8' => {test => 123});
  $t = $t->post_form_ok('/foo', {test => 123}, {Accept => '*/*'});
  $t = $t->post_form_ok('/foo', 'UTF-8', {test => 123}, {Accept => '*/*'});
  $t = $t->post_form_ok('/foo', {test => 123}, 'Hi!');
  $t = $t->post_form_ok('/foo', 'UTF-8', {test => 123}, 'Hi!');
  $t = $t->post_form_ok('/foo', {test => 123}, {Accept => '*/*'}, 'Hi!');
  $t = $t->post_form_ok(
    '/foo',
    'UTF-8',
    {test   => 123},
    {Accept => '*/*'},
    'Hi!'
  );

Submit a C<POST> form and check for success.

=head2 C<put_ok>

  $t = $t->put_ok('/foo');
  $t = $t->put_ok('/foo', {Accept => '*/*'});
  $t = $t->put_ok('/foo', 'Hi!');
  $t = $t->put_ok('/foo', {Accept => '*/*'}, 'Hi!');

Perform a C<PUT> request and check for success.

=head2 C<reset_session>

  $t = $t->reset_session;

Reset user agent session.

=head2 C<status_is>

  $t = $t->status_is(200);

Check response status for exact match.

=head2 C<text_is>

  $t = $t->text_is('div.foo[x=y]' => 'Hello!');
  $t = $t->text_is('html head title' => 'Hello!', 'right title');

Checks text content of the CSS3 selectors first matching XML/HTML element for
exact match with L<Mojo::DOM>.

=head2 C<text_like>

  $t = $t->text_like('div.foo[x=y]' => qr/Hello/);
  $t = $t->text_like('html head title' => qr/Hello/, 'right title');

Checks text content of the CSS3 selectors first matching XML/HTML element for
similar match with L<Mojo::DOM>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
