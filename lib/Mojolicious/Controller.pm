package Mojolicious::Controller;
use Mojo::Base 'Mojo::Command';

use Mojo::ByteStream;
use Mojo::Command;
use Mojo::Cookie::Response;
use Mojo::Exception;
use Mojo::Transaction::HTTP;
use Mojo::URL;
use Mojo::Util;

require Carp;

# "Scalpel... blood bucket... priest."
has [qw/app match/];
has tx => sub { Mojo::Transaction::HTTP->new };

# Exception template
our $EXCEPTION =
  Mojo::Command->new->get_data('exception.html.ep', __PACKAGE__);

# Exception template (development)
our $DEVELOPMENT_EXCEPTION =
  Mojo::Command->new->get_data('exception.development.html.ep', __PACKAGE__);

# Not found template
our $NOT_FOUND =
  Mojo::Command->new->get_data('not_found.html.ep', __PACKAGE__);

# Not found template (development)
our $DEVELOPMENT_NOT_FOUND =
  Mojo::Command->new->get_data('not_found.development.html.ep', __PACKAGE__);

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

  # Helper
  Carp::croak(qq/Can't locate object method "$method" via "$package"/)
    unless my $helper = $self->app->renderer->helpers->{$method};

  # Run
  return $self->$helper(@_);
}

sub DESTROY { }

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
sub client {
  warn <<EOF;
Mojolicious::Controller->client is DEPRECATED in favor of
Mojolicious::Controller->ua!!!
EOF
  return shift->app->client;
}

# "For the last time, I don't like lilacs!
#  Your first wife was the one who liked lilacs!
#  She also liked to shut up!"
sub cookie {
  my ($self, $name, $value, $options) = @_;

  # Shortcut
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
  my $self = shift;

  # Transaction
  my $tx = $self->tx;

  # WebSocket check
  Carp::croak('No WebSocket connection to finish') unless $tx->is_websocket;

  # Finish WebSocket
  $tx->finish;
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

  # Transaction finished
  $self->tx->on_finish(sub { shift and $self->$cb(@_) });
}

# "Stop being such a spineless jellyfish!
#  You know full well I'm more closely related to the sea cucumber.
#  Not where it counts."
sub on_message {
  my $self = shift;

  # Transaction
  my $tx = $self->tx;

  # WebSocket check
  Carp::croak('No WebSocket connection to receive messages from')
    unless $tx->is_websocket;

  # Callback
  my $cb = shift;

  # Receive
  $tx->on_message(sub { shift and $self->$cb(@_) });

  # Rendered
  $self->rendered;

  return $self;
}

# "Just make a simple cake. And this time, if someone's going to jump out of
#  it make sure to put them in *after* you cook it."
sub param {
  my $self = shift;
  my $name = shift;

  # Captures
  my $p = $self->stash->{'mojo.captures'} || {};

  # List
  unless (defined $name) {
    my %seen;
    return sort grep { !$seen{$_}++ } keys %$p, $self->req->param;
  }

  # Override value
  if (@_) {
    $p->{$name} = $_[0];
    return $self;
  }

  # Captured value
  return $p->{$name} if exists $p->{$name};

  # Param value
  return $self->req->param($name);
}

# "Is there an app for kissing my shiny metal ass?
#  Several!
#  Oooh!"
sub redirect_to {
  my $self = shift;

  # Response
  my $res = $self->res;

  # Code
  $res->code(302);

  # Headers
  my $headers = $res->headers;
  $headers->location($self->url_for(@_)->to_abs);
  $headers->content_length(0);

  # Rendered
  $self->rendered;

  return $self;
}

