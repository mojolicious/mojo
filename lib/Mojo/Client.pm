package Mojo::Client;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::CookieJar;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Parameters;
use Mojo::Server::Daemon;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::Util qw/encode url_escape/;
use Mojo::URL;
use Scalar::Util 'weaken';

# Debug
use constant DEBUG => $ENV{MOJO_CLIENT_DEBUG} || 0;

has [qw/app cert http_proxy https_proxy key no_proxy on_start tx/];
has cookie_jar => sub { Mojo::CookieJar->new };
has ioloop     => sub { Mojo::IOLoop->new };
has keep_alive_timeout => 15;
has log                => sub { Mojo::Log->new };
has managed            => 1;
has max_connections    => 5;
has max_redirects      => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has user_agent         => 'Mojolicious (Perl)';
has websocket_timeout  => 300;

# Singleton
our $CLIENT;

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
BEGIN {
  warn <<EOF;
Mojo::Client is DEPRECATED in favor of Mojo::UserAgent!!!
EOF
}

# Make sure we leave a clean ioloop behind
sub DESTROY {
  my $self = shift;

  # Loop
  return unless my $loop = $self->ioloop;

  # Cleanup active connections
  my $cs = $self->{_cs} || {};
  $loop->drop($_) for keys %$cs;

  # Cleanup keep alive connections
  my $cache = $self->{_cache} || [];
  for my $cached (@$cache) {
    $loop->drop($cached->[1]);
  }
}

sub async {
  my $self = shift;
  my $clone = $self->{_async} ||= $self->clone;
  $clone->ioloop(
      Mojo::IOLoop->singleton->is_running
    ? Mojo::IOLoop->singleton
    : $self->ioloop
  );
  $clone->managed(0);
  $clone->{_server} = $self->{_server};
  $clone->{_port}   = $self->{_port};
  return $clone;
}

sub build_form_tx {
  my $self = shift;

  # URL
  my $url = shift;

  # Callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

  # Encoding
  my $encoding = shift;

  # Form
  my $form = ref $encoding ? $encoding : shift;
  $encoding = undef if ref $encoding;

  # Parameters
  my $params = Mojo::Parameters->new;
  $params->charset($encoding) if defined $encoding;
  my $multipart;
  for my $name (sort keys %$form) {

    # Array
    if (ref $form->{$name} eq 'ARRAY') {
      $params->append($name, $_) for @{$form->{$name}};
    }

    # Hash
    elsif (ref $form->{$name} eq 'HASH') {
      my $hash = $form->{$name};

      # Enforce "multipart/form-data"
      $multipart = 1;

      # File
      if (my $file = $hash->{file}) {

        # Upgrade
        $file = $hash->{file} = Mojo::Asset::File->new(path => $file)
          unless ref $file;

        # Filename
        $hash->{filename} ||= $file->path if $file->can('path');
      }

      # Memory
      elsif (defined(my $content = delete $hash->{content})) {
        $hash->{file} = Mojo::Asset::Memory->new->add_chunk($content);
      }

      # Content-Type
      $hash->{'Content-Type'} ||= 'application/octet-stream';

      # Append
      push @{$params->params}, $name, $hash;
    }

    # Single value
    else { $params->append($name, $form->{$name}) }
  }

  # New transaction
  my $tx = $self->build_tx(POST => $url);

  # Request
  my $req = $tx->req;

  # Headers
  my $headers = $req->headers;
  $headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  # Multipart
  $headers->content_type('multipart/form-data') if $multipart;
  my $type = $headers->content_type || '';
  if ($type eq 'multipart/form-data') {

    # Formdata
    my $form = $params->to_hash;

    # Parts
    my @parts;
    foreach my $name (sort keys %$form) {

      # Part
      my $part = Mojo::Content::Single->new;

      # Headers
      my $h = $part->headers;

      # Form
      my $f = $form->{$name};

      # File
      my $filename;
      if (ref $f eq 'HASH') {

        # Filename
        $filename = delete $f->{filename} || $name;
        encode $encoding, $filename if $encoding;
        url_escape $filename, $Mojo::URL::UNRESERVED;

        # Asset
        $part->asset(delete $f->{file});

        # Headers
        $h->from_hash($f);
      }

      # Fields
      else {

        # Values
        my $chunk = join ',', ref $f ? @$f : ($f);
        encode $encoding, $chunk if $encoding;
        $part->asset->add_chunk($chunk);

        # Content-Type
        my $type = 'text/plain';
        $type .= qq/;charset=$encoding/ if $encoding;
        $h->content_type($type);
      }

      # Content-Disposition
      encode $encoding, $name if $encoding;
      url_escape $name, $Mojo::URL::UNRESERVED;
      my $disposition = qq/form-data; name="$name"/;
      $disposition .= qq/; filename="$filename"/ if $filename;
      $h->content_disposition($disposition);

      push @parts, $part;
    }

    # Multipart content
    my $content = Mojo::Content::MultiPart->new;
    $headers->content_type('multipart/form-data');
    $content->headers($headers);
    $content->parts(\@parts);

    # Add content to transaction
    $req->content($content);
  }

  # Urlencoded
  else {
    $headers->content_type('application/x-www-form-urlencoded');
    $req->body($params->to_string);
  }

  return $tx unless wantarray;
  return $tx, $cb;
}

