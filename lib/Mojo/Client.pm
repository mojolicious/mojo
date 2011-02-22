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

# "You can't let a single bad experience scare you away from drugs."
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
*async = sub {
  warn <<EOF;
Mojo::Client->async is DEPRECATED in favor of Mojo::Client->managed!!!
EOF
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
};

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

# "Ah, alcohol and night-swimming. It's a winning combination."
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

# "Homer, it's easy to criticize.
#  Fun, too."
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

# "The only thing I asked you to do for this party was put on clothes,
#  and you didn't do it."
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

# "'What are you lookin at?' - the innocent words of a drunken child."
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

# "And I gave that man directions, even though I didn't know the way,
#  because that's the kind of guy I am this week."
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

# "Wow, Barney. You brought a whole beer keg.
#  Yeah... where do I fill it up?"
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

# "Olive oil? Asparagus? If your mother wasn't so fancy,
#  we could just shop at the gas station like normal people."
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

# "It's like my dad always said: eventually, everybody gets shot."
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

# "Are we there yet?
#  No
#  Are we there yet?
#  No
#  Are we there yet?
#  No
#  ...Where are we going?"
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

# "Where on my badge does it say anything about protecting people?
#  Uh, second word, chief."
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

# "Hey, Weener Boy... where do you think you're going?"
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

# "I don't mind being called a liar when I'm lying, or about to lie,
#  or just finished lying, but NOT WHEN I'M TELLING THE TRUTH."
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

# "Mrs. Simpson, bathroom is not for customers.
#  Please use the crack house across the street."
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

# "No children have ever meddled with the Republican Party and lived to tell
#  about it."
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

# "Have you ever seen that Blue Man Group? Total ripoff of the Smurfs.
#  And the Smurfs, well, they SUCK."
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

# "Oh, I'm in no condition to drive. Wait a minute.
#  I don't have to listen to myself. I'm drunk."
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