# "Mamma Mia! The cruel meatball of war has rolled onto our laps and ruined
#  our white pants of peace!"
sub render {
  my $self = shift;

  # Template as single argument
  my $stash = $self->stash;
  my $template;
  $template = shift if @_ % 2 && !ref $_[0];

  # Arguments
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
  my ($output, $type) = $self->app->renderer->render($self, $args);

  # Failed
  return unless defined $output;

  # Partial
  return $output if $args->{partial};

  # Response
  my $res = $self->res;

  # Status
  $res->code($stash->{status}) if $stash->{status};
  $res->code(200) unless $res->code;

  # Output
  $res->body($output) unless $res->body;

  # Type
  my $headers = $res->headers;
  $headers->content_type($type) unless $headers->content_type;

  # Rendered
  $self->rendered;

  # Success
  return 1;
}

sub render_data {
  my $self = shift;
  my $data = shift;

  # Arguments
  my $args = ref $_[0] ? $_[0] : {@_};

  # Data
  $args->{data} = $data;

  return $self->render($args);
}

# "The path to robot hell is paved with human flesh.
#  Neat."
sub render_exception {
  my ($self, $e) = @_;

  # Exception
  $e = Mojo::Exception->new($e);

  # Error
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

  # Mode
  my $mode = $self->app->mode;

  # Exception template
  my $options = {
    template         => "exception.$mode",
    format           => 'html',
    handler          => undef,
    status           => 500,
    layout           => undef,
    extends          => undef,
    snapshot         => $snapshot,
    exception        => $e,
    'mojo.exception' => 1
  };

  # Mode specific template
  unless ($self->render($options)) {

    # Template
    $options->{template} = 'exception';
    unless ($self->render($options)) {

      # Inline template
      delete $options->{template};
      $options->{inline} =
        $mode eq 'development' ? $DEVELOPMENT_EXCEPTION : $EXCEPTION;
      $options->{handler} = 'ep';
      $self->render($options);

      # Render
      $self->render($options);
    }
  }

  # Rendered
  $self->rendered;
}