sub build_tx {
  my $self = shift;

  # New transaction
  my $tx = Mojo::Transaction::HTTP->new;

  # Request
  my $req = $tx->req;

  # Method
  $req->method(shift);

  # URL
  my $url = shift;
  $url = "http://$url" unless $url =~ /^\/|\:\/\//;
  $req->url->parse($url);

  # Callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

  # Body
  $req->body(pop @_)
    if @_ & 1 == 1 && ref $_[0] ne 'HASH' || ref $_[-2] eq 'HASH';

  # Headers
  $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

  return $tx unless wantarray;
  return $tx, $cb;
}

sub build_websocket_tx {
  my $self = shift;

  # New WebSocket
  my ($tx, $cb) = $self->build_tx(GET => @_);

  # Request
  my $req = $tx->req;

  # URL
  my $url = $req->url;

  # Scheme
  my $abs = $url->to_abs;
  if (my $scheme = $abs->scheme) {
    $scheme = $scheme eq 'wss' ? 'https' : 'http';
    $req->url($abs->scheme($scheme));
  }

  # Handshake
  Mojo::Transaction::WebSocket->new(handshake => $tx)->client_handshake;

  return $tx unless wantarray;
  return $tx, $cb;
}

sub clone {
  my $self = shift;

  # Clone
  my $clone = $self->new;
  $clone->app($self->app);
  $clone->log($self->log);
  $clone->on_start($self->on_start);
  $clone->cert($self->cert);
  $clone->key($self->key);
  $clone->http_proxy($self->http_proxy);
  $clone->https_proxy($self->https_proxy);
  $clone->no_proxy($self->no_proxy);
  $clone->user_agent($self->user_agent);
  $clone->cookie_jar($self->cookie_jar);
  $clone->keep_alive_timeout($self->keep_alive_timeout);
  $clone->max_connections($self->max_connections);
  $clone->max_redirects($self->max_redirects);
  $clone->websocket_timeout($self->websocket_timeout);

  return $clone;
}

sub delete {
  my $self = shift;
  return $self->_tx_queue_or_start($self->build_tx('DELETE', @_));
}

sub detect_proxy {
  my $self = shift;
  $self->http_proxy($ENV{HTTP_PROXY}   || $ENV{http_proxy});
  $self->https_proxy($ENV{HTTPS_PROXY} || $ENV{https_proxy});
  if (my $no = $ENV{NO_PROXY} || $ENV{no_proxy}) {
    $self->no_proxy([split /,/, $no]);
  }
  return $self;
}

sub finish {
  my $self = shift;

  # Transaction
  my $tx = $self->tx;

  # WebSocket
  croak 'Transaction is not a WebSocket' unless $tx->is_websocket;

  # Finish
  $tx->finish;
}

sub get {
  my $self = shift;
  return $self->_tx_queue_or_start($self->build_tx('GET', @_));
}

sub head {
  my $self = shift;
  return $self->_tx_queue_or_start($self->build_tx('HEAD', @_));
}

sub need_proxy {
  my ($self, $host) = @_;

  # No proxy list
  return 1 unless my $no = $self->no_proxy;

  # No proxy needed
  $host =~ /\Q$_\E$/ and return for @$no;

  # Proxy needed
  return 1;
}