# "It's greeat! We can do *anything* now that Science has invented Magic."
sub _tx_start {
  my ($self, $tx, $cb) = @_;

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

  # Make sure WebSocket requests have an origin header
  my $headers = $req->headers;
  $headers->origin($url) if $headers->upgrade && !$headers->origin;

  # We identify ourself
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

# "Once the government approves something, it's no longer immoral!"
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

# "Oh well. At least we'll die doing what we love: inhaling molten rock."
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

Mojo::Client - Async IO HTTP 1.1 And WebSocket Client

=head1 SYNOPSIS

  use Mojo::Client;
  my $client = Mojo::Client->new;

  # Grab the latest Mojolicious release :)
  my $latest = 'http://latest.mojolicio.us';
  print $client->max_redirects(3)->get($latest)->res->body;

  # Quick JSON request
  my $trends = 'http://search.twitter.com/trends.json';
  print $client->get($trends)->res->json->{trends}->[0]->{name};

  # Extract data from HTML and XML resources
  print $client->get('mojolicio.us')->res->dom->at('title')->text;

  # Scrape the latest headlines from a news site
  my $news = 'http://digg.com';
  $client->max_redirects(3);
  $client->get($news)->res->dom('h3 > a.story-title')->each(sub {
    print shift->text . "\n";
  });

  # Form post with exception handling
  my $cpan   = 'http://search.cpan.org/search';
  my $search = {q => 'mojo'};
  my $tx     = $client->post_form($cpan => $search);
  if (my $res = $tx->success) { print $res->body }
  else {
    my ($message, $code) = $tx->error;
    print "Error: $message";
  }

  # TLS certificate authentication
  $client->cert('tls.crt')->key('tls.key')->get('https://mojolicio.us');
    
  # Parallel requests
  my $callback = sub { print shift->res->body };
  $client->get('http://mojolicio.us' => $callback);
  $client->get('http://search.cpan.org' => $callback);
  $client->start;

  # Websocket request
  $client->websocket('ws://websockets.org:8787' => sub {
    my $client = shift;
    $client->on_message(sub {
      my ($client, $message) = @_;
      print "$message\n";
      $client->finish;
    });
    $client->send_message('hi there!');
  })->start;

=head1 DESCRIPTION

L<Mojo::Client> is a full featured async io HTTP 1.1 and WebSocket client
with C<IPv6>, C<TLS>, C<epoll> and C<kqueue> support.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::IP> and
L<IO::Socket::SSL> are supported transparently and used if installed.

=head1 ATTRIBUTES

L<Mojo::Client> implements the following attributes.

=head2 C<app>

  my $app = $client->app;
  $client = $client->app(MyApp->new);

A Mojo application to associate this client with.
If set, local requests will be processed in this application.

=head2 C<cert>

  my $cert = $client->cert;
  $client  = $client->cert('tls.crt');

Path to TLS certificate file.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<cookie_jar>

  my $cookie_jar = $client->cookie_jar;
  $client        = $client->cookie_jar(Mojo::CookieJar->new);

Cookie jar to use for this clients requests, by default a L<Mojo::CookieJar>
object.

=head2 C<http_proxy>

  my $proxy = $client->http_proxy;
  $client   = $client->http_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTP and WebSocket requests.

=head2 C<https_proxy>

  my $proxy = $client->https_proxy;
  $client   = $client->https_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTPS and WebSocket requests.

=head2 C<ioloop>

  my $loop = $client->ioloop;
  $client  = $client->ioloop(Mojo::IOLoop->new);

Loop object to use for io operations, by default a L<Mojo::IOLoop> object
will be used.

=head2 C<keep_alive_timeout>

  my $keep_alive_timeout = $client->keep_alive_timeout;
  $client                = $client->keep_alive_timeout(15);

Timeout in seconds for keep alive between requests, defaults to C<15>.

=head2 C<key>

  my $key = $client->key;
  $client = $client->key('tls.crt');

Path to TLS key file.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<log>

  my $log = $client->log;
  $client = $client->log(Mojo::Log->new);

A L<Mojo::Log> object used for logging, by default the application log will
be used.

=head2 C<managed>

  my $managed = $client->managed;
  $client     = $client->managed(0);

Automatic L<Mojo::IOLoop> management, defaults to C<1>.
Disabling it will for example allow you to share the same event loop with
multiple clients.
Note that this attribute is EXPERIMENTAL and might change without warning!

  $client->managed(0)->get('http://mojolicio.us' => sub {
    my $client = shift;
    print shift->res->body;
    $client->ioloop->stop;
  });
  $client->ioloop->start;

=head2 C<max_connections>

  my $max_connections = $client->max_connections;
  $client             = $client->max_connections(5);

Maximum number of keep alive connections that the client will retain before
it starts closing the oldest cached ones, defaults to C<5>.

=head2 C<max_redirects>

  my $max_redirects = $client->max_redirects;
  $client           = $client->max_redirects(3);

Maximum number of redirects the client will follow before it fails, defaults
to C<0>.

=head2 C<no_proxy>

  my $no_proxy = $client->no_proxy;
  $client      = $client->no_proxy(['localhost', 'intranet.mojolicio.us']);

Domains that don't require a proxy server to be used.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<on_start>

  my $cb  = $client->on_start;
  $client = $client->on_start(sub {...});

Callback to be invoked whenever a new transaction is about to start, this
includes automatically prepared proxy C<CONNECT> requests and followed
redirects.
Note that this attribute is EXPERIMENTAL and might change without warning!

  $client->on_start(sub {
    my ($client, $tx) = @_;
    $tx->req->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head2 C<tx>

  $client->tx;

The last finished transaction, only available from callbacks, usually a
L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket> object.

=head2 C<user_agent>

  my $user_agent = $client->user_agent;
  $client        = $client->user_agent('Mojolicious');

Value for C<User-Agent> request header, defaults to C<Mojolicious (Perl)>.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<websocket_timeout>

  my $websocket_timeout = $client->websocket_timeout;
  $client               = $client->websocket_timeout(300);

Timeout in seconds for WebSockets to be idle, defaults to C<300>.

=head1 METHODS

L<Mojo::Client> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

  my $client = Mojo::Client->new;

Construct a new L<Mojo::Client> object.
Use C<singleton> if you want to share keep alive connections with other
clients.

=head2 C<build_form_tx>

  my $tx = $client->build_form_tx('http://kraih.com/foo' => {test => 123});
  my $tx = $client->build_form_tx(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123}
  );
  my $tx = $client->build_form_tx(
    'http://kraih.com/foo',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx = $client->build_form_tx(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx = $client->build_form_tx(
    'http://kraih.com/foo',
    {file => {file => '/foo/bar.txt'}}
  );
  my $tx = $client->build_form_tx(
    'http://kraih.com/foo',
    {file => {content => 'lalala'}}
  );
  my $tx = $client->build_form_tx(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}}
  );

Versatile L<Mojo::Transaction::HTTP> builder for forms.

  my $tx = $client->build_form_tx('http://kraih.com/foo' => {test => 123});
  $tx->res->body(sub { print $_[1] });
  $client->start($tx);

=head2 C<build_tx>

  my $tx = $client->build_tx(GET => 'mojolicio.us');
  my $tx = $client->build_tx(POST => 'http://mojolicio.us');
  my $tx = $client->build_tx(
    GET => 'http://kraih.com' => {Connection => 'close'}
  );
  my $tx = $client->build_tx(
    POST => 'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Versatile general purpose L<Mojo::Transaction::HTTP> builder.

  # Streaming response
  my $tx = $client->build_tx(GET => 'http://mojolicio.us');
  $tx->res->body(sub { print $_[1] });
  $client->start($tx);

  # Custom socket
  my $tx = $client->build_tx(GET => 'http://mojolicio.us');
  $tx->connection($socket);
  $client->start($tx);

=head2 C<build_websocket_tx>

  my $tx = $client->build_websocket_tx('ws://localhost:3000');

Versatile L<Mojo::Transaction::HTTP> builder for WebSocket handshakes.
An upgrade to L<Mojo::Transaction::WebSocket> will happen automatically after
a successful handshake is performed.

=head2 C<clone>

  my $clone = $client->clone;

Clone client the instance.
Note that all cloned clients have their own keep alive connection queue, so
you can quickly run out of file descriptors with too many active clients.

=head2 C<delete>

  my $tx  = $client->delete('http://kraih.com');
  my $tx  = $client->delete('http://kraih.com' => {Connection => 'close'});
  my $tx  = $client->delete(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );
  $client = $client->delete('http://kraih.com' => sub {...});
  $client = $client->delete(
    'http://kraih.com' => {Connection => 'close'} => sub {...}
  );
  $client = $client->delete(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!' => sub {...}
  );

Prepare HTTP C<DELETE> request.

  $client->delete('http://kraih.com' => sub {
    print shift->res->body;
  })->start;

The request will be performed right away and the resulting
L<Mojo::Transaction::HTTP> object returned if no callback is given.

  print $client->delete('http://kraih.com')->res->body;

=head2 C<detect_proxy>

  $client = $client->detect_proxy;

Check environment variables C<HTTP_PROXY>, C<http_proxy>, C<HTTPS_PROXY>,
C<https_proxy>, C<NO_PROXY> and C<no_proxy> for proxy information.

=head2 C<finish>

  $client->finish;

Finish the WebSocket connection, only available from callbacks.

=head2 C<get>

  my $tx  = $client->get('http://kraih.com');
  my $tx  = $client->get('http://kraih.com' => {Connection => 'close'});
  my $tx  = $client->get(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );
  $client = $client->get('http://kraih.com' => sub {...});
  $client = $client->get(
    'http://kraih.com' => {Connection => 'close'} => sub {...}
  );
  $client = $client->get(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!' => sub {...}
  );

Prepare HTTP C<GET> request.

  $client->get('http://kraih.com' => sub {
    print shift->res->body;
  })->start;

The request will be performed right away and the resulting
L<Mojo::Transaction::HTTP> object returned if no callback is given.

  print $client->get('http://kraih.com')->res->body;

=head2 C<head>

  my $tx  = $client->head('http://kraih.com');
  my $tx  = $client->head('http://kraih.com' => {Connection => 'close'});
  my $tx  = $client->head(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );
  $client = $client->head('http://kraih.com' => sub {...});
  $client = $client->head(
    'http://kraih.com' => {Connection => 'close'} => sub {...}
  );
  $client = $client->head(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!' => sub {...}
  );

Prepare HTTP C<HEAD> request.

  $client->head('http://kraih.com' => sub {
    print shift->res->headers->content_length;
  })->start;

The request will be performed right away and the resulting
L<Mojo::Transaction::HTTP> object returned if no callback is given.

  print $client->head('http://kraih.com')->res->headers->content_length;

=head2 C<need_proxy>

  my $need_proxy = $client->need_proxy('intranet.mojolicio.us');

Check if request for domain would use a proxy server.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<on_finish>

  $client->on_finish(sub {...});

Callback signaling that peer finished the WebSocket connection, only
available from callbacks.

  $client->on_finish(sub {
    my $client = shift;
  });

=head2 C<on_message>

  $client = $client->on_message(sub {...});

Receive messages via WebSocket, only available from callbacks.

  $client->on_message(sub {
    my ($client, $message) = @_;
  });

=head2 C<post>

  my $tx  = $client->post('http://kraih.com');
  my $tx  = $client->post('http://kraih.com' => {Connection => 'close'});
  my $tx  = $client->post(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );
  $client = $client->post('http://kraih.com' => sub {...});
  $client = $client->post(
    'http://kraih.com' => {Connection => 'close'} => sub {...}
  );
  $client = $client->post(
    'http://kraih.com',
    {Connection => 'close'},
    'message body',
    sub {...}
  );
  $client = $client->post(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!' => sub {...}
  );

Prepare HTTP C<POST> request.

  $client->post('http://kraih.com' => sub {
    print shift->res->body;
  })->start;

The request will be performed right away and the resulting
L<Mojo::Transaction::HTTP> object returned if no callback is given.

  print $client->post('http://kraih.com')->res->body;

=head2 C<post_form>

  my $tx  = $client->post_form('http://kraih.com/foo' => {test => 123});
  my $tx  = $client->post_form(
    'http://kraih.com/foo'
    'UTF-8',
    {test => 123}
  );
  my $tx  = $client->post_form(
    'http://kraih.com/foo',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx  = $client->post_form(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx = $client->post_form(
    'http://kraih.com/foo',
    {file => {file => '/foo/bar.txt'}}
  );
  my $tx= $client->post_form(
    'http://kraih.com/foo',
    {file => {content => 'lalala'}}
  );
  my $tx = $client->post_form(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}}
  );
  $client = $client->post_form('/foo' => {test => 123}, sub {...});
  $client = $client->post_form(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    sub {...}
  );
  $client = $client->post_form(
    'http://kraih.com/foo',
    {test => 123},
    {Connection => 'close'},
    sub {...}
  );
  $client = $client->post_form(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {Connection => 'close'},
    sub {...}
  );
  $client = $client->post_form(
    'http://kraih.com/foo',
    {file => {file => '/foo/bar.txt'}},
    sub {...}
  );
  $client = $client->post_form(
    'http://kraih.com/foo',
    {file => {content => 'lalala'}},
    sub {...}
  );
  $client = $client->post_form(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}},
    sub {...}
  );

Prepare HTTP C<POST> request with form data.

  $client->post_form('http://kraih.com' => {q => 'test'} => sub {
    print shift->res->body;
  })->start;

The request will be performed right away and the resulting
L<Mojo::Transaction::HTTP> object returned if no callback is given.

  print $client->post_form('http://kraih.com' => {q => 'test'})->res->body;

=head2 C<put>

  my $tx  = $client->put('http://kraih.com');
  my $tx  = $client->put('http://kraih.com' => {Connection => 'close'});
  my $tx  = $client->put(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );
  $client = $client->put('http://kraih.com' => sub {...});
  $client = $client->put(
    'http://kraih.com' => {Connection => 'close'} => sub {...}
  );
  $client = $client->put(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!' => sub {...}
  );

Prepare HTTP C<PUT> request.

  $client->put('http://kraih.com' => sub {
    print shift->res->body;
  })->start;

The request will be performed right away and the resulting
L<Mojo::Transaction::HTTP> object returned if no callback is given.

  print $client->put('http://kraih.com')->res->body;

=head2 C<queue>

  $client = $client->queue(@transactions);
  $client = $client->queue(@transactions => sub {...});

Queue a list of transactions for processing.

=head2 C<req>

  my $req = $client->req;

The request object of the last finished transaction, only available from
callbacks, usually a L<Mojo::Message::Request> object.

=head2 C<res>

  my $res = $client->res;

The response object of the last finished transaction, only available from
callbacks, usually a L<Mojo::Message::Response> object.

=head2 C<singleton>

  my $client = Mojo::Client->singleton;

The global client object, used to access a single shared client instance from
everywhere inside the process.

=head2 C<send_message>

  $client = $client->send_message('Hi there!');
  $client = $client->send_message('Hi there!', sub {...});

Send a message via WebSocket, only available from callbacks.

=head2 C<start>

  $client = $client->start;
  $client = $client->start(@transactions);
  $client = $client->start(@transactions => sub {...});

Start processing all queued transactions.

=head2 C<test_server>

  my $port = $client->test_server;
  my $port = $client->test_server('https');

Starts a test server for C<app> if neccessary and returns the port number.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<websocket>

  $client = $client->websocket('ws://localhost:3000' => sub {...});
  $client = $client->websocket(
    'ws://localhost:3000' => {'User-Agent' => 'Agent 1.0'} => sub {...}
  );

Open a WebSocket connection with transparent handshake.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