sub render_inner {
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

# "If you hate intolerance and being punched in the face by me,
#  please support Proposition Infinity."
sub render_json {
  my $self = shift;
  my $json = shift;

  # Arguments
  my $args = ref $_[0] ? $_[0] : {@_};

  # JSON
  $args->{json} = $json;

  return $self->render($args);
}

sub render_later { shift->stash->{'mojo.rendered'} = 1 }

# "Excuse me, sir, you're snowboarding off the trail.
#  Lick my frozen metal ass."
sub render_not_found {
  my ($self, $resource) = @_;

  # Debug
  $self->app->log->debug(qq/Resource "$resource" not found./)
    if $resource;

  # Stash
  my $stash = $self->stash;

  # Exception
  return if $stash->{'mojo.exception'};

  # Recursion
  return if $stash->{'mojo.not_found'};

  # Check for POD plugin
  my $guide =
      $self->app->renderer->helpers->{pod_to_html}
    ? $self->url_for('/perldoc')
    : 'http://mojolicio.us/perldoc';

  # Mode
  my $mode = $self->app->mode;

  # Render not found template
  my $options = {
    template         => "not_found.$mode",
    format           => 'html',
    status           => 404,
    layout           => undef,
    extends          => undef,
    guide            => $guide,
    'mojo.not_found' => 1
  };

  # Mode specific template
  unless ($self->render($options)) {

    # Template
    $options->{template} = 'not_found';
    unless ($self->render($options)) {

      # Inline template
      delete $options->{template};
      $options->{inline} =
        $mode eq 'development' ? $DEVELOPMENT_NOT_FOUND : $NOT_FOUND;
      $options->{handler} = 'ep';

      # Render
      $self->render($options);
    }
  }

  # Rendered
  $self->rendered;
}

# "You called my thesis a fat sack of barf, and then you stole it?
#  Welcome to academia."
sub render_partial {
  my $self = shift;

  # Template as single argument
  my $template;
  $template = shift if (@_ % 2 && !ref $_[0]) || (!@_ % 2 && ref $_[1]);

  # Arguments
  my $args = ref $_[0] ? $_[0] : {@_};

  # Template
  $args->{template} = $template if $template;

  # Partial
  $args->{partial} = 1;

  return Mojo::ByteStream->new($self->render($args));
}

sub render_static {
  my ($self, $file) = @_;

  # Application
  my $app = $self->app;

  # Static
  $app->static->serve($self, $file)
    and $app->log->debug(
    qq/Static file "$file" not found, public directory missing?/);

  # Rendered
  $self->rendered;
}

sub render_text {
  my $self = shift;
  my $text = shift;

  # Arguments
  my $args = ref $_[0] ? $_[0] : {@_};

  # Data
  $args->{text} = $text;

  return $self->render($args);
}

# "On the count of three, you will awaken feeling refreshed,
#  as if Futurama had never been canceled by idiots,
#  then brought back by bigger idiots. One. Two."
sub rendered {
  my $self = shift;

  # Disable auto rendering
  $self->render_later;

  # Stash
  my $stash = $self->stash;

  # Already finished
  unless ($stash->{'mojo.finished'}) {

    # Application
    my $app = $self->app;

    # Session
    $app->sessions->store($self);

    # Hook
    $app->plugins->run_hook_reverse(after_dispatch => $self);

    # Finished
    $stash->{'mojo.finished'} = 1;
  }

  # Resume
  $self->tx->resume;

  return $self;
}

sub req { shift->tx->req }
sub res { shift->tx->res }

sub send_message {
  my ($self, $message, $cb) = @_;

  # Transaction
  my $tx = $self->tx;

  # WebSocket check
  Carp::croak('No WebSocket connection to send message to')
    unless $tx->is_websocket;

  # Send
  $tx->send_message(
    $message,
    sub {

      # Cleanup
      shift;

      # Callback
      $self->$cb(@_) if $cb;
    }
  );

  # Rendered
  $self->rendered;

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

  # Initialize
  $session = {} unless $session && ref $session eq 'HASH';
  $stash->{'mojo.session'} = $session;

  # Hash
  return $session unless @_;

  # Set
  my $values = exists $_[1] ? {@_} : $_[0];
  $stash->{'mojo.session'} = {%$session, %$values};

  return $self;
}

sub signed_cookie {
  my ($self, $name, $value, $options) = @_;

  # Shortcut
  return unless $name;

  # Secret
  my $secret = $self->app->secret;

  # Response cookie
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

  # Initialize
  $self->{stash} ||= {};

  # Hash
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

  # Request
  my $req = $self->req;

  # Make sure we have a match for named routes
  my $match;
  unless ($match = $self->match) {
    $match = Mojolicious::Routes::Match->new(get => '/');
    $match->root($self->app->routes);
  }

  # URL
  my $url = Mojo::URL->new;

  # Base
  $url->base($req->url->base->clone);
  my $base = $url->base;
  $base->userinfo(undef);

  # Path
  my $path = $url->path;

  # Relative URL
  if ($target =~ /^\//) { $url->parse($target) }

  # Route
  else {
    my ($p, $ws) = $match->path_for($target, @_);

    # Path
    $path->parse($p) if $p;

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

  # Callback only
  if (ref $chunk && ref $chunk eq 'CODE') {
    $cb    = $chunk;
    $chunk = undef;
  }

  # Write
  $self->res->write(
    $chunk,
    sub {

      # Cleanup
      shift;

      # Callback
      $self->$cb(@_) if $cb;
    }
  );

  # Rendered
  $self->rendered;
}

sub write_chunk {
  my ($self, $chunk, $cb) = @_;

  # Callback only
  if (ref $chunk && ref $chunk eq 'CODE') {
    $cb    = $chunk;
    $chunk = undef;
  }

  # Write
  $self->res->write_chunk(
    $chunk,
    sub {

      # Cleanup
      shift;

      # Callback
      $self->$cb(@_) if $cb;
    }
  );

  # Rendered
  $self->rendered;
}

1;
__DATA__

@@ exception.html.ep
<!doctype html><html>
  <head><title>Server Error</title></head>
   %= stylesheet begin
      body { background-color: #caecf6; }
      #raptor {
        background: url(<%= url_for '/failraptor.png' %>);
        height: 488px;
        left: 50%;
        margin-left: -371px;
        margin-top: -244px;
        position:absolute;
        top: 50%;
        width: 743px;
      }
    % end
  <body><div id="raptor"></div></body>
</html>

@@ exception.development.html.ep
% my $e = delete $self->stash->{'exception'};
<!doctype html><html>
  <head>
    <title>Server Error</title>
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="-1">
    %= javascript '/js/jquery.js'
    %= stylesheet '/css/prettify-mojo.css'
    %= javascript '/js/prettify.js'
    %= stylesheet begin
      a img { border: 0; }
      body {
        background-color: #f5f6f8;
        color: #333;
        font: 0.9em Verdana, sans-serif;
        margin-left: 3em;
        margin-right: 3em;
        margin-top: 0;
        text-shadow: #ddd 0 1px 0;
      }
      pre {
        margin: 0;
        white-space: pre-wrap;
      }
      table {
        border-collapse: collapse;
        margin-top: 1em;
        margin-bottom: 1em;
        width: 100%;
      }
      td { padding: 0.3em; }
      .box {
        background-color: #fff;
        -moz-box-shadow: 0px 0px 2px #ccc;
        -webkit-box-shadow: 0px 0px 2px #ccc;
        box-shadow: 0px 0px 2px #ccc;
        overflow: hidden;
        padding: 1em;
      }
      .code {
        background-color: #1a1a1a;
        background: url(<%= url_for '/mojolicious-pinstripe.gif' %>);
        color: #eee;
        font-family: 'Menlo', 'Monaco', Courier, monospace !important;
        text-shadow: #333 0 1px 0;
      }
      .file {
        margin-bottom: 0.5em;
        margin-top: 1em;
      }
      .important { background-color: rgba(47, 48, 50, .75); }
      .infobox tr:nth-child(odd) .value { background-color: #ddeeff; }
      .infobox tr:nth-child(even) .value { background-color: #eef9ff; }
      .key {
        text-align: right;
        text-weight: bold;
      }
      .preview {
        background-color: #1a1a1a;
        background: url(<%= url_for '/mojolicious-pinstripe.gif' %>);
        -moz-border-radius: 5px;
        border-radius: 5px;
        margin-bottom: 1em;
        padding: 0.5em;
      }
      .tap {
        font: 0.5em Verdana, sans-serif;
        text-align: center;
      }
      .value {
        padding-left: 1em;
        width: 100%;
      }
      #footer {
        margin-top: 1.5em;
        text-align: center;
        width: 100%;
      }
      #showcase {
        margin-top: 1em;
        -moz-border-radius-topleft: 5px;
        border-top-left-radius: 5px;
        -moz-border-radius-topright: 5px;
        border-top-right-radius: 5px;
      }
      #showcase pre {
        font: 1.5em Georgia, Times, serif;
        margin: 0;
        text-shadow: #333 0 1px 0;
      }
      #more, #trace {
        -moz-border-radius-bottomleft: 5px;
        border-bottom-left-radius: 5px;
        -moz-border-radius-bottomright: 5px;
        border-bottom-right-radius: 5px;
      }
      #request {
        -moz-border-radius-topleft: 5px;
        border-top-left-radius: 5px;
        -moz-border-radius-topright: 5px;
        border-top-right-radius: 5px;
        margin-top: 1em;
      }
    % end
  </head>
  <body onload="prettyPrint()">
    % my $code = begin
      <code class="prettyprint"><%= shift %></code>
    % end
    % my $cv = begin
      % my ($key, $value, $i) = @_;
      %= tag 'tr', $i ? (class => 'important') : undef, begin
        <td class="key"><%= $key %>.</td>
        <td class="value">
          %== $code->($value)
        </td>
      % end
    % end
    % my $kv = begin
      % my ($key, $value) = @_;
      <tr>
        <td class="key"><%= $key %>:</td>
        <td class="value">
          <pre><%= $value %></pre>
        </td>
      </tr>
    % end
    <div id="showcase" class="code box">
      <pre><%= $e->message %></pre>
      <div id="context">
        <table>
          % for my $line (@{$e->lines_before}) {
            %== $cv->($line->[0], $line->[1])
          % }
          % if (defined $e->line->[1]) {
            %== $cv->($e->line->[0], $e->line->[1], 1)
          % }
          % for my $line (@{$e->lines_after}) {
            %== $cv->($line->[0], $line->[1])
          % }
        </table>
      </div>
      % if (defined $e->line->[2]) {
        <div id="insight">
          <table>
            % for my $line (@{$e->lines_before}) {
              %== $cv->($line->[0], $line->[2])
            % }
            %== $cv->($e->line->[0], $e->line->[2], 1)
            % for my $line (@{$e->lines_after}) {
              %== $cv->($line->[0], $line->[2])
            % }
          </table>
        </div>
        <div class="tap">tap for more</div>
        %= javascript begin
          var current = '#context';
          $('#showcase').click(function() {
            $(current).slideToggle('slow', function() {
              if (current == '#context') {
                current = '#insight';
              }
              else {
                current = '#context';
              }
              $(current).slideToggle('slow');
            });
          });
          $('#insight').toggle();
        % end
      % }
    </div>
    <div class="box" id="trace">
      % if (@{$e->frames}) {
        <div id="frames">
          % for my $frame (@{$e->frames}) {
            % if (my $line = $frame->[3]) {
              <div class="file"><%= $frame->[1] %></div>
              <div class="code preview">
                %= "$frame->[2]."
                %== $code->($line)
              </div>
            % }
          % }
        </div>
        <div class="tap">tap for more</div>
        %= javascript begin
          $('#trace').click(function() {
            $('#frames').slideToggle('slow');
          });
          $('#frames').toggle();
        % end
      % }
    </div>
    <div class="box infobox" id="request">
      <table>
        % my $req = $self->req;
        %== $kv->(Method => $req->method)
        % my $url = $req->url;
        %== $kv->(Path => $url->to_string)
        %== $kv->(Base => $url->base->to_string)
        %== $kv->(Parameters => dumper $req->params->to_hash)
        %== $kv->(Stash => dumper $snapshot)
        %== $kv->(Session => dumper session)
        %== $kv->(Version => $req->version)
        % for my $name (@{$self->req->headers->names}) {
          % my $value = $self->req->headers->header($name);
          %== $kv->($name, $value)
        % }
      </table>
    </div>
    <div class="box infobox" id="more">
      <div id="infos">
        <table>
          %== $kv->(Perl => "$] ($^O)")
          % my $version  = $Mojolicious::VERSION;
          % my $codename = $Mojolicious::CODENAME;
          %== $kv->(Mojolicious => "$version ($codename)")
          %== $kv->(Home => app->home)
          %== $kv->(Include => dumper \@INC)
          %== $kv->(PID => $$)
          %== $kv->(Name => $0)
          %== $kv->(Executable => $^X)
          %== $kv->(Time => scalar localtime(time))
        </table>
      </div>
      <div class="tap">tap for more</div>
    </div>
    <div id="footer">
      %= link_to 'http://mojolicio.us' => begin
        %= image '/mojolicious-black.png', alt => 'Mojolicious logo'
      % end
    </div>
    %= javascript begin
      $('#more').click(function() {
        $('#infos').slideToggle('slow');
      });
      $('#infos').toggle();
    % end
  </body>