sub on_finish {
  my $self = shift;

  # Transaction
  my $tx = $self->tx;

  # WebSocket
  croak 'Transaction is not a WebSocket' unless $tx->is_websocket;

  # Callback
  my $cb = shift;

  # Weaken
  weaken $self;
  weaken $tx;

  # Connection finished
  $tx->on_finish(sub { shift; local $self->{tx} = $tx; $self->$cb(@_) });
}

sub on_message {
  my $self = shift;

  # Transaction
  my $tx = $self->tx;

  # WebSocket
  croak 'Transaction is not a WebSocket' unless $tx->is_websocket;

  # Callback
  my $cb = shift;

  # Weaken
  weaken $self;
  weaken $tx;

  # Receive
  $tx->on_message(sub { shift; local $self->{tx} = $tx; $self->$cb(@_) });

  return $self;
}

sub post {
  my $self = shift;
  return $self->_tx_queue_or_start($self->build_tx('POST', @_));
}

sub post_form {
  my $self = shift;
  return $self->_tx_queue_or_start($self->build_form_tx(@_));
}

sub put {
  my $self = shift;
  $self->_tx_queue_or_start($self->build_tx('PUT', @_));
}

sub queue {
  my $self = shift;

  # Callback
  my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

  # Queue transactions
  my $queue = $self->{_queue} ||= [];
  push @$queue, [$_, $cb] for @_;

  return $self;
}

sub req { shift->tx->req(@_) }
sub res { shift->tx->res(@_) }

sub singleton { $CLIENT ||= shift->new(@_) }

sub send_message {
  my ($self, $message, $cb) = @_;

  # Transaction
  my $tx = $self->tx;

  # WebSocket
  croak 'Transaction is not a WebSocket' unless $tx->is_websocket;

  # Weaken
  weaken $self;
  weaken $tx;

  # Send
  $tx->send_message(
    $message,
    sub {

      # Cleanup
      shift;
      local $self->{tx} = $tx;

      $self->$cb(@_) if $cb;
    }
  );

  return $self;
}

sub start {
  my $self = shift;

  # Queue
  $self->queue(@_) if @_;
  my $queue = delete $self->{_queue} || [];

  # Process sync subrequests in new client
  if ($self->managed && $self->{_processing}) {
    my $clone = $self->clone;
    $clone->queue(@$_) for @$queue;
    return $clone->start;
  }

  # Add async transactions from queue
  else { $self->_tx_start(@$_) for @$queue }

  # Process sync requests
  if ($self->managed && $self->{_processing}) {

    # Start loop
    my $loop = $self->ioloop;
    $loop->start;

    # Cleanup
    $loop->one_tick(0);
  }

  return $self;
}

sub test_server {
  my ($self, $protocol) = @_;

  # Server
  unless ($self->{_port}) {
    my $server = $self->{_server} =
      Mojo::Server::Daemon->new(ioloop => $self->ioloop, silent => 1);
    my $port = $self->{_port} = $self->ioloop->generate_port;
    die "Couldn't find a free TCP port for testing.\n" unless $port;
    $self->{_protocol} = $protocol ||= 'http';
    $server->listen(["$protocol://*:$port"]);
    $server->prepare_ioloop;
  }

  # Application
  my $server = $self->{_server};
  delete $server->{app};
  my $app = $self->app;
  ref $app ? $server->app($app) : $server->app_class($app);
  $self->log($server->app->log);

  return $self->{_port};
}

sub websocket {
  my $self = shift;
  $self->_tx_queue_or_start($self->build_websocket_tx(@_));
}

sub _cache {
  my ($self, $name, $id) = @_;

  # Cache
  my $cache = $self->{_cache} ||= [];

  # Enqueue
  if ($id) {

    # Limit keep alive connections
    my $max = $self->max_connections;
    while (@$cache > $max) {
      my $cached = shift @$cache;
      $self->_drop($cached->[1]);
    }

    # Add to cache
    push @$cache, [$name, $id] if $max;

    return $self;
  }

  # Loop
  my $loop = $self->ioloop;

  # Dequeue
  my $result;
  my @cache;
  for my $cached (@$cache) {

    # Search for name or id
    if (!$result && ($cached->[1] eq $name || $cached->[0] eq $name)) {

      # Result
      my $id = $cached->[1];

      # Test connection
      if ($loop->test($id)) { $result = $id }

      # Drop corrupted connection
      else { $loop->drop($id) }
    }

    # Cache again
    else { push @cache, $cached }
  }
  $self->{_cache} = \@cache;

  return $result;
}

