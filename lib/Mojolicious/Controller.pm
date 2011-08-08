package Mojolicious::Controller;
use Mojo::Base -base;

use Mojo::Asset::File;
use Mojo::ByteStream;
use Mojo::Cookie::Response;
use Mojo::Exception;
use Mojo::Transaction::HTTP;
use Mojo::URL;
use Mojo::Util;

require Carp;
require File::Basename;
require File::Spec;

# "Scalpel... blood bucket... priest."
has [qw/app match/];
has tx => sub { Mojo::Transaction::HTTP->new };

# Template directory
my $T = File::Spec->catdir(File::Basename::dirname(__FILE__), 'templates');

# Exception template
our $EXCEPTION =
  Mojo::Asset::File->new(path => File::Spec->catfile($T, 'exception.html.ep'))
  ->slurp;

# Exception template (development)
our $DEVELOPMENT_EXCEPTION =
  Mojo::Asset::File->new(
  path => File::Spec->catfile($T, 'exception.development.html.ep'))->slurp;

# Not found template
our $NOT_FOUND =
  Mojo::Asset::File->new(path => File::Spec->catfile($T, 'not_found.html.ep'))
  ->slurp;

# Not found template (development)
our $DEVELOPMENT_NOT_FOUND =
  Mojo::Asset::File->new(
  path => File::Spec->catfile($T, 'not_found.development.html.ep'))->slurp;

# Reserved stash values
my @RESERVED = (
  qw/action app cb class controller data exception extends format handler/,
  qw/json layout method namespace partial path status template text/
);
my %RESERVED;
$RESERVED{$_}++ for @RESERVED;