</html>

@@ not_found.html.ep
<!doctype html><html>
  <head><title>Page Not Found</title></head>
   %= stylesheet begin
      a img { border: 0; }
      body { background-color: #caecf6; }
      #noraptor {
        left: 0%;
        position: fixed;
        top: 60%;
      }
      #notfound {
        background: url(<%= url_for '/mojolicious-notfound.png' %>);
        height: 62px;
        left: 50%;
        margin-left: -153px;
        margin-top: -31px;
        position:absolute;
        top: 50%;
        width: 306px;
      }
    % end
  <body>
    %= link_to url_for->base => begin
      %= image '/mojolicious-noraptor.png', alt => 'Bye!', id => 'noraptor'
    % end
    <div id="notfound"></div>
  </body>
</html>
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->

@@ not_found.development.html.ep
<!doctype html><html>
  <head>
    <title>Page Not Found</title>
    %= stylesheet '/css/prettify-mojo.css'
    %= javascript '/js/prettify.js'
    %= stylesheet begin
      a {
        color: inherit;
        text-decoration: none;
      }
      a img { border: 0; }
      body {
        background-color: #f5f6f8;
        color: #333;
        font: 0.9em Verdana, sans-serif;
        margin: 0;
        text-align: center;
        text-shadow: #ddd 0 1px 0;
      }
      h1 {
        font: 1.5em Georgia, Times, serif;
        margin-bottom: 1em;
        margin-top: 1em;
        text-shadow: #666 0 1px 0;
      }
      #footer {
        background-color: #caecf6;
        padding-top: 20em;
        width: 100%;
      }
      #footer a img { margin-top: 20em; }
      #documentation {
        background-color: #ecf1da;
        padding-bottom: 20em;
        padding-top: 20em;
      }
      #documentation h1 { margin-bottom: 3em; }
      #header {
        margin-bottom: 20em;
        margin-top: 15em;
        width: 100%;
      }
      #perldoc {
        background-color: #eee;
        border: 2px dashed #1a1a1a;
        color: #000;
        display: inline-block;
        margin-left: 0.1em;
        padding: 0.5em;
        white-space: nowrap;
      }
      #preview {
        background-color: #1a1a1a;
        background: url(<%= url_for '/mojolicious-pinstripe.gif' %>);
        -moz-border-radius: 5px;
        border-radius: 5px;
        font-family: 'Menlo', 'Monaco', Courier, monospace !important;
        font-size: 1.5em;
        margin: 0;
        margin-left: auto;
        margin-right: auto;
        padding: 0.5em;
        padding-left: 1em;
        text-align: left;
        width: 500px;
      }
      #suggestion {
        background-color: #2f3032;
        color: #eee;
        padding-bottom: 20em;
        padding-top: 20em;
        text-shadow: #333 0 1px 0;
      }
    % end
  </head>
  <body onload="prettyPrint()">
    <div id="header">
      %= image '/mojolicious-box.png', alt => 'Mojolicious banner'
      <h1>This page is brand new and has not been unboxed yet!</h1>
    </div>
    <div id="suggestion">
      %= image '/mojolicious-arrow.png', alt => 'Arrow'
      <h1>Perhaps you would like to add a route for it?</h1>
      <div id="preview">
        <pre class="prettyprint">