sub _connect {
  my ($self, $tx, $cb) = @_;

  # Check for specific connection id
  my $id = $tx->connection;

  # Loop
  my $loop = $self->ioloop;

  # Info
  my ($scheme, $address, $port) = $self->_tx_info($tx);

  # Weaken
  weaken $self;

  # Keep alive connection
  $id ||= $self->_cache("$scheme:$address:$port");
  if ($id && !ref $id) {

    # Debug
    warn "KEEP ALIVE CONNECTION ($scheme:$address:$port)\n" if DEBUG;

    # Add new connection
    $self->{_cs}->{$id} = {cb => $cb, tx => $tx};

    # Kept alive
    $tx->kept_alive(1);

    # Connected
    $self->_connected($id);
  }

  # New connection
  else {

    # TLS/WebSocket proxy
    unless (($tx->req->method || '') eq 'CONNECT') {

      # CONNECT request to proxy required
      return if $self->_connect_proxy($tx, $cb);
    }

    # Debug
    warn "NEW CONNECTION ($scheme:$address:$port)\n" if DEBUG;

    # Connect
    $id = $loop->connect(
      address  => $address,
      port     => $port,
      handle   => $id,
      tls      => $scheme eq 'https' ? 1 : 0,
      tls_cert => $self->cert,
      tls_key  => $self->key,
      on_connect => sub { $self->_connected($_[1]) }
    );

    # Add new connection
    $self->{_cs}->{$id} = {cb => $cb, tx => $tx};
  }

  # Callbacks
  $loop->on_error($id => sub { $self->_error(@_) });
  $loop->on_hup($id => sub { $self->_hup(@_) });
  $loop->on_read($id => sub { $self->_read(@_) });

  return $id;
}

sub _connect_proxy {
  my ($self, $old, $cb) = @_;

  # Request
  my $req = $old->req;

  # URL
  my $url = $req->url;

  # Proxy
  return unless my $proxy = $req->proxy;

  # WebSocket and/or HTTPS
  return
    unless ($req->headers->upgrade || '') eq 'WebSocket'
    || ($url->scheme || '') eq 'https';

  # CONNECT request
  my $new = $self->build_tx(CONNECT => $url->clone);
  $new->req->proxy($proxy);

  # Start CONNECT request
  $self->_tx_start(
    $new => sub {
      my ($self, $tx) = @_;

      # CONNECT failed
      unless (($tx->res->code || '') eq '200') {
        $old->req->error('Proxy connection failed.');
        $self->_tx_finish($old, $cb);
        return;
      }

      # TLS upgrade
      if ($tx->req->url->scheme eq 'https') {

        # Connection from keep alive cache
        return unless my $old_id = $tx->connection;

        # Start TLS
        my $new_id = $self->ioloop->start_tls($old_id);

        # Cleanup
        $old->req->proxy(undef);
        delete $self->{_cs}->{$old_id};
        $tx->connection($new_id);
      }

      # Share connection
      $old->connection($tx->connection);

      # Start real transaction
      $self->_tx_start($old, $cb);
    }
  );

  return 1;
}

sub _connected {
  my ($self, $id) = @_;

  # Loop
  my $loop = $self->ioloop;

  # Transaction
  my $tx = $self->{_cs}->{$id}->{tx};

  # Connection
  $tx->connection($id);

  # Store connection information in transaction
  my $local = $loop->local_info($id);
  $tx->local_address($local->{address});
  $tx->local_port($local->{port});
  my $remote = $loop->remote_info($id);
  $tx->remote_address($remote->{address});
  $tx->remote_port($remote->{port});

  # Keep alive timeout
  $loop->connection_timeout($id => $self->keep_alive_timeout);

  # Write
  $self->_write($id);
}

