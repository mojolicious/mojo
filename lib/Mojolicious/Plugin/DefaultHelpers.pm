package Mojolicious::Plugin::DefaultHelpers;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::ByteStream;
use Mojo::Collection;
use Mojo::Date;
use Mojo::IOLoop;
use Mojo::Util qw(dumper sha1_sum steady_time);

sub register {
  my ($self, $app) = @_;

  # Controller alias helpers
  for my $name (qw(app flash param stash session url_for validation)) {
    $app->helper($name => sub { shift->$name(@_) });
  }

  # Stash key shortcuts (should not generate log messages)
  for my $name (qw(extends layout title)) {
    $app->helper(
      $name => sub {
        my $c     = shift;
        my $stash = $c->stash;
        $stash->{$name} = shift if @_;
        $c->stash(@_) if @_;
        return $stash->{$name};
      }
    );
  }

  $app->helper($_ => $self->can("_$_"))
    for qw(accepts content content_for csrf_token current_route delay),
    qw(inactivity_timeout is_fresh url_with);
  $app->helper(b => sub { shift; Mojo::ByteStream->new(@_) });
  $app->helper(c => sub { shift; Mojo::Collection->new(@_) });
  $app->helper(config        => sub { shift->app->config(@_) });
  $app->helper(time_in_words => sub { Mojo::Date->new($_[1])->to_words });
  $app->helper(dumper        => sub { shift; dumper(@_) });
  $app->helper(include       => sub { shift->render_to_string(@_) });
  $app->helper(ua            => sub { shift->app->ua });
}

sub _accepts {
  my $c = shift;
  return $c->app->renderer->accepts($c, @_);
}