get '<%= $self->req->url->path->to_abs_string %>' => sub {
    my $self = shift;
    $self->render(text => 'Hello world!');
};</pre>
      </div>
    </div>
    <div id="documentation">
      <h1>
        You might also enjoy our excellent documentation in
        <div id="perldoc">
          %= link_to 'perldoc Mojolicious::Guides', $guide
        </div>
      </h1>
      %= image '/amelia.png', alt => 'Amelia'
    </div>
    <div id="footer">
      <h1>And don't forget to have fun!</h1>
      <p><%= image '/mojolicious-clouds.png', alt => 'Clouds' %></p>
      %= link_to 'http://mojolicio.us' => begin
        %= image '/mojolicious-black.png', alt => 'Mojolicious logo'
      % end
    </div>
  </body>
</html>

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

The transaction that is currently being processed, defaults to a
L<Mojo::Transaction::HTTP> object.

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

Gracefully end WebSocket connection.

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

Callback signaling that the transaction has been finished.

  $c->on_finish(sub {
    my $self = shift;
  });

=head2 C<on_message>

  $c = $c->on_message(sub {...});

Receive messages via WebSocket, only works if there is currently a WebSocket
connection in progress.

  $c->on_message(sub {
    my ($self, $message) = @_;
  });

=head2 C<param>

  my @names = $c->param;
  my $foo   = $c->param('foo');
  my @foo   = $c->param('foo');
  $c        = $c->param(foo => 'ba;r');

