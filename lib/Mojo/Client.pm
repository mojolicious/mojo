# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Client;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::ByteStream 'b';
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::CookieJar;
use Mojo::IOLoop;
use Mojo::Parameters;
use Mojo::Server::Daemon;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Scalar::Util 'weaken';

__PACKAGE__->attr([qw/app log tls_ca_file tls_verify_cb tx/]);
__PACKAGE__->attr(cookie_jar => sub { Mojo::CookieJar->new });
__PACKAGE__->attr(ioloop     => sub { Mojo::IOLoop->new });
__PACKAGE__->attr(keep_alive_timeout         => 15);
__PACKAGE__->attr(max_keep_alive_connections => 5);
__PACKAGE__->attr(max_redirects              => 0);
__PACKAGE__->attr(websocket_timeout          => 300);

# Singleton
our $CLIENT;

# Make sure we leave a clean ioloop behind
sub DESTROY {
    my $self = shift;

    # Shortcut
    return unless my $loop = $self->ioloop;

    # Cleanup active connections
    my $cs = $self->{_cs} || {};
    for my $id (keys %$cs) {
        $loop->drop($id);
    }

    # Cleanup keep alive connections
    my $cache = $self->{_cache} || [];
    for my $cached (@$cache) {
        my $id = $cached->[1];
        $loop->drop($id);
    }
}

sub async {
    my $self = shift;

    # Already async
    my $singleton = Mojo::IOLoop->singleton;
    return $self if $self->{_is_async} || !$singleton->is_running;

    # Async
    unless ($self->{_async}) {

        # Clone
        my $clone = $self->{_async} = $self->clone;
        $clone->{_is_async} = 1;

        # Singleton
        $clone->ioloop($singleton);
    }

    return $self->{_async};
}

sub clone {
    my $self = shift;

    # Clone
    my $clone = $self->new;
    $clone->app($self->app);
    $clone->cookie_jar($self->cookie_jar);
    $clone->keep_alive_timeout($self->keep_alive_timeout);
    $clone->max_keep_alive_connections($self->max_keep_alive_connections);
    $clone->max_redirects($self->max_redirects);
    $clone->tls_ca_file($self->tls_ca_file);
    $clone->tls_verify_cb($self->tls_verify_cb);
    $clone->websocket_timeout($self->websocket_timeout);

    return $clone;
}

sub delete { shift->_build_tx('DELETE', @_) }

sub finish {
    my $self = shift;

    # WebSocket
    croak 'No WebSocket connection to finish'
      if ref $self->tx eq 'ARRAY' && !$self->tx->is_websocket;

    # Finish
    $self->tx->finish;
}

sub finished {
    my $self = shift;

    # WebSocket
    croak 'No WebSocket connection in progress'
      if ref $self->tx eq 'ARRAY' && !$self->tx->is_websocket;

    # Callback
    my $cb = shift;

    # Transaction
    my $tx = $self->tx;

    # Weaken
    weaken $self;
    weaken $tx;

    # Connection finished
    $tx->finished(sub { shift; local $self->{tx} = $tx; $self->$cb(@_) });
}

sub get  { shift->_build_tx('GET',  @_) }
sub head { shift->_build_tx('HEAD', @_) }
sub post { shift->_build_tx('POST', @_) }

sub post_form {
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
    for my $name (sort keys %$form) {

        # Array
        if (ref $form->{$name} eq 'ARRAY') {
            for my $value (@{$form->{$name}}) {
                $params->append($name, $value);
            }
        }

        # Single value
        else {
            my $value = $form->{$name};
            $params->append($name, $value);
        }
    }

    # Transaction
    my $tx = Mojo::Transaction::HTTP->new;
    $tx->req->method('POST');
    $tx->req->url->parse($url);

    # Headers
    $tx->req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

    # Multipart
    my $type = $tx->req->headers->content_type || '';
    if ($type eq 'multipart/form-data') {
        $self->_build_multipart_post($tx, $params, $encoding);
    }

    # Urlencoded
    else {
        $tx->req->headers->content_type('application/x-www-form-urlencoded');
        $tx->req->body($params->to_string);
    }

    # Quick process
    if (!$cb && !$self->{_is_async}) {
        $self->process($tx);
        return $tx;
    }

    # Queue transaction with callback
    $self->queue($tx, $cb);
}