sub _drop {
  my ($self, $id, $close) = @_;

  # Drop connection
  my $c = delete $self->{_cs}->{$id};

  # Transaction
  my $tx = $c->{tx};
  if (!$close && $tx && $tx->keep_alive && !$tx->error) {

    # Keep non-CONNECTed connection alive
    $self->_cache(join(':', $self->_tx_info($tx)), $id)
      unless (($tx->req->method || '') =~ /^connect$/i
      && ($tx->res->code || '') eq '200');

    # Still active
    return;
  }

  # Connection close
  $self->_cache($id);
  $self->ioloop->drop($id);
}

sub _error {
  my ($self, $loop, $id, $error) = @_;

  # Transaction
  if (my $tx = $self->{_cs}->{$id}->{tx}) { $tx->res->error($error) }

  # Log
  $self->log->error($error);

  # Finished
  $self->_handle($id, $error);
}

sub _handle {
  my ($self, $id, $close) = @_;

  # Connection
  my $c = $self->{_cs}->{$id};

  # Old transaction
  my $old = $c->{tx};

  # WebSocket
  if ($old && $old->is_websocket) {

    # Finish transaction
    $old->client_close;

    # Counter
    $self->{_processing} -= 1;

    # Cleanup
    delete $self->{_cs}->{$id};
    $self->_drop($id, $close);
  }

  # Upgrade connection to WebSocket
  elsif ($old && (my $new = $self->_upgrade($id))) {

    # Finish
    $self->_tx_finish($new, $c->{cb});

    # Leftovers
    $new->client_read($old->res->leftovers);
  }

  # Normal connection
  else {

    # Cleanup
    $self->_drop($id, $close);

    # Idle connection
    return unless $old;

    # Extract cookies
    if (my $jar = $self->cookie_jar) { $jar->extract($old) }

    # Counter
    $self->{_processing} -= 1;

    # Redirect or callback
    $self->_tx_finish($new || $old, $c->{cb})
      unless $self->_redirect($c, $old);
  }

  # Cleanup
  $self->ioloop->stop if $self->managed && !$self->{_processing};
}

sub _hup { shift->_handle(pop, 1) }

sub _read {
  my ($self, $loop, $id, $chunk) = @_;

  # Debug
  warn "< $chunk\n" if DEBUG;

  # Connection
  return unless my $c = $self->{_cs}->{$id};

  # Transaction
  if (my $tx = $c->{tx}) {

    # Read
    $tx->client_read($chunk);

    # Finish
    if ($tx->is_done) { $self->_handle($id) }

    # Writing
    elsif ($c->{tx}->is_writing) { $self->_write($id) }

    return;
  }

  # Corrupted connection
  $self->_drop($id);
}

sub _redirect {
  my ($self, $c, $old) = @_;

  # Response
  my $res = $old->res;

  # Code
  return unless $res->is_status_class('300');
  return if $res->code == 305;

  # Location
  return unless my $location = $res->headers->location;
  $location = Mojo::URL->new($location);

  # Request
  my $req = $old->req;

  # Fix broken location without authority and/or scheme
  my $url = $req->url;
  $location->authority($url->authority) unless $location->authority;
  $location->scheme($url->scheme)       unless $location->scheme;

  # Method
  my $method = $req->method;
  $method = 'GET' unless $method =~ /^GET|HEAD$/i;

  # Max redirects
  my $r = $c->{redirects} || 0;
  my $max = $self->max_redirects;
  return unless $r < $max;

  # New transaction
  my $new = Mojo::Transaction::HTTP->new;
  $new->req->method($method)->url($location);
  $new->previous($old);

  # Start redirected request
  return 1 unless my $new_id = $self->_tx_start($new, $c->{cb});

  # Create new connection
  $self->{_cs}->{$new_id}->{redirects} = $r + 1;

  # Redirecting
  return 1;
}

sub _tx_finish {
  my ($self, $tx, $cb) = @_;

  # Response
  my $res = $tx->res;

  # 400/500
  $res->error($res->message, $res->code)
    if $res->is_status_class(400) || $res->is_status_class(500);

  # Callback
  return unless $cb;
  local $self->{tx} = $tx;
  $self->$cb($tx);
}