Access GET/POST parameters and route captures.

  # Only GET parameters
  my $foo = $c->req->url->query->param('foo');

  # Only GET and POST parameters
  my $foo = $c->req->param('foo');

=head2 C<redirect_to>

  $c = $c->redirect_to('named');
  $c = $c->redirect_to('named', foo => 'bar');
  $c = $c->redirect_to('/path');
  $c = $c->redirect_to('http://127.0.0.1/foo/bar');

Prepare a C<302> redirect response.

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

=head2 C<render_data>

  $c->render_data($bits);

Render the given content as raw bytes, similar to C<render_text> but data
will not be encoded.

=head2 C<render_exception>

  $c->render_exception('Oops!');
  $c->render_exception(Mojo::Exception->new('Oops!'));

Render the exception template C<exception.html.$handler> and set the response
status code to C<500>.

=head2 C<render_inner>

  my $output = $c->render_inner;
  my $output = $c->render_inner('content');
  my $output = $c->render_inner(content => 'Hello world!');
  my $output = $c->render_inner(content => sub { 'Hello world!' });

Contains partial rendered templates, used for the renderers C<layout> and
C<extends> features.

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
    
Render the not found template C<not_found.html.$handler> and set the response
status code to C<404>.

=head2 C<render_partial>

  my $output = $c->render_partial('menubar');
  my $output = $c->render_partial('menubar', format => 'txt');
    