sub _content {
  my ($c, $name, $content) = @_;
  $name ||= 'content';

  # Set (first come)
  my $hash = $c->stash->{'mojo.content'} ||= {};
  $hash->{$name} //= ref $content eq 'CODE' ? $content->() : $content
    if defined $content;

  # Get
  return Mojo::ByteStream->new($hash->{$name} // '');
}

sub _content_for {
  my ($c, $name, $content) = @_;
  return _content($c, $name) unless defined $content;
  my $hash = $c->stash->{'mojo.content'} ||= {};
  return $hash->{$name} .= ref $content eq 'CODE' ? $content->() : $content;
}

sub _csrf_token {
  my $c = shift;
  $c->session->{csrf_token}
    ||= sha1_sum($c->app->secrets->[0] . steady_time . rand 999);
}

sub _current_route {
  return '' unless my $endpoint = shift->match->endpoint;
  return $endpoint->name unless @_;
  return $endpoint->name eq shift;
}

sub _delay {
  my $c     = shift;
  my $tx    = $c->render_later->tx;
  my $delay = Mojo::IOLoop->delay(@_);
  $delay->catch(sub { $c->render_exception(pop) and undef $tx })->wait;
}

sub _inactivity_timeout {
  return unless my $stream = Mojo::IOLoop->stream(shift->tx->connection // '');
  $stream->timeout(shift);
}

sub _is_fresh {
  my ($c, %options) = @_;
  return $c->app->static->is_fresh($c, \%options);
}

sub _url_with {
  my $c = shift;
  return $c->url_for(@_)->query($c->req->url->query->clone);
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Plugin::DefaultHelpers - Default helpers plugin

=head1 SYNOPSIS

  # Mojolicious
  $self->plugin('DefaultHelpers');

  # Mojolicious::Lite
  plugin 'DefaultHelpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::DefaultHelpers> is a collection of renderer helpers for
L<Mojolicious>.

This is a core plugin, that means it is always enabled and its code a good
example for learning to build new plugins, you're welcome to fork it.

See L<Mojolicious::Plugins/"PLUGINS"> for a list of plugins that are available
by default.

=head1 HELPERS

L<Mojolicious::Plugin::DefaultHelpers> implements the following helpers.

=head2 accepts

  my $formats = $c->accepts;
  my $format  = $c->accepts('html', 'json', 'txt');

Select best possible representation for resource from C<Accept> request
header, C<format> stash value or C<format> C<GET>/C<POST> parameter with
L<Mojolicious::Renderer/"accepts">, defaults to returning the first extension
if no preference could be detected.

  # Check if JSON is acceptable
  $c->render(json => {hello => 'world'}) if $c->accepts('json');

  # Check if JSON was specifically requested
  $c->render(json => {hello => 'world'}) if $c->accepts('', 'json');

  # Unsupported representation
  $c->render(data => '', status => 204)
    unless my $format = $c->accepts('html', 'json');

  # Detected representations to select from
  my @formats = @{$c->accepts};

=head2 app

  %= app->secrets->[0]

Alias for L<Mojolicious::Controller/"app">.

=head2 b

  %= b('test 123')->b64_encode

Turn string into a L<Mojo::ByteStream> object.

=head2 c

  %= c(qw(a b c))->shuffle->join

Turn list into a L<Mojo::Collection> object.

=head2 config

  %= config 'something'

Alias for L<Mojo/"config">.

=head2 content

  %= content foo => begin
    test
  % end
  %= content bar => 'Hello World!'
  %= content 'foo'
  %= content 'bar'
  %= content

Store partial rendered content in named buffer and retrieve it, defaults to
retrieving the named buffer C<content>, which is commonly used for the
renderers C<layout> and C<extends> features. Note that new content will be
ignored if the named buffer is already in use.

=head2 content_for

  % content_for foo => begin
    test
  % end
  %= content_for 'foo'

Append partial rendered content to named buffer and retrieve it. Note that
named buffers are shared with the L</"content"> helper.

  % content_for message => begin
    Hello
  % end
  % content_for message => begin
    world!
  % end
  %= content_for 'message'

=head2 csrf_token

  %= csrf_token

Get CSRF token from L</"session">, and generate one if none exists.

=head2 current_route

  % if (current_route 'login') {
    Welcome to Mojolicious!
  % }
  %= current_route

Check or get name of current route.

=head2 delay

  $c->delay(sub {...}, sub {...});

Disable automatic rendering and use L<Mojo::IOLoop/"delay"> to manage
callbacks and control the flow of events, which can help you avoid deep nested
closures and memory leaks that often result from continuation-passing style.
Calls L<Mojolicious::Controller/"render_exception"> if an error occured in one
of the steps, breaking the chain.

  # Longer version
  $c->render_later;
  my $delay = Mojo::IOLoop->delay(sub {...}, sub {...});
  $delay->catch(sub { $c->render_exception(pop) })->wait;

=head2 dumper

  %= dumper {some => 'data'}

Dump a Perl data structure with L<Mojo::Util/"dumper">.

=head2 extends

  % extends 'blue';
  % extends 'blue', title => 'Blue!';

Set C<extends> stash value, all additional pairs get merged into the
L</"stash">.

=head2 flash

  %= flash 'foo'

Alias for L<Mojolicious::Controller/"flash">.

=head2 inactivity_timeout

  $c->inactivity_timeout(3600);

Use L<Mojo::IOLoop/"stream"> to find the current connection and increase
timeout if possible.

  # Longer version
  Mojo::IOLoop->stream($c->tx->connection)->timeout(3600);

=head2 include

  %= include 'menubar'
  %= include 'menubar', format => 'txt'

Alias for C<Mojolicious::Controller/"render_to_string">.

=head2 is_fresh

  my $bool = $c->is_fresh;
  my $bool = $c->is_fresh(etag => 'abc');
  my $bool = $c->is_fresh(last_modified => $epoch);

Check freshness of request by comparing the C<If-None-Match> and
C<If-Modified-Since> request headers to the C<ETag> and C<Last-Modified>
response headers with L<Mojolicious::Static/"is_fresh">.

  # Add ETag header and check freshness before rendering
  $c->is_fresh(etag => 'abc')
    ? $c->rendered(304)
    : $c->render(text => 'I ♥ Mojolicious!');

=head2 layout

  % layout 'green';
  % layout 'green', title => 'Green!';

Set C<layout> stash value, all additional pairs get merged into the
L</"stash">.

=head2 param

  %= param 'foo'

Alias for L<Mojolicious::Controller/"param">.

=head2 session

  %= session 'foo'

Alias for L<Mojolicious::Controller/"session">.

=head2 stash

  %= stash 'foo'
  % stash foo => 'bar';

Alias for L<Mojolicious::Controller/"stash">.

  %= stash('name') // 'Somebody'

=head2 time_in_words

  %= time_in_words 784111777

Report the approximate distance in time from now with
L<Mojo::Date/"to_words">.

=head2 title

  % title 'Welcome!';
  % title 'Welcome!', foo => 'bar';
  %= title

Set C<title> stash value, all additional pairs get merged into the
L</"stash">.

=head2 ua

  %= ua->get('mojolicio.us')->res->dom->at('title')->text

Alias for L<Mojo/"ua">.

=head2 url_for

  %= url_for 'named', controller => 'bar', action => 'baz'

Alias for L<Mojolicious::Controller/"url_for">.

=head2 url_with

  %= url_with 'named', controller => 'bar', action => 'baz'

Does the same as L</"url_for">, but inherits query parameters from the current
request.

  %= url_with->query([page => 2])

=head2 validation

  %= validation->param('foo')

Alias for L<Mojolicious::Controller/"validation">.

=head1 METHODS

L<Mojolicious::Plugin::DefaultHelpers> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new);

Register helpers in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