sub process {
    my $self = shift;

    # Queue
    $self->queue(@_) if @_;
    my $queue = $self->{_queue} || [];
    $self->{_queue} = [];

    # Already running
    if (!$self->{_is_async} && $self->{_queued}) {
        my $clone = $self->clone;
        for my $job (@$queue) { $clone->queue(@$job) }
        return $clone->process;
    }

    # Process
    else {
        for my $job (@$queue) { $self->_queue(@$job) }
    }

    # Start ioloop
    $self->ioloop->start;

    return $self;
}

sub put { shift->_build_tx('PUT', @_) }

sub queue {
    my $self = shift;

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Queue transactions
    my $queue = $self->{_queue} ||= [];
    for my $tx (@_) { push @$queue, [$tx, $cb] if $tx }

    return $self;
}

sub receive_message {
    my $self = shift;

    # WebSocket
    croak 'No WebSocket connection to receive messages from'
      if ref $self->tx eq 'ARRAY' && !$self->tx->is_websocket;

    # Callback
    my $cb = shift;

    # Transaction
    my $tx = $self->tx;

    # Weaken
    weaken $self;
    weaken $tx;

    # Receive
    $tx->receive_message(
        sub { shift; local $self->{tx} = $tx; $self->$cb(@_) });
}

sub req {
    my $self = shift;

    # Pipeline
    croak 'Method "req" not supported for pipelines'
      if ref $self->tx eq 'ARRAY';

    $self->tx->req(@_);
}

sub res {
    my $self = shift;

    # Pipeline
    croak 'Method "res" not supported for pipelines'
      if ref $self->tx eq 'ARRAY';

    $self->tx->res(@_);
}

sub singleton { $CLIENT ||= shift->new(@_) }

sub send_message {
    my $self = shift;

    # WebSocket
    croak 'No WebSocket connection to send message to'
      if ref $self->tx eq 'ARRAY' && !$self->tx->is_websocket;

    # Send
    $self->tx->send_message(@_);
}

sub success {
    my $self = shift;

    # Pipeline
    croak 'Method "success" not supported for pipelines'
      if ref $self->tx eq 'ARRAY';

    $self->tx->success(@_);
}

# Are we there yet?
# No
# Are we there yet?
# No
# Are we there yet?
# No
# ...Where are we going?
sub websocket {
    my $self = shift;

    # New WebSocket
    my $tx = Mojo::Transaction::HTTP->new;

    # Request
    my $req = $tx->req;
    $req->method('GET');

    # URL
    $req->url->parse(shift);

    # Scheme
    if (my $scheme = $req->url->to_abs->scheme) {
        $scheme = $scheme eq 'wss' ? 'https' : 'http';
        $req->url($req->url->to_abs->scheme($scheme));
    }

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Headers
    my $h = $req->headers;
    $h->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

    # Default headers
    $h->upgrade('WebSocket')       unless $h->upgrade;
    $h->connection('Upgrade')      unless $h->connection;
    $h->websocket_protocol('mojo') unless $h->websocket_protocol;

    # Queue
    $self->queue($tx, $cb);
}

sub _build_multipart_post {
    my ($self, $tx, $params, $encoding) = @_;

    # Formdata
    my $form = $params->to_hash;

    # Parts
    my @parts;
    foreach my $name (sort keys %$form) {

        # Part
        my $part = Mojo::Content::Single->new;

        # Content-Disposition
        my $escaped = b($name);
        $escaped->encode($encoding) if $encoding;
        $escaped = $escaped->url_escape($Mojo::URL::PARAM)->to_string;
        $part->headers->content_disposition(qq/form-data; name="$escaped"/);

        # Content-Type
        my $type = 'text/plain';
        $type .= qq/;charset=$encoding/ if $encoding;
        $part->headers->content_type($type);

        # Values
        my $f = $form->{$name};
        my $chunk = join ',', ref $f ? @$f : ($f);
        $chunk = b($chunk)->encode($encoding)->to_string if $encoding;
        $part->asset->add_chunk($chunk);

        push @parts, $part;
    }

    # Multipart content
    my $content = Mojo::Content::MultiPart->new;
    $content->headers($tx->req->headers);
    $content->headers->content_type('multipart/form-data');
    $content->parts(\@parts);

    # Add content to transaction
    $tx->req->content($content);
}