Same as C<render> but returns the rendered result.

=head2 C<render_static>

  $c->render_static('images/logo.png');
  $c->render_static('../lib/MyApp.pm');

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

  $c->rendered;

Finalize response and run C<after_dispatch> plugin hook.

=head2 C<req>

  my $req = $c->req;

Alias for C<$c-E<gt>tx-E<gt>req>.
Usually refers to a L<Mojo::Message::Request> object.

=head2 C<res>

  my $res = $c->res;

Alias for C<$c-E<gt>tx-E<gt>res>.
Usually refers to a L<Mojo::Message::Response> object.

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

Persistent data storage, by default stored in a signed cookie.
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

=head2 C<url_for>

  my $url = $c->url_for;
  my $url = $c->url_for(controller => 'bar', action => 'baz');
  my $url = $c->url_for('named', controller => 'bar', action => 'baz');
  my $url = $c->url_for('/perldoc');
  my $url = $c->url_for('http://mojolicio.us/perldoc');

Generate a portable L<Mojo::URL> object with base for a route, path or URL.

=head2 C<write>

  $c->write;
  $c->write('Hello!');
  $c->write(sub {...});
  $c->write('Hello!', sub {...});

Write dynamic content matching the corresponding C<Content-Length> header
chunk wise, the optional drain callback will be invoked once all data has
been written to the kernel send buffer or equivalent.

  $c->res->headers->content_length(6);
  $c->write('Hel');
  $c->write('lo!');

=head2 C<write_chunk>

  $c->write_chunk;
  $c->write_chunk('Hello!');
  $c->write_chunk(sub {...});
  $c->write_chunk('Hello!', sub {...});

Write dynamic content chunk wise with the C<chunked> C<Transfer-Encoding>
which doesn't require a C<Content-Length> header, the optional drain callback
will be invoked once all data has been written to the kernel send buffer or
equivalent.

  $c->write_chunk('Hel');
  $c->write_chunk('lo!');
  $c->write_chunk('');

An empty chunk marks the end of the stream.

  3
  Hel
  3
  lo!
  0

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