sub _tx_info {
  my ($self, $tx) = @_;

  # Request
  my $req = $tx->req;

  # URL
  my $url = $req->url;

  # Info
  my $scheme = $url->scheme || 'http';
  my $host   = $url->ihost;
  my $port   = $url->port;

  # Proxy info
  if (my $proxy = $req->proxy) {
    $scheme = $proxy->scheme;
    $host   = $proxy->ihost;
    $port   = $proxy->port;
  }

  # Default port
  $port ||= $scheme eq 'https' ? 443 : 80;

  return ($scheme, $host, $port);
}

sub _tx_queue_or_start {
  my ($self, $tx, $cb) = @_;

  # Async
  return $self->start($tx, $cb) unless $self->managed;

  # Quick start
  $self->start($tx, sub { $tx = $_[1] }) and return $tx unless $cb;

  # Queue transaction with callback
  $self->queue($tx, $cb);
}

sub _tx_start {
  my ($self, $tx, $cb) = @_;

  # Callback needed
  croak 'Unmanaged client requests require a callback'
    if !$self->managed && !$cb;

  # Embedded server
  if ($self->app) {
    my $req = $tx->req;
    my $url = $req->url->to_abs;

    # Relative
    unless ($url->host) {
      $url->scheme($self->{_protocol});
      $url->host('localhost');
      $url->port($self->test_server);
      $req->url($url);
    }
  }

  # Request
  my $req = $tx->req;

  # URL
  my $url = $req->url;

  # Scheme
  my $scheme = $url->scheme || '';

  # Detect proxy
  $self->detect_proxy if $ENV{MOJO_PROXY};

  # Proxy
  if ($self->need_proxy($url->host)) {

    # HTTP proxy
    if (my $proxy = $self->http_proxy) {
      $req->proxy($proxy) if !$req->proxy && $scheme eq 'http';
    }

    # HTTPS proxy
    if (my $proxy = $self->https_proxy) {
      $req->proxy($proxy) if !$req->proxy && $scheme eq 'https';
    }
  }

  # We identify ourself
  my $headers = $req->headers;
  $headers->user_agent($self->user_agent) unless $headers->user_agent;

  # Inject cookies
  if (my $jar = $self->cookie_jar) { $jar->inject($tx) }

  # Start
  if (my $start = $self->on_start) { $self->$start($tx) }

  # Connect
  return unless my $id = $self->_connect($tx, $cb);

  # Weaken
  weaken $self;

  # Resume callback
  $tx->on_resume(sub { $self->_write($id) });

  # Counter
  $self->{_processing} ||= 0;
  $self->{_processing} += 1;

  return $id;
}

sub _upgrade {
  my ($self, $id) = @_;

  # Connection
  my $c = $self->{_cs}->{$id};

  # Last transaction
  my $old = $c->{tx};

  # Request
  my $req = $old->req;

  # Headers
  my $headers = $req->headers;

  # No upgrade request
  return unless $headers->upgrade;

  # Response
  my $res = $old->res;

  # Handshake failed
  return unless ($res->code || '') eq '101';

  # Upgrade to WebSocket transaction
  my $new = Mojo::Transaction::WebSocket->new(handshake => $old);
  $new->kept_alive($old->kept_alive);

  # WebSocket challenge
  $res->error('WebSocket challenge failed.') and return
    unless $new->client_challenge;
  $c->{tx} = $new;

  # Upgrade connection timeout
  $self->ioloop->connection_timeout($id, $self->websocket_timeout);

  # Weaken
  weaken $self;

  # Resume callback
  $new->on_resume(sub { $self->_write($id) });

  return $new;
}

sub _write {
  my ($self, $id) = @_;

  # Connection
  return unless my $c = $self->{_cs}->{$id};

  # Transaction
  return unless my $tx = $c->{tx};

  # Not writing
  return unless $tx->is_writing;

  # Chunk
  my $chunk = $c->{tx}->client_write;

  # Still writing
  my $cb;
  if ($tx->is_writing) {

    # Weaken
    weaken $self;

    $cb = sub { $self->_write($id) };
  }

  # Write
  $self->ioloop->write($id, $chunk, $cb);

  # Finish
  $self->_handle($id) if $tx->is_done;

  # Debug
  warn "> $chunk\n" if DEBUG;
}

1;
__END__

=head1 NAME

Mojo::Client - DEPRECATED!

=head1 SYNOPSIS

  use Mojo::UserAgent;

=head1 DESCRIPTION

This module has been DEPRECATED in favor of L<Mojo::UserAgent>!

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