# "Is all the work done by the children?
#  No, not the whipping."
sub AUTOLOAD {
  my $self = shift;

  # Method
  my ($package, $method) = our $AUTOLOAD =~ /^([\w\:]+)\:\:(\w+)$/;

  # Call helper
  Carp::croak(qq/Can't locate object method "$method" via package "$package"/)
    unless my $helper = $self->app->renderer->helpers->{$method};
  return $self->$helper(@_);
}

sub DESTROY { }

# "For the last time, I don't like lilacs!
#  Your first wife was the one who liked lilacs!
#  She also liked to shut up!"
sub cookie {
  my ($self, $name, $value, $options) = @_;
  return unless $name;

  # Response cookie
  if (defined $value) {

    # Cookie too big
    $self->app->log->error(qq/Cookie "$name" is bigger than 4096 bytes./)
      if length $value > 4096;

    # Create new cookie
    $options ||= {};
    my $cookie = Mojo::Cookie::Response->new(
      name  => $name,
      value => $value,
      %$options
    );
    $self->res->cookies($cookie);
    return $self;
  }

  # Request cookie
  unless (wantarray) {
    return unless my $cookie = $self->req->cookie($name);
    return $cookie->value;
  }

  # Request cookies
  my @cookies = $self->req->cookie($name);
  return map { $_->value } @cookies;
}

# "Something's wrong, she's not responding to my poking stick."
sub finish {
  my ($self, $chunk) = @_;

  # WebSocket
  my $tx = $self->tx;
  return $tx->finish if $tx->is_websocket;

  # Chunked stream
  if ($tx->res->is_chunked) {
    $self->write_chunk($chunk) if defined $chunk;
    return $self->write_chunk('');
  }

  # Normal stream
  $self->write($chunk) if defined $chunk;
  $self->write('');
}

# "You two make me ashamed to call myself an idiot."
sub flash {
  my $self = shift;

  # Get
  my $session = $self->stash->{'mojo.session'};
  if ($_[0] && !defined $_[1] && !ref $_[0]) {
    return unless $session && ref $session eq 'HASH';
    return unless my $flash = $session->{flash};
    return unless ref $flash eq 'HASH';
    return $flash->{$_[0]};
  }

  # Initialize
  $session = $self->session;
  my $flash = $session->{new_flash};
  $flash = {} unless $flash && ref $flash eq 'HASH';
  $session->{new_flash} = $flash;

  # Hash
  return $flash unless @_;

  # Set
  my $values = exists $_[1] ? {@_} : $_[0];
  $session->{new_flash} = {%$flash, %$values};

  return $self;
}

# "My parents may be evil, but at least they're stupid."
sub on_finish {
  my ($self, $cb) = @_;
  $self->tx->on_finish(sub { shift and $self->$cb(@_) });
}

# "I like being a women.
#  Now when I say something stupid, everyone laughs and buys me things."
sub on_message {
  my $self = shift;

  my $tx = $self->tx;
  Carp::croak('No WebSocket connection to receive messages from')
    unless $tx->is_websocket;
  my $cb = shift;
  $tx->on_message(sub { shift and $self->$cb(@_) });
  $self->rendered(101);

  return $self;
}

# "Just make a simple cake. And this time, if someone's going to jump out of
#  it make sure to put them in *after* you cook it."
sub param {
  my $self = shift;
  my $name = shift;

  # List
  my $p = $self->stash->{'mojo.captures'} || {};
  unless (defined $name) {
    my %seen;
    my @keys = grep { !$seen{$_}++ } $self->req->param;
    push @keys, grep { !$RESERVED{$_} && !$seen{$_}++ } keys %$p;
    return sort @keys;
  }

  # Override value
  if (@_) {
    $p->{$name} = $_[0];
    return $self;
  }

  # Captured unreserved value
  return $p->{$name} if !$RESERVED{$name} && exists $p->{$name};

  # Param value
  return $self->req->param($name);
}

# "Is there an app for kissing my shiny metal ass?
#  Several!
#  Oooh!"
sub redirect_to {
  my $self = shift;

  my $headers = $self->res->headers;
  $headers->location($self->url_for(@_)->to_abs);
  $headers->content_length(0);
  $self->rendered(302);

  return $self;
}

# "Mamma Mia! The cruel meatball of war has rolled onto our laps and ruined
#  our white pants of peace!"
sub render {
  my $self = shift;

  # Recursion
  my $stash = $self->stash;
  if ($stash->{'mojo.rendering'}) {
    $self->app->log->debug(qq/Can't render in "before_render" hook./);
    return '';
  }

  # Template may be first argument
  my $template;
  $template = shift if @_ % 2 && !ref $_[0];
  my $args = ref $_[0] ? $_[0] : {@_};

  # Template
  $args->{template} = $template if $template;
  unless ($stash->{template} || $args->{template}) {

    # Default template
    my $controller = $args->{controller} || $stash->{controller};
    my $action     = $args->{action}     || $stash->{action};

    # Normal default template
    if ($controller && $action) {
      $self->stash->{template} = join('/', split(/-/, $controller), $action);
    }

    # Try the route name if we don't have controller and action
    elsif ($self->match && $self->match->endpoint) {
      $self->stash->{template} = $self->match->endpoint->name;
    }
  }

  # Render
  my $app = $self->app;
  {
    local $stash->{'mojo.rendering'} = 1;
    $app->plugins->run_hook_reverse(before_render => $self, $args);
  }
  my ($output, $type) = $app->renderer->render($self, $args);
  return unless defined $output;
  return $output if $args->{partial};

  # Prepare response
  my $res = $self->res;
  $res->body($output) unless $res->body;
  my $headers = $res->headers;
  $headers->content_type($type) unless $headers->content_type;
  $self->rendered($stash->{status});

  return 1;
}

# "She's built like a steakhouse, but she handles like a bistro!"
sub render_content {
  my $self    = shift;
  my $name    = shift;
  my $content = pop;

  # Initialize
  my $stash = $self->stash;
  my $c = $stash->{'mojo.content'} ||= {};
  $name ||= 'content';

  # Set
  if (defined $content) {

    # Reset with multiple values
    if (@_) {
      $c->{$name} = '';
      for my $part (@_, $content) {
        $c->{$name} .= ref $part eq 'CODE' ? $part->() : $part;
      }
    }

    # First come
    else {
      $c->{$name} ||= ref $content eq 'CODE' ? $content->() : $content;
    }
  }

  # Get
  $content = $c->{$name};
  $content = '' unless defined $content;
  return Mojo::ByteStream->new("$content");
}

sub render_data { shift->render(data => shift, @_) }

# "The path to robot hell is paved with human flesh.
#  Neat."
sub render_exception {
  my ($self, $e) = @_;
  $e = Mojo::Exception->new($e);
  $self->app->log->error($e);

  # Recursion
  return if $self->stash->{'mojo.exception'};

  # Filtered stash snapshot
  my $snapshot = {};
  my $stash    = $self->stash;
  for my $key (keys %$stash) {
    next if $key =~ /^mojo\./;
    next unless defined(my $value = $stash->{$key});
    $snapshot->{$key} = $value;
  }

  # Mode specific template
  my $mode    = $self->app->mode;
  my $options = {
    template         => "exception.$mode",
    format           => 'html',
    handler          => undef,
    status           => 500,
    snapshot         => $snapshot,
    exception        => $e,
    'mojo.exception' => 1
  };
  unless ($self->render($options)) {

    # Template
    $options->{template} = 'exception';
    unless ($self->render($options)) {

      # Inline template
      delete $stash->{layout};
      delete $stash->{extends};
      delete $options->{template};
      $options->{inline} =
        $mode eq 'development' ? $DEVELOPMENT_EXCEPTION : $EXCEPTION;
      $options->{handler} = 'ep';
      $self->render($options);
    }
  }
}

# DEPRECATED in Smiling Face With Sunglasses!
sub render_inner {
  warn <<EOF;
Mojolicious::Controller->render_inner is DEPRECATED in favor of
Mojolicious::Controller->render_content!!!
EOF
  shift->render_content(@_);
}

# "If you hate intolerance and being punched in the face by me,
#  please support Proposition Infinity."
sub render_json {
  my $self = shift;
  my $json = shift;
  my $args = ref $_[0] ? $_[0] : {@_};
  $args->{json} = $json;
  return $self->render($args);
}

sub render_later { shift->stash->{'mojo.rendered'} = 1 }

# "Excuse me, sir, you're snowboarding off the trail.
#  Lick my frozen metal ass."
sub render_not_found {
  my ($self, $resource) = @_;
  $self->app->log->debug(qq/Resource "$resource" not found./) if $resource;

  # Recursion
  my $stash = $self->stash;
  return if $stash->{'mojo.exception'};
  return if $stash->{'mojo.not_found'};

  # Check for POD plugin
  my $guide =
      $self->app->renderer->helpers->{pod_to_html}
    ? $self->url_for('/perldoc')
    : 'http://mojolicio.us/perldoc';

  # Mode specific template
  my $mode    = $self->app->mode;
  my $options = {
    template         => "not_found.$mode",
    format           => 'html',
    status           => 404,
    guide            => $guide,
    'mojo.not_found' => 1
  };
  unless ($self->render($options)) {

    # Template
    $options->{template} = 'not_found';
    unless ($self->render($options)) {

      # Inline template
      delete $options->{layout};
      delete $options->{extends};
      delete $options->{template};
      $options->{inline} =
        $mode eq 'development' ? $DEVELOPMENT_NOT_FOUND : $NOT_FOUND;
      $options->{handler} = 'ep';
      $self->render($options);
    }
  }
}

# "You called my thesis a fat sack of barf, and then you stole it?
#  Welcome to academia."
sub render_partial {
  my $self     = shift;
  my $template = @_ % 2 ? shift : undef;
  my $args     = {@_};

  $args->{template} = $template if defined $template;
  $args->{partial} = 1;

  return Mojo::ByteStream->new($self->render($args));
}

sub render_static {
  my ($self, $file) = @_;

  my $app = $self->app;
  unless ($app->static->serve($self, $file)) {
    $app->log->debug(
      qq/Static file "$file" not found, public directory missing?/);
    return;
  }
  $self->rendered;

  return 1;
}

sub render_text { shift->render(text => shift, @_) }

# "On the count of three, you will awaken feeling refreshed,
#  as if Futurama had never been canceled by idiots,
#  then brought back by bigger idiots. One. Two."
sub rendered {
  my ($self, $status) = @_;

  # Disable auto rendering
  $self->render_later;

  # Make sure we have a status
  my $res = $self->res;
  $res->code($status) if $status;

  # Finish transaction
  my $stash = $self->stash;
  unless ($stash->{'mojo.finished'}) {
    $res->code(200) unless $res->code;
    my $app = $self->app;
    $app->plugins->run_hook_reverse(after_dispatch => $self);
    $app->sessions->store($self);
    $stash->{'mojo.finished'} = 1;
  }
  $self->tx->resume;

  return $self;
}

# "A three month calendar? What is this, Mercury?"
sub req { shift->tx->req }
sub res { shift->tx->res }

sub respond_to {
  my $self = shift;
  my $args = ref $_[0] ? $_[0] : {@_};

  # Detect formats
  my @formats;
  my $app = $self->app;
  push @formats, @{$app->types->detect($self->req->headers->accept)};
  my $stash = $self->stash;
  unless (@formats) {
    if (my $format = $stash->{format}) { push @formats, $format }
    else { push @formats, $app->renderer->default_format }
  }

  # Find target
  my $target;
  for my $format (@formats) {
    if ($target = $args->{$format}) {
      $stash->{format} = $format;
      last;
    }
  }

  # Fallback
  unless ($target) {
    return unless $target = $args->{any};
    delete $stash->{format};
  }

  # Dispatch
  ref $target eq 'CODE' ? $target->($self) : $self->render($target);
  return 1;
}

sub send_message {
  my ($self, $message, $cb) = @_;

  my $tx = $self->tx;
  Carp::croak('No WebSocket connection to send message to')
    unless $tx->is_websocket;
  $tx->send_message($message, sub { shift and $self->$cb(@_) if $cb });
  $self->rendered(101);

  return $self;
}

# "Why am I sticky and naked? Did I miss something fun?"
sub session {
  my $self = shift;

  # Get
  my $stash   = $self->stash;
  my $session = $stash->{'mojo.session'};
  if ($_[0] && !defined $_[1] && !ref $_[0]) {
    return unless $session && ref $session eq 'HASH';
    return $session->{$_[0]};
  }

  # Hash
  $session = {} unless $session && ref $session eq 'HASH';
  $stash->{'mojo.session'} = $session;
  return $session unless @_;

  # Set
  my $values = exists $_[1] ? {@_} : $_[0];
  $stash->{'mojo.session'} = {%$session, %$values};

  return $self;
}

sub signed_cookie {
  my ($self, $name, $value, $options) = @_;
  return unless $name;

  # Response cookie
  my $secret = $self->app->secret;
  if (defined $value) {

    # Sign value
    my $signature = Mojo::Util::hmac_md5_sum $value, $secret;
    $value = $value .= "--$signature";

    # Create cookie
    my $cookie = $self->cookie($name, $value, $options);
    return $cookie;
  }

  # Request cookies
  my @values = $self->cookie($name);
  my @results;
  for my $value (@values) {

    # Check signature
    if ($value =~ s/\-\-([^\-]+)$//) {
      my $signature = $1;
      my $check = Mojo::Util::hmac_md5_sum $value, $secret;

      # Verified
      if ($signature eq $check) { push @results, $value }

      # Bad cookie
      else {
        $self->app->log->debug(
          qq/Bad signed cookie "$name", possible hacking attempt./);
      }
    }

    # Not signed
    else { $self->app->log->debug(qq/Cookie "$name" not signed./) }
  }

  return wantarray ? @results : $results[0];
}

# "All this knowledge is giving me a raging brainer."
sub stash {
  my $self = shift;

  # Hash
  $self->{stash} ||= {};
  return $self->{stash} unless @_;

  # Get
  return $self->{stash}->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  for my $key (keys %$values) {
    $self->app->log->debug(qq/Careful, "$key" is a reserved stash value./)
      if $RESERVED{$key};
    $self->{stash}->{$key} = $values->{$key};
  }

  return $self;
}

sub ua { shift->app->ua }

# "Behold, a time traveling machine.
#  Time? I can't go back there!
#  Ah, but this machine only goes forward in time.
#  That way you can't accidentally change history or do something disgusting
#  like sleep with your own grandmother.
#  I wouldn't want to do that again."
sub url_for {
  my $self = shift;
  my $target = shift || '';

  # Absolute URL
  return Mojo::URL->new($target) if $target =~ /^\w+\:\/\//;

  # Make sure we have a match for named routes
  my $match;
  unless ($match = $self->match) {
    $match = Mojolicious::Routes::Match->new(get => '/');
    $match->root($self->app->routes);
  }

  # Base
  my $url = Mojo::URL->new;
  my $req = $self->req;
  $url->base($req->url->base->clone);
  my $base = $url->base;
  $base->userinfo(undef);

  # Relative URL
  my $path = $url->path;
  if ($target =~ /^\//) {
    if (my $e = $self->stash->{path}) {
      my $real = $req->url->path->to_abs_string;
      Mojo::Util::url_unescape($real);
      my $backup = $real;
      Mojo::Util::decode('UTF-8', $real);
      $real = $backup unless defined $real;
      $real =~ s/\/?$e$/$target/;
      $target = $real;
    }
    $url->parse($target);
  }

  # Route
  else {
    my ($p, $ws) = $match->path_for($target, @_);
    $path->parse($p) if $p;

    # Fix trailing slash
    $path->trailing_slash(1)
      if (!$target || $target eq 'current')
      && $req->url->path->trailing_slash;

    # Fix scheme for WebSockets
    $base->scheme(($base->scheme || '') eq 'https' ? 'wss' : 'ws') if $ws;
  }

  # Make path absolute
  my $base_path = $base->path;
  unshift @{$path->parts}, @{$base_path->parts};
  $base_path->parts([]);

  return $url;
}

# "I wax my rocket every day!"
sub write {
  my ($self, $chunk, $cb) = @_;

  if (ref $chunk && ref $chunk eq 'CODE') {
    $cb    = $chunk;
    $chunk = undef;
  }
  $self->res->write($chunk, sub { shift and $self->$cb(@_) if $cb });
  $self->rendered;

  return $self;
}

sub write_chunk {
  my ($self, $chunk, $cb) = @_;

  if (ref $chunk && ref $chunk eq 'CODE') {
    $cb    = $chunk;
    $chunk = undef;
  }
  $self->res->write_chunk($chunk, sub { shift and $self->$cb(@_) if $cb });
  $self->rendered;

  return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Controller - Controller Base Class

=head1 SYNOPSIS

  use Mojo::Base 'Mojolicious::Controller';

=head1 DESCRIPTION

L<Mojolicious::Controller> is the base class for your L<Mojolicious>
controllers.
It is also the default controller class for L<Mojolicious> unless you set
C<controller_class> in your application.

=head1 ATTRIBUTES

L<Mojolicious::Controller> inherits all attributes from L<Mojo::Base> and
implements the following new ones.

=head2 C<app>

  my $app = $c->app;
  $c      = $c->app(Mojolicious->new);

A reference back to the L<Mojolicious> application that dispatched to this
controller.

=head2 C<match>

  my $m = $c->match;

A L<Mojolicious::Routes::Match> object containing the routes results for the
current request.

=head2 C<tx>

  my $tx = $c->tx;

The transaction that is currently being processed, usually a
L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket> object.

=head1 METHODS

L<Mojolicious::Controller> inherits all methods from L<Mojo::Base> and
implements the following new ones.

=head2 C<cookie>

  $c         = $c->cookie(foo => 'bar');
  $c         = $c->cookie(foo => 'bar', {path => '/'});
  my $value  = $c->cookie('foo');
  my @values = $c->cookie('foo');

Access request cookie values and create new response cookies.

=head2 C<finish>

  $c->finish;
  $c->finish('Bye!');

Gracefully end WebSocket connection or long poll stream.

=head2 C<flash>

  my $flash = $c->flash;
  my $foo   = $c->flash('foo');
  $c        = $c->flash({foo => 'bar'});
  $c        = $c->flash(foo => 'bar');

Data storage persistent for the next request, stored in the session.

  $c->flash->{foo} = 'bar';
  my $foo = $c->flash->{foo};
  delete $c->flash->{foo};

=head2 C<on_finish>

  $c->on_finish(sub {...});

Callback to be invoked when the transaction has been finished.

  $c->on_finish(sub {
    my $c = shift;
  });

=head2 C<on_message>

  $c = $c->on_message(sub {...});

Callback to be invoked when new WebSocket messages arrive.

  $c->on_message(sub {
    my ($c, $message) = @_;
  });

=head2 C<param>

  my @names = $c->param;
  my $foo   = $c->param('foo');
  my @foo   = $c->param('foo');
  $c        = $c->param(foo => 'ba;r');

Access GET/POST parameters and route captures that are not reserved stash
values.

  # Only GET parameters
  my $foo = $c->req->url->query->param('foo');

  # Only GET and POST parameters
  my $foo = $c->req->param('foo');

=head2 C<redirect_to>

  $c = $c->redirect_to('named');
  $c = $c->redirect_to('named', foo => 'bar');
  $c = $c->redirect_to('/path');
  $c = $c->redirect_to('http://127.0.0.1/foo/bar');

Prepare a C<302> redirect response, takes the exact same arguments as
C<url_for>.

  return $c->redirect_to('login') unless $c->session('user');

=head2 C<render>

  $c->render;
  $c->render(controller => 'foo', action => 'bar');
  $c->render({controller => 'foo', action => 'bar'});
  $c->render(text => 'Hello!');
  $c->render(template => 'index');
  $c->render(template => 'foo/index');
  $c->render(template => 'index', format => 'html', handler => 'epl');
  $c->render(handler => 'something');
  $c->render('foo/bar');
  $c->render('foo/bar', format => 'html');

This is a wrapper around L<Mojolicious::Renderer> exposing pretty much all
functionality provided by it.
It will set a default template to use based on the controller and action name
or fall back to the route name.
You can call it with a hash of options which can be preceded by an optional
template name.
It will also run the C<before_render> plugin hook.

=head2 C<render_content>

  my $output = $c->render_content;
  my $output = $c->render_content('header');
  my $output = $c->render_content(header => 'Hello world!');
  my $output = $c->render_content(header => sub { 'Hello world!' });

Contains partial rendered templates, used for the renderers C<layout> and
C<extends> features.

=head2 C<render_data>

  $c->render_data($bits);
  $c->render_data($bits, format => 'png');

Render the given content as raw bytes, similar to C<render_text> but data
will not be encoded.

=head2 C<render_exception>

  $c->render_exception('Oops!');
  $c->render_exception(Mojo::Exception->new('Oops!'));

Render the exception template C<exception.$mode.html.$handler> or
C<exception.html.$handler> and set the response status code to C<500>.

=head2 C<render_json>

  $c->render_json({foo => 'bar'});
  $c->render_json([1, 2, -3]);

Render a data structure as JSON.

=head2 C<render_later>

  $c->render_later;

Disable auto rendering, especially for long polling this can be quite useful.

  $c->render_later;
  Mojo::IOLoop->timer(2 => sub {
    $c->render(text => 'Delayed by 2 seconds!');
  });

=head2 C<render_not_found>

  $c->render_not_found;
  $c->render_not_found($resource);
    
Render the not found template C<not_found.$mode.html.$handler> or
C<not_found.html.$handler> and set the response status code to C<404>.

=head2 C<render_partial>

  my $output = $c->render_partial('menubar');
  my $output = $c->render_partial('menubar', format => 'txt');
    
Same as C<render> but returns the rendered result.

=head2 C<render_static>

  my $success = $c->render_static('images/logo.png');
  my $success = $c->render_static('../lib/MyApp.pm');

Render a static file using L<Mojolicious::Static> relative to the
C<public> directory of your application.

=head2 C<render_text>

  $c->render_text('Hello World!');
  $c->render_text('Hello World', layout => 'green');

Render the given content as Perl characters, which will be encoded to bytes.
See C<render_data> for an alternative without encoding.
Note that this does not change the content type of the response, which is
C<text/html;charset=UTF-8> by default.

  $c->render_text('Hello World!', format => 'txt');

=head2 C<rendered>

  $c = $c->rendered;
  $c = $c->rendered(302);

Finalize response and run C<after_dispatch> plugin hook.

=head2 C<req>

  my $req = $c->req;

Alias for C<$c-E<gt>tx-E<gt>req>.
Usually refers to a L<Mojo::Message::Request> object.

=head2 C<res>

  my $res = $c->res;

Alias for C<$c-E<gt>tx-E<gt>res>.
Usually refers to a L<Mojo::Message::Response> object.

=head2 C<respond_to>

  my $success = $c->respond_to(
    json => sub {...},
    xml  => {text => 'hello!'},
    any  => sub {...}
  );

Automatically select best possible representation for resource from C<Accept>
request header and route C<format>.
Note that this method is EXPERIMENTAL and might change without warning!

  $c->respond_to(
    json => sub { $c->render_json({just => 'works'}) },
    xml  => {text => '<just>works</just>'},
    any  => {data => '', status => 204}
  );

=head2 C<send_message>

  $c = $c->send_message('Hi there!');
  $c = $c->send_message('Hi there!', sub {...});

Send a message via WebSocket, only works if there is currently a WebSocket
connection in progress.

=head2 C<session>

  my $session = $c->session;
  my $foo     = $c->session('foo');
  $c          = $c->session({foo => 'bar'});
  $c          = $c->session(foo => 'bar');

Persistent data storage, defaults to using signed cookies.
Note that cookies are generally limited to 4096 bytes of data.

  $c->session->{foo} = 'bar';
  my $foo = $c->session->{foo};
  delete $c->session->{foo};

=head2 C<signed_cookie>

  $c         = $c->signed_cookie(foo => 'bar');
  $c         = $c->signed_cookie(foo => 'bar', {path => '/'});
  my $value  = $c->signed_cookie('foo');
  my @values = $c->signed_cookie('foo');

Access signed request cookie values and create new signed response cookies.
Cookies failing signature verification will be automatically discarded.

=head2 C<stash>

  my $stash = $c->stash;
  my $foo   = $c->stash('foo');
  $c        = $c->stash({foo => 'bar'});
  $c        = $c->stash(foo => 'bar');

Non persistent data storage and exchange.

  $c->stash->{foo} = 'bar';
  my $foo = $c->stash->{foo};
  delete $c->stash->{foo};

=head2 C<ua>

  my $ua = $c->ua;
    
A L<Mojo::UserAgent> prepared for the current environment.

  # Blocking
  my $tx = $c->ua->get('http://mojolicio.us');
  my $tx = $c->ua->post_form('http://kraih.com/login' => {user => 'mojo'});

  # Non-blocking
  $c->ua->get('http://mojolicio.us' => sub {
    my $tx = pop;
    $c->render_data($tx->res->body);
  });

  # Parallel non-blocking
  my $t = Mojo::IOLoop->trigger(sub {
    my ($t, @titles) = @_;
    $c->render_json(\@titles);
  });
  for my $url ('http://mojolicio.us', 'https://metacpan.org') {
    $t->begin;
    $c->ua->get($url => sub {
      $t->end(pop->res->dom->html->head->title->text);
    });
  }

=head2 C<url_for>

  my $url = $c->url_for;
  my $url = $c->url_for(controller => 'bar', action => 'baz');
  my $url = $c->url_for('named', controller => 'bar', action => 'baz');
  my $url = $c->url_for('/perldoc');
  my $url = $c->url_for('http://mojolicio.us/perldoc');

Generate a portable L<Mojo::URL> object with base for a route, path or URL.

  # "/perldoc" if application is deployed under "/"
  print $c->url_for('/perldoc');

  # "/myapp/perldoc" if application is deployed under "/myapp"
  print $c->url_for('/perldoc');

=head2 C<write>

  $c->write;
  $c->write('Hello!');
  $c->write(sub {...});
  $c->write('Hello!', sub {...});

Write dynamic content chunk wise, the optional drain callback will be invoked
once all data has been written to the kernel send buffer or equivalent.

  # Keep connection alive (with Content-Length header)
  $c->res->headers->content_length(6);
  $c->write('Hel', sub {
    my $c = shift;
    $c->write('lo!')
  });

  # Close connection when done (without Content-Length header)
  $c->write('Hel', sub {
    my $c = shift;
    $c->write('lo!', sub {
      my $c = shift;
      $c->finish;
    });
  });

=head2 C<write_chunk>

  $c->write_chunk;
  $c->write_chunk('Hello!');
  $c->write_chunk(sub {...});
  $c->write_chunk('Hello!', sub {...});

Write dynamic content chunk wise with the C<chunked> C<Transfer-Encoding>
which doesn't require a C<Content-Length> header, the optional drain callback
will be invoked once all data has been written to the kernel send buffer or
equivalent.

  $c->write_chunk('He', sub {
    my $c = shift;
    $c->write_chunk('ll', sub {
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
instances of L<Mojolicious::Controller>.
This includes all helpers from L<Mojolicious::Plugin::DefaultHelpers> and
L<Mojolicious::Plugin::TagHelpers>.

  $c->layout('green');
  $c->title('Welcome!');

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
