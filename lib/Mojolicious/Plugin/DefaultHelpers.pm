package Mojolicious::Plugin::DefaultHelpers;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::Asset::File;
use Mojo::ByteStream;
use Mojo::Collection;
use Mojo::Exception;
use Mojo::IOLoop;
use Mojo::Util qw(deprecated dumper hmac_sha1_sum steady_time);
use Time::HiRes qw(gettimeofday tv_interval);
use Scalar::Util 'blessed';

sub register {
  my ($self, $app) = @_;

  # Controller alias helpers
  for my $name (qw(app flash param stash session url_for validation)) {
    $app->helper($name => sub { shift->$name(@_) });
  }

  # Stash key shortcuts (should not generate log messages)
  for my $name (qw(extends layout title)) {
    $app->helper($name => sub { shift->stash($name, @_) });
  }

  $app->helper(accepts => sub { $_[0]->app->renderer->accepts(@_) });
  $app->helper(b       => sub { shift; Mojo::ByteStream->new(@_) });
  $app->helper(c       => sub { shift; Mojo::Collection->new(@_) });
  $app->helper(config  => sub { shift->app->config(@_) });

  $app->helper(content      => sub { _content(0, 0, @_) });
  $app->helper(content_for  => sub { _content(1, 0, @_) });
  $app->helper(content_with => sub { _content(0, 1, @_) });

  # DEPRECATED!
  $app->helper(
    delay => sub {
      deprecated 'delay helper is DEPRECATED';
      my $c  = shift;
      my $tx = $c->render_later->tx;
      Mojo::IOLoop->delay(@_)
        ->catch(sub { $c->helpers->reply->exception(pop) and undef $tx })->wait;
    }
  );

  $app->helper($_ => $self->can("_$_"))
    for qw(csrf_token current_route inactivity_timeout is_fresh url_with);

  $app->helper(dumper => sub { shift; dumper @_ });
  $app->helper(include => sub { shift->render_to_string(@_) });

  $app->helper("reply.$_" => $self->can("_$_")) for qw(asset file static);

  $app->helper('reply.exception' => sub { _development('exception', @_) });
  $app->helper('reply.not_found' => sub { _development('not_found', @_) });

  $app->helper('timing.begin'         => \&_timing_begin);
  $app->helper('timing.elapsed'       => \&_timing_elapsed);
  $app->helper('timing.rps'           => \&_timing_rps);
  $app->helper('timing.server_timing' => \&_timing_server_timing);

  $app->helper(ua => sub { shift->app->ua });
}

sub _asset {
  my $c = shift;
  $c->app->static->serve_asset($c, @_);
  $c->rendered;
}

sub _block { ref $_[0] eq 'CODE' ? $_[0]() : $_[0] }