sub _build_tx {
    my $self = shift;

    # New transaction
    my $tx = Mojo::Transaction::HTTP->new;

    # Request
    my $req = $tx->req;

    # Method
    $req->method(shift);

    # URL
    $req->url->parse(shift);

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Body
    $req->body(pop @_) if @_ & 1 == 1 || ref $_[-2] eq 'HASH';

    # Headers
    $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

    # Quick process
    if (!$cb && !$self->{_is_async}) {
        $self->process($tx);
        return $tx;
    }

    # Queue transaction with callback
    $self->queue($tx, $cb);
}

sub _connect {
    my ($self, $tx, $cb) = @_;

    # Pipeline
    my $pipeline = ref $tx eq 'ARRAY' ? 1 : 0;

    # Info
    my ($scheme, $address, $port) =
      $self->_tx_info($pipeline ? $tx->[0] : $tx);

    # Cached connection
    my $id;
    if ($id = $self->_withdraw("$scheme:$address:$port")) {

        # Writing
        $self->ioloop->writing($id);

        # Add new connection
        $self->{_cs}->{$id} = {cb => $cb, tx => $tx};

        # Kept alive first transaction
        $tx = $pipeline ? $tx->[0] : $tx;
        $tx->kept_alive(1);

        # Connected
        $self->_connected($id);
    }

    # New connection
    else {

        # Connect
        $id = $self->ioloop->connect(
            cb => sub {
                my ($loop, $id) = @_;

                # Connected
                $self->_connected($id);
            },
            address => $address,
            port    => $port,
            tls     => $scheme eq 'https' ? 1 : 0,
            tls_ca_file => $self->tls_ca_file || $ENV{MOJO_CA_FILE},
            tls_verify_cb => $self->tls_verify_cb
        );

        # Error
        unless (defined $id) {

            # Update all transactions
            for my $tx ($pipeline ? @$tx : ($tx)) {
                $tx->error(500, qq/Couldn't connect./);
            }

            # Callback
            $self->$cb($tx) if $cb;

            return;
        }

        # Callbacks
        $self->ioloop->error_cb($id => sub { $self->_error(@_) });
        $self->ioloop->hup_cb($id => sub { $self->_error(@_) });
        $self->ioloop->read_cb($id => sub { $self->_read(@_) });
        $self->ioloop->write_cb($id => sub { $self->_write(@_) });

        # Add new connection
        $self->{_cs}->{$id} = {cb => $cb, tx => $tx};
    }

    return $id;
}

sub _connected {
    my ($self, $id) = @_;

    # Prepare transactions
    my $loop = $self->ioloop;
    my $tx   = $self->{_cs}->{$id}->{tx};
    for my $tx (ref $tx eq 'ARRAY' ? @$tx : ($tx)) {

        # Connection
        $tx->connection($id);

        # Store connection information in transaction
        my $local = $loop->local_info($id);
        $tx->local_address($local->{address});
        $tx->local_port($local->{port});
        my $remote = $loop->remote_info($id);
        $tx->remote_address($remote->{address});
        $tx->remote_port($remote->{port});
    }

    # Keep alive timeout
    $loop->connection_timeout($id => $self->keep_alive_timeout);
}

sub _deposit {
    my ($self, $name, $id) = @_;

    # Limit keep alive connections
    my $cache = $self->{_cache} ||= [];
    while (@$cache >= $self->max_keep_alive_connections) {
        my $cached = shift @$cache;
        $self->_drop($cached->[1]);
    }

    # Deposit
    push @$cache, [$name, $id];
}

sub _drop {
    my ($self, $id) = @_;

    # Keep connection alive
    if (my $tx = $self->{_cs}->{$id}->{tx}) {

        # Read only
        $self->ioloop->not_writing($id);

        # Last transaction
        $tx = ref $tx eq 'ARRAY' ? $tx->[-1] : $tx;

        # Deposit
        my ($scheme, $address, $port) = $self->_tx_info($tx);
        $self->_deposit("$scheme:$address:$port", $id) if $tx->keep_alive;
    }

    # Connection close
    else {
        $self->ioloop->drop($id);
        $self->_withdraw($id);
    }

    # Drop connection
    delete $self->{_cs}->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Transaction
    if (my $tx = $self->{_cs}->{$id}->{tx}) {

        # Add error message to all transactions
        for my $tx (ref $tx eq 'ARRAY' ? @$tx : ($tx)) {
            $tx->error(500, $error) unless $tx->is_finished;
        }
    }

    # Log
    my $log = $self->log;
    $log->error($error) if $error && $log;

    # Finish
    $self->_finish($id);
}

sub _fetch_cookies {
    my ($self, $tx) = @_;

    # Shortcut
    return unless $self->cookie_jar;

    # URL
    my $url = $tx->req->url->clone;
    if (my $host = $tx->req->headers->host) { $url->host($host) }

    # Fetch
    $tx->req->cookies($self->cookie_jar->find($tx->req->url));
}

# No children have ever meddled with the Republican Party and lived to tell
# about it.
sub _finish {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    my $old = $c->{tx};

    # Pipeline
    my $pipeline = ref $old eq 'ARRAY' ? 1 : 0;

    # Drop WebSockets
    my $new;
    if ($old && !$pipeline && $old->is_websocket) {
        $old->client_close;
        $old = undef;
        $self->{_queued} -= 1;
        delete $self->{_cs}->{$id};
        $self->_drop($id);
    }

    # Normal transaction
    else {

        # WebSocket upgrade
        $new = $self->_upgrade($id) if $old;

        # Drop old connection so we can reuse it
        $self->_drop($id) unless $new;
    }

    # Finish normal transaction
    if ($old) {

        # Cookies to the jar
        for my $tx ($pipeline ? @$old : ($old)) { $self->_store_cookies($tx) }

        # Counter
        $self->{_queued} -= 1 unless $new && !$pipeline;

        # Done
        unless ($self->_redirect($c, $old)) {
            my $cb = $c->{cb};
            my $tx = $new;
            $tx ||= $old;
            local $self->{tx} = $tx;
            $self->$cb($tx, $c->{history}) if $cb;
        }
    }

    # Stop ioloop
    $self->ioloop->stop if !$self->{_is_async} && !$self->{_queued};
}

sub _fix_cookies {
    my ($self, $tx, @cookies) = @_;

    # Fix
    for my $cookie (@cookies) {

        # Domain
        $cookie->domain($tx->req->url->host) unless $cookie->domain;

        # Path
        $cookie->path($tx->req->url->path) unless $cookie->path;
    }

    return @cookies;
}

sub _prepare_server {
    my $self = shift;

    # Server
    unless ($self->{_port}) {
        my $server = $self->{_server} =
          Mojo::Server::Daemon->new(ioloop => $self->ioloop, silent => 1);
        my $port = $self->{_port} = $self->ioloop->generate_port;
        die "Couldn't find a free TCP port for testing.\n" unless $port;
        $server->listen("http://*:$port");
        $server->prepare_ioloop;
    }

    # Application
    my $server = $self->{_server};
    delete $server->{app};
    my $app = $self->app;
    ref $app ? $server->app($app) : $server->app_class($app);
}

sub _queue {
    my ($self, $tx, $cb) = @_;

    # Embedded server
    $self->_prepare_server if $self->app;

    # Pipeline
    my $pipeline = ref $tx eq 'ARRAY' ? 1 : 0;

    # Log
    $self->log($self->{_server}->app->log) if $self->{_server} && !$self->log;

    # Prepare all transactions
    for my $tx ($pipeline ? @$tx : ($tx)) {

        # Embedded server
        if ($self->app) {
            my $url = $tx->req->url->to_abs;
            next if $url->host;
            $url->scheme('http');
            $url->host('localhost');
            $url->port($self->{_port});
            $tx->req->url($url);
        }

        # Make sure WebSocket requests have an origin header
        my $req = $tx->req;
        $req->headers->origin($req->url)
          if $req->headers->upgrade && !$req->headers->origin;

        # Cookies from the jar
        $self->_fetch_cookies($tx);
    }

    # Connect
    return unless my $id = $self->_connect($tx, $cb);

    # Pipeline
    if ($pipeline) {
        my $c = $self->{_cs}->{$id};
        $c->{writer} = 0;
        $c->{reader} = 0;
    }

    # Weaken
    weaken $self;

    # Prepare
    for my $t ($pipeline ? @$tx : ($tx)) {

        # We identify ourself
        $t->req->headers->user_agent(
            'Mozilla/5.0 (compatible; Mojolicious; Perl)')
          unless $t->req->headers->user_agent;

        # State change callback
        $t->state_cb(sub { $self->_state($id, @_) });
    }

    # Counter
    $self->{_queued} ||= 0;
    $self->{_queued} += 1;

    return $id;
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    if (my $tx = $c->{tx}) {

        # Pipeline
        $tx = $c->{tx}->[$c->{reader}] if defined $c->{reader};

        # Read
        $tx->client_read($chunk);
    }

    # Corrupted connection
    else { $self->_drop($id) }
}

sub _redirect {
    my ($self, $c, $tx) = @_;

    # Pipeline
    return if ref $tx eq 'ARRAY';

    # Code
    return unless $tx->res->is_status_class('300');
    return if $tx->res->code == 305;

    # Location
    return unless my $location = $tx->res->headers->location;

    # Method
    my $method = $tx->req->method;
    $method = 'GET' unless $method =~ /^GET|HEAD$/i;

    # Max redirects
    my $r = $c->{redirects} || 0;
    my $max = $self->max_redirects;
    return unless $r < $max;

    # New transaction
    my $new = Mojo::Transaction::HTTP->new;
    $new->req->method($method);
    $new->req->url->parse($location);

    # History
    my $h = $c->{history} || [];

    # Queue redirected request
    my $nid = $self->_queue($new, $c->{cb});

    # Create new conenction
    my $nc = $self->{_cs}->{$nid};
    push @$h, $tx;
    $nc->{history}   = $h;
    $nc->{redirects} = $r + 1;

    # Redirecting
    return 1;
}

sub _state {
    my ($self, $id, $tx) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Normal transaction
    unless (ref $c->{tx} eq 'ARRAY') {

        # Finished
        return $self->_finish($id) if $tx->is_finished;

        # Writing
        return $tx->is_writing
          ? $self->ioloop->writing($id)
          : $self->ioloop->not_writing($id);
    }

    # Reader
    my $reader = $c->{tx}->[$c->{reader}];
    if ($reader && $reader->is_finished) {
        $c->{reader}++;

        # Leftovers
        if (defined(my $leftovers = $reader->client_leftovers)) {
            $reader = $c->{tx}->[$c->{reader}];
            $reader->client_read($leftovers);
        }
    }

    # Finished
    return $self->_finish($id) unless $c->{tx}->[$c->{reader}];

    # Writer
    my $writer = $c->{tx}->[$c->{writer}];
    $c->{writer}++
      if $writer && $writer->is_state('read_response');

    # Current
    my $current = $c->{writer};
    $current = $c->{reader} unless $c->{tx}->[$c->{writer}];

    return $c->{tx}->[$current]->is_writing
      ? $self->ioloop->writing($id)
      : $self->ioloop->not_writing($id);
}

sub _store_cookies {
    my ($self, $tx) = @_;

    # Shortcut
    return unless $self->cookie_jar;

    # Store
    $self->cookie_jar->add($self->_fix_cookies($tx, @{$tx->res->cookies}));
}

sub _tx_info {
    my ($self, $tx) = @_;

    # Info
    my $scheme = $tx->req->url->scheme;
    my $host   = $tx->req->url->ihost;
    my $port   = $tx->req->url->port;

    # Proxy
    if (my $proxy = $tx->req->proxy) {
        $scheme = $proxy->scheme;
        $host   = $proxy->ihost;
        $port   = $proxy->port;
    }

    # Default port
    $scheme ||= 'http';
    $port ||= $scheme eq 'https' ? 443 : 80;

    return ($scheme, $host, $port);
}

sub _upgrade {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    my $old = $c->{tx};

    # Pipeline
    return if ref $old eq 'ARRAY';

    # No handshake
    return unless $old->req->headers->upgrade;

    # Handshake failed
    return unless ($old->res->code || '') eq '101';

    # Start new WebSocket
    my $new = $c->{tx} = Mojo::Transaction::WebSocket->new(handshake => $old);

    # Cleanup connection
    delete $c->{reader};
    delete $c->{writer};

    # Upgrade connection timeout
    $self->ioloop->connection_timeout($id, $self->websocket_timeout);

    # Weaken
    weaken $self;

    # State change callback
    $new->state_cb(
        sub {
            my $tx = shift;

            # Finished
            return $self->_finish($id) if $tx->is_finished;

            # Writing
            $tx->is_writing
              ? $self->ioloop->writing($id)
              : $self->ioloop->not_writing($id);
        }
    );

    return $new;
}

sub _withdraw {
    my ($self, $name) = @_;

    # Withdraw
    my $found;
    my @cache;
    my $cache = $self->{_cache} || [];
    for my $cached (@$cache) {

        # Search for name or id
        $found = $cached->[1] and next
          if $cached->[1] eq $name || $cached->[0] eq $name;

        # Cache again
        push @cache, $cached;
    }
    $self->{_cache} = \@cache;

    return $found;
}

sub _write {
    my ($self, $loop, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Transaction
    if (my $tx = $c->{tx}) {

        # Pipeline
        $tx = $c->{tx}->[$c->{writer}] if defined $c->{writer};

        # Get chunk
        return $tx->client_write;
    }

    # Corrupted connection
    else { $self->_drop($id) }

    return;
}

1;
__END__

=head1 NAME

Mojo::Client - Async IO HTTP 1.1 And WebSocket Client

=head1 SYNOPSIS

    use Mojo::Client;
    my $client = Mojo::Client->new;

    $client->async->get(
        'http://kraih.com' => sub {
            my $self = shift;
            print $self->res->code;
        }
    )->process;

    $client->get(
        'http://kraih.com' => sub {
            if (my $res = shift->success) { print $res->code }
        }
    )->process;

    print $client->post('http://mojolicious.org')->success->body;

=head1 DESCRIPTION

L<Mojo::Client> is a full featured async io HTTP 1.1 and WebSocket client
with C<IPv6>, C<TLS>, C<epoll> and C<kqueue> support.

It implements the most common HTTP verbs.
If you need something more custom you can create your own
L<Mojo::Transaction::HTTP> objects and C<queue> them.
All of the verbs take an optional set of headers as a hash or hash reference,
as well as an optional callback sub reference.

Optional modules L<IO::KQueue>, L<IO::Epoll>, L<IO::Socket::INET6> and
L<IO::Socket::SSL> are supported transparently and used if installed.

=head1 ATTRIBUTES

L<Mojo::Client> implements the following attributes.

=head2 C<app>

    my $app = $client->app;
    $client = $client->app(MyApp->new);

A Mojo application to associate this client with.
If set, local requests will be processed in this application.

=head2 C<cookie_jar>

    my $cookie_jar = $client->cookie_jar;
    $client        = $client->cookie_jar(Mojo::CookieJar->new);

Cookie jar to use for this clients requests, by default a L<Mojo::CookieJar>
object.

=head2 C<ioloop>

    my $loop = $client->ioloop;
    $client  = $client->ioloop(Mojo::IOLoop->new);

Loop object to use for io operations, by default a L<Mojo::IOLoop> object
will be used.

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $client->keep_alive_timeout;
    $client                = $client->keep_alive_timeout(15);

Timeout in seconds for keep alive between requests, defaults to C<15>.

=head2 C<log>

    my $log = $client->log;
    $client = $client->log(Mojo::Log->new);

A L<Mojo::Log> object used for logging, by default the application log will
be used.

=head2 C<max_keep_alive_connections>

    my $max_keep_alive_connections = $client->max_keep_alive_connections;
    $client                        = $client->max_keep_alive_connections(5);

Maximum number of keep alive connections that the client will retain before
it starts closing the oldest cached ones, defaults to C<5>.

=head2 C<max_redirects>

    my $max_redirects = $client->max_redirects;
    $client           = $client->max_redirects(3);

Maximum number of redirects the client will follow before it fails, defaults
to C<3>.

=head2 C<tls_ca_file>

    my $tls_ca_file = $client->tls_ca_file;
    $client         = $client->tls_ca_file('/etc/tls/cacerts.pem');

TLS certificate authority file to use, defaults to the C<MOJO_CA_FILE>
environment variable.
Note that L<IO::Socket::SSL> must be installed for HTTPS support.

=head2 C<tls_verify_cb>

    my $tls_verify_cb = $client->tls_verify_cb;
    $client           = $client->tls_verify_cb(sub {...});

Callback to verify your TLS connection, by default the client will accept
most certificates.
Note that L<IO::Socket::SSL> must be installed for HTTPS support.

=head2 C<tx>

    $client->tx;

The last finished transaction, only available from callbacks.

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
Use C<singleton> if you want to share keep alive connections and cookies with
other clients

=head2 C<async>

    my $async = $client->async;

Clone client instance and start using the global shared L<Mojo::IOLoop>
singleton.

    $client->async->get('http://mojolicious.org' => sub {
        my $self = shift;
        print $self->res->body;
    })->process;

=head2 C<clone>

    my $clone = $client->clone;

Clone client instance.

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

Send a HTTP C<DELETE> request.

=head2 C<finish>

    $client->finish;

Finish the WebSocket connection, only available from callbacks.

=head2 C<finished>

    $client->finished(sub {...});

Callback signaling that peer finished the WebSocket connection, only
available from callbacks.

    $client->finished(sub {
        my $self = shift;
    });

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

Send a HTTP C<GET> request.

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

Send a HTTP C<HEAD> request.

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

Send a HTTP C<POST> request.

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
        {Expect => '100-continue'}
    );
    my $tx  = $client->post_form(
        'http://kraih.com/foo',
        'UTF-8',
        {test => 123},
        {Expect => '100-continue'}
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
        {Expect => '100-continue'},
        sub {...}
    );
    $client = $client->post_form(
        'http://kraih.com/foo',
        'UTF-8',
        {test => 123},
        {Expect => '100-continue'},
        sub {...}
    );

Send a HTTP C<POST> request with form data.

=head2 C<process>

    $client = $client->process;
    $client = $client->process(@transactions);
    $client = $client->process(@transactions => sub {...});

Process all queued transactions.
Will be blocking unless you have a global shared ioloop and use the C<async>
method.

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

Send a HTTP C<PUT> request.

=head2 C<queue>

    $client = $client->queue(@transactions);
    $client = $client->queue(@transactions => sub {...});

Queue a list of transactions for processing.
HTTP 1.1 transactions can also be pipelined by wrapping them in an arrayref.
Note that following redirects and WebSocket upgrades don't work for pipelined
transactions.

    $client->queue([$tx, $tx2] => sub {
        my ($self, $p) = @_;
    });

=head2 C<receive_message>

    $client->receive_message(sub {...});

Receive messages via WebSocket, only available from callbacks.

    $client->receive_message(sub {
        my ($self, $message) = @_;
    });

=head2 C<req>

    my $req = $client->req;

The request object of the last finished transaction, only available from
callbacks.

=head2 C<res>

    my $res = $client->res;

The response object of the last finished transaction, only available from
callbacks.

=head2 C<singleton>

    my $client = Mojo::Client->singleton;

The global client object, used to access a single shared client instance from
everywhere inside the process.

=head2 C<send_message>

    $client->send_message('Hi there!');

Send a message via WebSocket, only available from callbacks.

=head2 C<success>

    my $res = $client->success;

Return C<res> if the last finished transaction was successful and had no
connection or parser errors, only available from callbacks.

=head2 C<websocket>

    $client = $client->websocket('ws://localhost:3000' => sub {...});
    $client = $client->websocket(
        'ws://localhost:3000' => {'User-Agent' => 'Agent 1.0'} => sub {...}
    );

Open a WebSocket connection with transparent handshake.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
