package Mojo::UserAgent;
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
use constant DEBUG => $ENV{MOJO_USERAGENT_DEBUG} || 0;

# "You can't let a single bad experience scare you away from drugs."
has [qw/app http_proxy https_proxy no_proxy on_start/];
has cert       => sub { $ENV{MOJO_CERT_FILE} };
has cookie_jar => sub { Mojo::CookieJar->new };
has ioloop     => sub { Mojo::IOLoop->new };
has keep_alive_timeout => 15;
has key                => sub { $ENV{MOJO_KEY_FILE} };
has log                => sub { Mojo::Log->new };
has max_connections    => 5;
has max_redirects      => sub { $ENV{MOJO_MAX_REDIRECTS} || 0 };
has name               => 'Mojolicious (Perl)';
has websocket_timeout  => 300;

# Make sure we leave a clean ioloop behind
sub DESTROY { shift->_cleanup }

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
  Mojo::Transaction::WebSocket->new(handshake => $tx, masked => 1)
    ->client_handshake;

  return $tx unless wantarray;
  return $tx, $cb;
}

# "The only thing I asked you to do for this party was put on clothes,
#  and you didn't do it."
sub delete {
  my $self = shift;
  return $self->start($self->build_tx('DELETE', @_));
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

# "'What are you lookin at?' - the innocent words of a drunken child."
sub get {
  my $self = shift;
  return $self->start($self->build_tx('GET', @_));
}

sub head {
  my $self = shift;
  return $self->start($self->build_tx('HEAD', @_));
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

# "Olive oil? Asparagus? If your mother wasn't so fancy,
#  we could just shop at the gas station like normal people."
sub post {
  my $self = shift;
  return $self->start($self->build_tx('POST', @_));
}

sub post_form {
  my $self = shift;
  return $self->start($self->build_form_tx(@_));
}

# "And I gave that man directions, even though I didn't know the way,
#  because that's the kind of guy I am this week."
sub put {
  my $self = shift;
  $self->start($self->build_tx('PUT', @_));
}

# "Wow, Barney. You brought a whole beer keg.
#  Yeah... where do I fill it up?"
sub start {
  my ($self, $tx, $cb) = @_;

  # Default loop
  $self->{_loop} ||= $self->ioloop;

  # Non-blocking
  if ($cb) {

    # Debug
    warn "NEW NON-BLOCKING REQUEST\n" if DEBUG;

    # Switch to non-blocking
    $self->_switch_non_blocking unless $self->{_nb};

    # Start
    return $self->_start_tx($tx, $cb);
  }

  # Debug
  warn "NEW BLOCKING REQUEST\n" if DEBUG;

  # Switch to blocking
  $self->_switch_blocking if $self->{_nb};

  # Quick start
  $self->_start_tx($tx, sub { $tx = $_[1] });

  # Start loop
  $self->{_loop}->start;

  # Cleanup
  $self->{_loop}->one_tick(0);

  return $tx;
}

# "It's like my dad always said: eventually, everybody gets shot."
sub test_server {
  my ($self, $protocol) = @_;

  # Server
  unless ($self->{_port}) {

    # Loop
    my $loop = $self->{_loop} || $self->ioloop;

    # Server
    my $server = $self->{_server} =
      Mojo::Server::Daemon->new(ioloop => $loop, silent => 1);

    # Port
    my $port = $self->{_port} = $loop->generate_port;
    die "Couldn't find a free TCP port for testing.\n" unless $port;

    # Listen
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
  $self->start($self->build_websocket_tx(@_));
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
  my $loop = $self->{_loop};

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

sub _cleanup {
  my $self = shift;

  # Loop
  return unless my $loop = $self->{_loop};

  # Stop server
  delete $self->{_port};
  delete $self->{_server};

  # Debug
  warn "DROPPING ALL CONNECTIONS\n" if DEBUG;

  # Cleanup active connections
  my $cs = $self->{_cs} || {};
  $loop->drop($_) for keys %$cs;

  # Cleanup keep alive connections
  my $cache = $self->{_cache} || [];
  for my $cached (@$cache) {
    $loop->drop($cached->[1]);
  }
}

# "Where on my badge does it say anything about protecting people?
#  Uh, second word, chief."
sub _connect {
  my ($self, $tx, $cb) = @_;

  # Check for specific connection id
  my $id = $tx->connection;

  # Loop
  my $loop = $self->{_loop};

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
    unless ($req->headers->upgrade || '') eq 'websocket'
    || ($url->scheme || '') eq 'https';

  # CONNECT request
  my $new = $self->build_tx(CONNECT => $url->clone);
  $new->req->proxy($proxy);

  # Start CONNECT request
  $self->_start_tx(
    $new => sub {
      my ($self, $tx) = @_;

      # CONNECT failed
      unless (($tx->res->code || '') eq '200') {
        $old->req->error('Proxy connection failed.');
        $self->_finish_tx($old, $cb);
        return;
      }

      # TLS upgrade
      if ($tx->req->url->scheme eq 'https') {

        # Connection from keep alive cache
        return unless my $old_id = $tx->connection;

        # Start TLS
        my $new_id = $self->{_loop}->start_tls($old_id);

        # Cleanup
        $old->req->proxy(undef);
        delete $self->{_cs}->{$old_id};
        $tx->connection($new_id);
      }

      # Share connection
      $old->connection($tx->connection);

      # Start real transaction
      $self->_start_tx($old, $cb);
    }
  );

  return 1;
}

# "I don't mind being called a liar when I'm lying, or about to lie,
#  or just finished lying, but NOT WHEN I'M TELLING THE TRUTH."
sub _connected {
  my ($self, $id) = @_;

  # Loop
  my $loop = $self->{_loop};

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
  $self->{_loop}->drop($id);
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

# "Oh, I'm in no condition to drive. Wait a minute.
#  I don't have to listen to myself. I'm drunk."
sub _finish_tx {
  my ($self, $tx, $cb) = @_;

  # Response
  my $res = $tx->res;

  # 400/500
  $res->error($res->message, $res->code)
    if $res->is_status_class(400) || $res->is_status_class(500);

  # Callback
  return unless $cb;
  $self->$cb($tx);
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
    $self->_finish_tx($new, $c->{cb});

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
    $self->_finish_tx($new || $old, $c->{cb})
      unless $self->_redirect($c, $old);
  }

  # Stop loop
  $self->{_loop}->stop if !$self->{_nb} && !$self->{_processing};
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
  return 1 unless my $new_id = $self->_start_tx($new, $c->{cb});

  # Create new connection
  $self->{_cs}->{$new_id}->{redirects} = $r + 1;

  # Redirecting
  return 1;
}

# "It's greeat! We can do *anything* now that Science has invented Magic."
sub _start_tx {
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

  # We identify ourself
  my $headers = $req->headers;
  $headers->user_agent($self->name) unless $headers->user_agent;

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

sub _switch_blocking {
  my $self = shift;

  # Can't switch while processing non-blocking requests
  croak 'Non-blocking requests in progress' if $self->{_processing};

  # Debug
  warn "SWITCHING TO BLOCKING MODE\n" if DEBUG;

  # Cleanup
  $self->_cleanup;

  # Normal loop
  $self->{_loop} = $self->ioloop;
  $self->{_nb}   = 0;
}

sub _switch_non_blocking {
  my $self = shift;

  # Can't switch while processing blocking requests
  croak 'Blocking request in progress' if $self->{_processing};

  # Debug
  warn "SWITCHING TO NON-BLOCKING MODE\n" if DEBUG;

  # Cleanup
  $self->_cleanup;

  # Global loop
  $self->{_loop} = Mojo::IOLoop->singleton;
  $self->{_nb}   = 1;
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
  my $new = Mojo::Transaction::WebSocket->new(handshake => $old, masked => 1);
  $new->kept_alive($old->kept_alive);

  # WebSocket challenge
  $res->error('WebSocket challenge failed.') and return
    unless $new->client_challenge;
  $c->{tx} = $new;

  # Upgrade connection timeout
  $self->{_loop}->connection_timeout($id, $self->websocket_timeout);

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
  $self->{_loop}->write($id, $chunk, $cb);

  # Finish
  $self->_handle($id) if $tx->is_done;

  # Debug
  warn "> $chunk\n" if DEBUG;
}

1;
__END__

=head1 NAME

Mojo::UserAgent - Async IO HTTP 1.1 And WebSocket User Agent

=head1 SYNOPSIS

  use Mojo::UserAgent;
  my $ua = Mojo::UserAgent->new;

  # Grab the latest Mojolicious release :)
  my $latest = 'http://latest.mojolicio.us';
  print $ua->max_redirects(3)->get($latest)->res->body;

  # Quick JSON request
  my $trends = 'http://search.twitter.com/trends.json';
  print $ua->get($trends)->res->json->{trends}->[0]->{name};

  # Extract data from HTML and XML resources
  print $ua->get('mojolicio.us')->res->dom->at('title')->text;

  # Scrape the latest headlines from a news site
  my $news = 'http://digg.com';
  $ua->max_redirects(3);
  $ua->get($news)->res->dom('h3 > a.story-title')->each(sub {
    print shift->text . "\n";
  });

  # Form post with exception handling
  my $cpan   = 'http://search.cpan.org/search';
  my $search = {q => 'mojo'};
  my $tx     = $ua->post_form($cpan => $search);
  if (my $res = $tx->success) { print $res->body }
  else {
    my ($message, $code) = $tx->error;
    print "Error: $message";
  }

  # TLS certificate authentication
  $ua->cert('tls.crt')->key('tls.key')->get('https://mojolicio.us');

  # Websocket request
  $ua->websocket('ws://websockets.org:8787' => sub {
    my $tx = pop;
    $tx->on_finish(sub { Mojo::IOLoop->stop });
    $tx->on_message(sub {
      my ($tx, $message) = @_;
      print "$message\n";
      $tx->finish;
    });
    $tx->send_message('hi there!');
  });
  Mojo::IOLoop->start;

=head1 DESCRIPTION

L<Mojo::UserAgent> is a full featured async io HTTP 1.1 and WebSocket user
agent with C<IPv6>, C<TLS>, C<epoll> and C<kqueue> support.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::IP> and
L<IO::Socket::SSL> are supported transparently and used if installed.

=head1 ATTRIBUTES

L<Mojo::UserAgent> implements the following attributes.

=head2 C<app>

  my $app = $ua->app;
  $ua     = $ua->app(MyApp->new);

A Mojo application to associate this user agent with.
If set, local requests will be processed in this application.

=head2 C<cert>

  my $cert = $ua->cert;
  $ua      = $ua->cert('tls.crt');

Path to TLS certificate file, defaults to the value of C<MOJO_CERT_FILE>.

=head2 C<cookie_jar>

  my $cookie_jar = $ua->cookie_jar;
  $ua            = $ua->cookie_jar(Mojo::CookieJar->new);

Cookie jar to use for this user agents requests, by default a
L<Mojo::CookieJar> object.

=head2 C<http_proxy>

  my $proxy = $ua->http_proxy;
  $ua       = $ua->http_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTP and WebSocket requests.

=head2 C<https_proxy>

  my $proxy = $ua->https_proxy;
  $ua       = $ua->https_proxy('http://sri:secret@127.0.0.1:8080');

Proxy server to use for HTTPS and WebSocket requests.

=head2 C<ioloop>

  my $loop = $ua->ioloop;
  $ua      = $ua->ioloop(Mojo::IOLoop->new);

Loop object to use for blocking io operations, by default a L<Mojo::IOLoop>
object will be used.

=head2 C<keep_alive_timeout>

  my $keep_alive_timeout = $ua->keep_alive_timeout;
  $ua                    = $ua->keep_alive_timeout(15);

Timeout in seconds for keep alive between requests, defaults to C<15>.

=head2 C<key>

  my $key = $ua->key;
  $ua     = $ua->key('tls.crt');

Path to TLS key file, defaults to the value of C<MOJO_KEY_FILE>.

=head2 C<log>

  my $log = $ua->log;
  $ua     = $ua->log(Mojo::Log->new);

A L<Mojo::Log> object used for logging, by default the application log will
be used.

=head2 C<max_connections>

  my $max_connections = $ua->max_connections;
  $ua                 = $ua->max_connections(5);

Maximum number of keep alive connections that the user agent will retain
before it starts closing the oldest cached ones, defaults to C<5>.

=head2 C<max_redirects>

  my $max_redirects = $ua->max_redirects;
  $ua               = $ua->max_redirects(3);

Maximum number of redirects the user agent will follow before it fails,
defaults to the value of C<MOJO_MAX_REDIRECTS> or C<0>.

=head2 C<name>

  my $name = $ua->name;
  $ua      = $ua->name('Mojolicious');

Value for C<User-Agent> request header, defaults to C<Mojolicious (Perl)>.

=head2 C<no_proxy>

  my $no_proxy = $ua->no_proxy;
  $ua          = $ua->no_proxy(['localhost', 'intranet.mojolicio.us']);

Domains that don't require a proxy server to be used.
Note that this attribute is EXPERIMENTAL and might change without warning!

=head2 C<on_start>

  my $cb = $ua->on_start;
  $ua    = $ua->on_start(sub {...});

Callback to be invoked whenever a new transaction is about to start, this
includes automatically prepared proxy C<CONNECT> requests and followed
redirects.

  $ua->on_start(sub {
    my ($ua, $tx) = @_;
    $tx->req->headers->header('X-Bender', 'Bite my shiny metal ass!');
  });

=head2 C<websocket_timeout>

  my $websocket_timeout = $ua->websocket_timeout;
  $ua                   = $ua->websocket_timeout(300);

Timeout in seconds for WebSockets to be idle, defaults to C<300>.

=head1 METHODS

L<Mojo::UserAgent> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<build_form_tx>

  my $tx = $ua->build_form_tx('http://kraih.com/foo' => {test => 123});
  my $tx = $ua->build_form_tx(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123}
  );
  my $tx = $ua->build_form_tx(
    'http://kraih.com/foo',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx = $ua->build_form_tx(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx = $ua->build_form_tx(
    'http://kraih.com/foo',
    {file => {file => '/foo/bar.txt'}}
  );
  my $tx = $ua->build_form_tx(
    'http://kraih.com/foo',
    {file => {content => 'lalala'}}
  );
  my $tx = $ua->build_form_tx(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}}
  );

Versatile L<Mojo::Transaction::HTTP> builder for forms.

  my $tx = $ua->build_form_tx('http://kraih.com/foo' => {test => 123});
  $tx->res->body(sub { print $_[1] });
  $ua->start($tx);

=head2 C<build_tx>

  my $tx = $ua->build_tx(GET => 'mojolicio.us');
  my $tx = $ua->build_tx(POST => 'http://mojolicio.us');
  my $tx = $ua->build_tx(
    GET => 'http://kraih.com' => {Connection => 'close'}
  );
  my $tx = $ua->build_tx(
    POST => 'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Versatile general purpose L<Mojo::Transaction::HTTP> builder.

  # Streaming response
  my $tx = $ua->build_tx(GET => 'http://mojolicio.us');
  $tx->res->body(sub { print $_[1] });
  $ua->start($tx);

  # Custom socket
  my $tx = $ua->build_tx(GET => 'http://mojolicio.us');
  $tx->connection($socket);
  $ua->start($tx);

=head2 C<build_websocket_tx>

  my $tx = $ua->build_websocket_tx('ws://localhost:3000');

Versatile L<Mojo::Transaction::HTTP> builder for WebSocket handshakes.
An upgrade to L<Mojo::Transaction::WebSocket> will happen automatically after
a successful handshake is performed.

=head2 C<delete>

  my $tx = $ua->delete('http://kraih.com');
  my $tx = $ua->delete('http://kraih.com' => {Connection => 'close'});
  my $tx = $ua->delete(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Perform blocking HTTP C<DELETE> request.
You can also append a callback to perform requests non-blocking.

  $ua->delete('http://kraih.com' => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<detect_proxy>

  $ua = $ua->detect_proxy;

Check environment variables C<HTTP_PROXY>, C<http_proxy>, C<HTTPS_PROXY>,
C<https_proxy>, C<NO_PROXY> and C<no_proxy> for proxy information.

=head2 C<get>

  my $tx = $ua->get('http://kraih.com');
  my $tx = $ua->get('http://kraih.com' => {Connection => 'close'});
  my $tx = $ua->get(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Perform blocking HTTP C<GET> request.
You can also append a callback to perform requests non-blocking.

  $ua->get('http://kraih.com' => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<head>

  my $tx = $ua->head('http://kraih.com');
  my $tx = $ua->head('http://kraih.com' => {Connection => 'close'});
  my $tx = $ua->head(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Perform blocking HTTP C<HEAD> request.
You can also append a callback to perform requests non-blocking.

  $ua->head('http://kraih.com' => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<need_proxy>

  my $need_proxy = $ua->need_proxy('intranet.mojolicio.us');

Check if request for domain would use a proxy server.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<post>

  my $tx = $ua->post('http://kraih.com');
  my $tx = $ua->post('http://kraih.com' => {Connection => 'close'});
  my $tx = $ua->post(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Perform blocking HTTP C<POST> request.
You can also append a callback to perform requests non-blocking.

  $ua->post('http://kraih.com' => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<post_form>

  my $tx = $ua->post_form('http://kraih.com/foo' => {test => 123});
  my $tx = $ua->post_form(
    'http://kraih.com/foo'
    'UTF-8',
    {test => 123}
  );
  my $tx  = $ua->post_form(
    'http://kraih.com/foo',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx  = $ua->post_form(
    'http://kraih.com/foo',
    'UTF-8',
    {test => 123},
    {Connection => 'close'}
  );
  my $tx = $ua->post_form(
    'http://kraih.com/foo',
    {file => {file => '/foo/bar.txt'}}
  );
  my $tx= $ua->post_form(
    'http://kraih.com/foo',
    {file => {content => 'lalala'}}
  );
  my $tx = $ua->post_form(
    'http://kraih.com/foo',
    {myzip => {file => $asset, filename => 'foo.zip'}}
  );

Perform blocking HTTP C<POST> request with form data.
You can also append a callback to perform requests non-blocking.

  $ua->post_form('http://kraih.com' => {q => 'test'} => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<put>

  my $tx = $ua->put('http://kraih.com');
  my $tx = $ua->put('http://kraih.com' => {Connection => 'close'});
  my $tx = $ua->put(
    'http://kraih.com' => {Connection => 'close'} => 'Hi!'
  );

Perform blocking HTTP C<PUT> request.
You can also append a callback to perform requests non-blocking.

  $ua->put('http://kraih.com' => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<start>

  $ua = $ua->start($tx);

Process blocking transaction.
You can also append a callback to perform transactions non-blocking.

  $ua->start($tx => sub {
    print pop->res->body;
    Mojo::IOLoop->stop;
  });
  Mojo::IOLoop->start;

=head2 C<test_server>

  my $port = $ua->test_server;
  my $port = $ua->test_server('https');

Starts a test server for C<app> if necessary and returns the port number.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<websocket>

  $ua->websocket('ws://localhost:3000' => sub {...});
  $ua->websocket(
    'ws://localhost:3000' => {'User-Agent' => 'Agent 1.0'} => sub {...}
  );

Open a non-blocking WebSocket connection with transparent handshake.

  $ua->websocket('ws://localhost:3000' => sub {
    my $tx = pop;
    $tx->on_finish(sub { Mojo::IOLoop->stop });
    $tx->on_message(sub { say pop });
    $tx->send_message('Hi!');
  });
  Mojo::IOLoop->start;

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