sub _content {
  my ($append, $replace, $c, $name, $content) = @_;
  $name ||= 'content';

  my $hash = $c->stash->{'mojo.content'} ||= {};
  if (defined $content) {
    if ($append) { $hash->{$name} .= _block($content) }
    if ($replace) { $hash->{$name} = _block($content) }
    else          { $hash->{$name} //= _block($content) }
  }

  return Mojo::ByteStream->new($hash->{$name} // '');
}

sub _csrf_token {
  my $c = shift;
  return $c->session->{csrf_token}
    ||= hmac_sha1_sum($$ . steady_time . rand, $c->app->secrets->[0]);
}

sub _current_route {
  return '' unless my $route = shift->match->endpoint;
  return @_ ? $route->name eq shift : $route->name;
}

sub _development {
  my ($page, $c, $e) = @_;

  my $app = $c->app;
  $app->log->error($e = _exception($e) ? $e : Mojo::Exception->new($e)->inspect)
    if $page eq 'exception';

  # Filtered stash snapshot
  my $stash = $c->stash;
  %{$stash->{snapshot} = {}} = map { $_ => $stash->{$_} }
    grep { !/^mojo\./ and defined $stash->{$_} } keys %$stash;
  $stash->{exception} = $page eq 'exception' ? $e : undef;

  # Render with fallbacks
  my $mode    = $app->mode;
  my $options = {
    format   => $stash->{format} || $app->renderer->default_format,
    handler  => undef,
    status   => $page eq 'exception' ? 500 : 404,
    template => "$page.$mode"
  };
  my $bundled = 'mojo/' . ($mode eq 'development' ? 'debug' : $page);
  return $c if _fallbacks($c, $options, $page, $bundled);
  _fallbacks($c, {%$options, format => 'html'}, $page, $bundled);
  return $c;
}

sub _exception { blessed $_[0] && $_[0]->isa('Mojo::Exception') }

sub _fallbacks {
  my ($c, $options, $template, $bundled) = @_;

  # Mode specific template
  return 1 if $c->render_maybe(%$options);

  # Normal template
  return 1 if $c->render_maybe(%$options, template => $template);

  # Inline template
  my $stash = $c->stash;
  return undef unless $options->{format} eq 'html';
  delete @$stash{qw(extends layout)};
  return $c->render_maybe($bundled, %$options, handler => 'ep');
}

sub _file { _asset(shift, Mojo::Asset::File->new(path => shift)) }

sub _inactivity_timeout {
  my ($c, $timeout) = @_;
  my $stream = Mojo::IOLoop->stream($c->tx->connection // '');
  $stream->timeout($timeout) if $stream;
  return $c;
}

sub _is_fresh {
  my ($c, %options) = @_;
  return $c->app->static->is_fresh($c, \%options);
}

sub _static {
  my ($c, $file) = @_;
  return !!$c->rendered if $c->app->static->serve($c, $file);
  $c->app->log->debug(qq{Static file "$file" not found});
  return !$c->helpers->reply->not_found;
}

sub _timing_begin { shift->stash->{'mojo.timing'}{shift()} = [gettimeofday] }

sub _timing_elapsed {
  my ($c, $name) = @_;
  return undef unless my $started = $c->stash->{'mojo.timing'}{$name};
  return tv_interval($started, [gettimeofday()]);
}

sub _timing_rps { $_[1] == 0 ? undef : sprintf '%.3f', 1 / $_[1] }

sub _timing_server_timing {
  my ($c, $metric, $desc, $dur) = @_;
  my $value = $metric;
  $value .= qq{;desc="$desc"} if defined $desc;
  $value .= ";dur=$dur"       if defined $dur;
  $c->res->headers->append('Server-Timing' => $value);
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
  $app->plugin('DefaultHelpers');

  # Mojolicious::Lite
  plugin 'DefaultHelpers';

=head1 DESCRIPTION

L<Mojolicious::Plugin::DefaultHelpers> is a collection of helpers for
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

Select best possible representation for resource from C<format> C<GET>/C<POST>
parameter, C<format> stash value or C<Accept> request header with
L<Mojolicious::Renderer/"accepts">, defaults to returning the first extension if
no preference could be detected.

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

  %= b('Joel is a slug')->slugify

Turn string into a L<Mojo::ByteStream> object.

=head2 c

  %= c('a', 'b', 'c')->shuffle->join

Turn list into a L<Mojo::Collection> object.

=head2 config

  %= config 'something'

Alias for L<Mojolicious/"config">.

=head2 content

  %= content foo => begin
    test
  % end
  %= content bar => 'Hello World!'
  %= content 'foo'
  %= content 'bar'
  %= content

Store partial rendered content in a named buffer and retrieve it later,
defaults to retrieving the named buffer C<content>, which is used by the
renderer for the C<layout> and C<extends> features. New content will be ignored
if the named buffer is already in use.

=head2 content_for

  % content_for foo => begin
    test
  % end
  %= content_for 'foo'

Same as L</"content">, but appends content to named buffers if they are already
in use.

  % content_for message => begin
    Hello
  % end
  % content_for message => begin
    world!
  % end
  %= content 'message'

=head2 content_with

  % content_with foo => begin
    test
  % end
  %= content_with 'foo'

Same as L</"content">, but replaces content of named buffers if they are
already in use.

  % content message => begin
    world!
  % end
  % content_with message => begin
    Hello <%= content 'message' %>
  % end
  %= content 'message'

=head2 csrf_token

  %= csrf_token

Get CSRF token from L</"session">, and generate one if none exists.

=head2 current_route

  % if (current_route 'login') {
    Welcome to Mojolicious!
  % }
  %= current_route

Check or get name of current route.

=head2 dumper

  %= dumper {some => 'data'}

Dump a Perl data structure with L<Mojo::Util/"dumper">, very useful for
debugging.

=head2 extends

  % extends 'blue';
  % extends 'blue', title => 'Blue!';

Set C<extends> stash value, all additional key/value pairs get merged into the
L</"stash">.

=head2 flash

  %= flash 'foo'

Alias for L<Mojolicious::Controller/"flash">.

=head2 inactivity_timeout

  $c = $c->inactivity_timeout(3600);

Use L<Mojo::IOLoop/"stream"> to find the current connection and increase
timeout if possible.

  # Longer version
  Mojo::IOLoop->stream($c->tx->connection)->timeout(3600);

=head2 include

  %= include 'menubar'
  %= include 'menubar', format => 'txt'

Alias for L<Mojolicious::Controller/"render_to_string">.

=head2 is_fresh

  my $bool = $c->is_fresh;
  my $bool = $c->is_fresh(etag => 'abc');
  my $bool = $c->is_fresh(last_modified => $epoch);

Check freshness of request by comparing the C<If-None-Match> and
C<If-Modified-Since> request headers to the C<ETag> and C<Last-Modified>
response headers with L<Mojolicious::Static/"is_fresh">.

  # Add ETag/Last-Modified headers and check freshness before rendering
  $c->is_fresh(etag => 'abc', last_modified => 1424985708)
    ? $c->rendered(304)
    : $c->render(text => 'I ♥ Mojolicious!');

=head2 layout

  % layout 'green';
  % layout 'green', title => 'Green!';

Set C<layout> stash value, all additional key/value pairs get merged into the
L</"stash">.

=head2 param

  %= param 'foo'

Alias for L<Mojolicious::Controller/"param">.

=head2 reply->asset

  $c->reply->asset(Mojo::Asset::File->new);

Reply with a L<Mojo::Asset::File> or L<Mojo::Asset::Memory> object using
L<Mojolicious::Static/"serve_asset">, and perform content negotiation with
C<Range>, C<If-Modified-Since> and C<If-None-Match> headers.

  # Serve asset with custom modification time
  my $asset = Mojo::Asset::Memory->new;
  $asset->add_chunk('Hello World!')->mtime(784111777);
  $c->res->headers->content_type('text/plain');
  $c->reply->asset($asset);

  # Serve static file if it exists
  if (my $asset = $c->app->static->file('images/logo.png')) {
    $c->res->headers->content_type('image/png');
    $c->reply->asset($asset);
  }

=head2 reply->exception

  $c = $c->reply->exception('Oops!');
  $c = $c->reply->exception(Mojo::Exception->new);

Render the exception template C<exception.$mode.$format.*> or
C<exception.$format.*> and set the response status code to C<500>. Also sets
the stash values C<exception> to a L<Mojo::Exception> object and C<snapshot> to
a copy of the L</"stash"> for use in the templates.

=head2 reply->file

  $c->reply->file('/etc/passwd');

Reply with a static file from an absolute path anywhere on the file system using
L<Mojolicious/"static">.

  # Longer version
  $c->reply->asset(Mojo::Asset::File->new(path => '/etc/passwd'));

  # Serve file from an absolute path with a custom content type
  $c->res->headers->content_type('application/myapp');
  $c->reply->file('/home/sri/foo.txt');

  # Serve file from a secret application directory
  $c->reply->file($c->app->home->child('secret', 'file.txt'));

=head2 reply->not_found

  $c = $c->reply->not_found;

Render the not found template C<not_found.$mode.$format.*> or
C<not_found.$format.*> and set the response status code to C<404>. Also sets
the stash value C<snapshot> to a copy of the L</"stash"> for use in the
templates.

=head2 reply->static

  my $bool = $c->reply->static('images/logo.png');
  my $bool = $c->reply->static('../lib/MyApp.pm');

Reply with a static file using L<Mojolicious/"static">, usually from the
C<public> directories or C<DATA> sections of your application. Note that this
helper uses a relative path, but does not protect from traversing to parent
directories.

  # Serve file from a relative path with a custom content type
  $c->res->headers->content_type('application/myapp');
  $c->reply->static('foo.txt');

=head2 session

  %= session 'foo'

Alias for L<Mojolicious::Controller/"session">.

=head2 stash

  %= stash 'foo'
  % stash foo => 'bar';

Alias for L<Mojolicious::Controller/"stash">.

  %= stash('name') // 'Somebody'

=head2 timing->begin

  $c->timing->begin('foo');

Create named timestamp for L<"timing-E<gt>elapsed">. Note that this helper is
EXPERIMENTAL and might change without warning!

=head2 timing->elapsed

  my $elapsed = $c->timing->elapsed('foo');

Return fractional amount of time in seconds since named timstamp has been
created with L</"timing-E<gt>begin"> or C<undef> if no such timestamp exists.
Note that this helper is EXPERIMENTAL and might change without warning!

  # Log timing information
  $c->timing->begin('database_stuff');
  ...
  my $elapsed = $c->timing->elapsed('database_stuff');
  $c->app->log->debug("Database stuff took $elapsed seconds");

=head2 timing->rps

  my $rps = $c->timing->rps('0.001');

Return fractional number of requests that could be performed in one second if
every singe one took the given amount of time in seconds or C<undef> if the
number is too low. Note that this helper is EXPERIMENTAL and might change
without warning!

  # Log more timing information
  $c->timing->begin('web_stuff');
  ...
  my $elapsed = $c->timing->elapsed('web_stuff');
  my $rps     = $c->timing->rps($elapsed);
  $c->app->log->debug("Web stuff took $elapsed seconds ($rps per second)");

=head2 timing->server_timing

  $c->timing->server_timing('metric');
  $c->timing->server_timing('metric', 'Some Description');
  $c->timing->server_timing('metric', 'Some Description', '0.001');

Create C<Server-Timing> header with optional description and duration. Note that
this helper is EXPERIMENTAL and might change without warning!

  # "Server-Timing: miss"
  $c->timing->server_timing('miss');

  # "Server-Timing: dc;desc=atl"
  $c->timing->server_timing('dc', 'atl');

  # "Server-Timing: db;desc=Database;dur=0.0001"
  $c->timing->begin('database_stuff');
  ...
  my $elapsed = $c->timing->elapsed('database_stuff');
  $c->timing->server_timing('db', 'Database', $elapsed);

  # "Server-Timing: miss, dc;desc=atl"
  $c->timing->server_timing('miss');
  $c->timing->server_timing('dc', 'atl');

=head2 title

  %= title
  % title 'Welcome!';
  % title 'Welcome!', foo => 'bar';

Get or set C<title> stash value, all additional key/value pairs get merged into
the L</"stash">.

=head2 ua

  %= ua->get('mojolicious.org')->result->dom->at('title')->text

Alias for L<Mojolicious/"ua">.

=head2 url_for

  %= url_for 'named', controller => 'bar', action => 'baz'

Alias for L<Mojolicious::Controller/"url_for">.

  %= url_for('/index.html')->query(foo => 'bar')

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

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
