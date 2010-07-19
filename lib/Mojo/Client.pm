# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Client;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::Asset::File;
use Mojo::Asset::Memory;
use Mojo::ByteStream 'b';
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::CookieJar;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Parameters;
use Mojo::Server::Daemon;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;
use Mojo::URL;
use Scalar::Util 'weaken';

# You can't let a single bad experience scare you away from drugs.
__PACKAGE__->attr(
    [qw/app http_proxy https_proxy tls_ca_file tls_verify_cb tx/]);
__PACKAGE__->attr(cookie_jar => sub { Mojo::CookieJar->new });
__PACKAGE__->attr(ioloop     => sub { Mojo::IOLoop->new });
__PACKAGE__->attr(keep_alive_timeout         => 15);
__PACKAGE__->attr(log                        => sub { Mojo::Log->new });
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
    $loop->drop($_) for keys %$cs;

    # Cleanup keep alive connections
    my $cache = $self->{_cache} || [];
    for my $cached (@$cache) {
        my $id = $cached->[1];
        $loop->drop($id);
    }
}

# Homer, it's easy to criticize.
# Fun, too.
sub async {
    my $self = shift;

    # Already async or async not possible
    return $self if $self->{_is_async};

    # Create async client
    unless ($self->{_async}) {

        # Clone and cache async client
        my $clone = $self->{_async} = $self->clone;
        $clone->{_is_async} = 1;

        # Make async client use the global ioloop if available
        my $singleton = Mojo::IOLoop->singleton;
        $clone->ioloop($singleton->is_running ? $singleton : $self->ioloop);

        # Inherit test server
        $clone->{_server} = $self->{_server};
        $clone->{_port}   = $self->{_port};
    }

    return $self->{_async};
}

# Ah, alcohol and night-swimming. It's a winning combination.
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
                $filename = b($filename);
                $filename->encode($encoding) if $encoding;
                $filename =
                  $filename->url_escape($Mojo::URL::PARAM)->to_string;

                # File
                $part->asset(delete $f->{file});

                # Headers
                $h->from_hash($f);
            }

            # Fields
            else {

                # Values
                my $chunk = join ',', ref $f ? @$f : ($f);
                $chunk = b($chunk)->encode($encoding)->to_string if $encoding;
                $part->asset->add_chunk($chunk);

                # Content-Type
                my $type = 'text/plain';
                $type .= qq/;charset=$encoding/ if $encoding;
                $h->content_type($type);
            }

            # Content-Disposition
            my $escaped = b($name);
            $escaped->encode($encoding) if $encoding;
            $escaped = $escaped->url_escape($Mojo::URL::PARAM)->to_string;
            my $disposition = qq/form-data; name="$escaped"/;
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
    $req->url->parse(shift);

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
    my $tx = Mojo::Transaction::HTTP->new;

    # Request
    my $req = $tx->req;
    $req->method('GET');

    # URL
    my $url = $req->url;
    $url->parse(shift);

    # Scheme
    my $abs = $url->to_abs;
    if (my $scheme = $abs->scheme) {
        $scheme = $scheme eq 'wss' ? 'https' : 'http';
        $req->url($abs->scheme($scheme));
    }

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Headers
    my $h = $req->headers;
    $h->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

    # Default headers
    $h->upgrade('WebSocket')           unless $h->upgrade;
    $h->connection('Upgrade')          unless $h->connection;
    $h->sec_websocket_protocol('mojo') unless $h->sec_websocket_protocol;

    # Generate challenge
    $h->sec_websocket_key1($self->_generate_key)
      unless $h->sec_websocket_key1;
    $h->sec_websocket_key2($self->_generate_key)
      unless $h->sec_websocket_key2;
    $req->body(pack 'N*', int(rand 9999999) + 1, int(rand 9999999) + 1);

    return $tx unless wantarray;
    return $tx, $cb;
}

sub clone {
    my $self = shift;

    # Clone
    my $clone = $self->new;
    $clone->app($self->app);
    $clone->log($self->log);
    $clone->cookie_jar($self->cookie_jar);
    $clone->keep_alive_timeout($self->keep_alive_timeout);
    $clone->max_keep_alive_connections($self->max_keep_alive_connections);
    $clone->max_redirects($self->max_redirects);
    $clone->tls_ca_file($self->tls_ca_file);
    $clone->tls_verify_cb($self->tls_verify_cb);
    $clone->websocket_timeout($self->websocket_timeout);

    return $clone;
}

# The only thing I asked you to do for this party was put on clothes,
# and you didn't do it.
sub delete {
    my $self = shift;
    return $self->_queue_or_process_tx($self->build_tx('DELETE', @_));
}

sub detect_proxy {
    my $self = shift;
    $self->http_proxy($ENV{HTTP_PROXY}   || $ENV{http_proxy});
    $self->https_proxy($ENV{HTTPS_PROXY} || $ENV{https_proxy});
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

sub finished {
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
    $tx->finished(sub { shift; local $self->{tx} = $tx; $self->$cb(@_) });
}

# "What are you lookin' at?" - the innocent words of a drunken child.
sub get {
    my $self = shift;
    return $self->_queue_or_process_tx($self->build_tx('GET', @_));
}

sub head {
    my $self = shift;
    return $self->_queue_or_process_tx($self->build_tx('HEAD', @_));
}

sub post {
    my $self = shift;
    return $self->_queue_or_process_tx($self->build_tx('POST', @_));
}

sub post_form {
    my $self = shift;
    return $self->_queue_or_process_tx($self->build_form_tx(@_));
}

# Olive oil? Asparagus? If your mother wasn't so fancy,
# we could just shop at the gas station like normal people.
sub process {
    my $self = shift;

    # Queue
    $self->queue(@_) if @_;
    my $queue = delete $self->{_queue} || [];

    # Process sync subrequests in new client
    if (!$self->{_is_async} && $self->{_processing}) {
        my $clone = $self->clone;
        $clone->queue(@$_) for @$queue;
        return $clone->process;
    }

    # Add async transactions from queue
    else { $self->_prepare_pipeline(@$_) for @$queue }

    # Process sync requests
    if (!$self->{_is_async} && $self->{_processing}) {

        # Start loop
        my $loop = $self->ioloop;
        $loop->start;

        # Cleanup
        $loop->one_tick(0);
    }

    return $self;
}

sub put {
    my $self = shift;
    $self->_queue_or_process_tx($self->build_tx('PUT', @_));
}

# And I gave that man directions, even though I didn't know the way,
# because that's the kind of guy I am this week.
sub queue {
    my $self = shift;

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Queue transactions
    my $queue = $self->{_queue} ||= [];
    for my $tx (@_) {
        push @$queue, [ref $tx eq 'ARRAY' ? $tx : [$tx], $cb] if $tx;
    }

    return $self;
}

sub receive_message {
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
    $tx->receive_message(
        sub { shift; local $self->{tx} = $tx; $self->$cb(@_) });
}

sub req { shift->tx->req(@_) }
sub res { shift->tx->res(@_) }

sub singleton { $CLIENT ||= shift->new(@_) }

# Wow, Barney. You brought a whole beer keg.
# Yeah... where do I fill it up?
sub send_message {
    my $self = shift;

    # Transaction
    my $tx = $self->tx;

    # WebSocket
    croak 'Transaction is not a WebSocket' unless $tx->is_websocket;

    # Send
    $tx->send_message(@_);
}

# It's like my dad always said: eventually, everybody gets shot.
sub test_server {
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
    $self->log($server->app->log);

    return $self->{_port};
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
    $self->queue($self->build_websocket_tx(@_));
}

sub websocket_challenge {
    my ($self, $key1, $key2, $key3) = @_;

    # Shortcut
    return unless $key1 && $key2 && $key3;

    # Calculate solution for challenge
    my $c1 = pack 'N', join('', $key1 =~ /(\d)/g) / ($key1 =~ tr/\ //);
    my $c2 = pack 'N', join('', $key2 =~ /(\d)/g) / ($key2 =~ tr/\ //);
    return b("$c1$c2$key3")->md5_bytes->to_string;
}

sub _cache {
    my ($self, $name, $id) = @_;

    # Cache
    my $cache = $self->{_cache} ||= [];

    # Enqueue
    if ($id) {

        # Limit keep alive connections
        while (@$cache > $self->max_keep_alive_connections) {
            my $cached = shift @$cache;
            $self->_drop($cached->[1]);
        }

        # Add to cache
        push @$cache, [$name, $id];

        return $self;
    }

    # Dequeue
    my $result;
    my @cache;
    for my $cached (@$cache) {

        # Search for name or id
        $result = $cached->[1] and next
          if $cached->[1] eq $name || $cached->[0] eq $name;

        # Cache again
        push @cache, $cached;
    }
    $self->{_cache} = \@cache;

    return $result;
}

# Where on my badge does it say anything about protecting people?
# Uh, second word, chief.
sub _connect {
    my ($self, $p, $cb) = @_;

    # First transaction
    my $c = $p->[0];

    # Check for specific connection id
    my $id = $c->connection;

    # Cleanup
    my $loop = $self->ioloop;
    $loop->one_tick(0);

    # Info
    my ($scheme, $address, $port) = $self->_pipeline_info($p);

    # Keep alive connection
    $id ||= $self->_cache("$scheme:$address:$port");
    if ($id && !ref $id) {

        # Writing
        $loop->writing($id);

        # Add new connection
        $self->{_cs}->{$id} = {cb => $cb, p => $p};

        # Kept alive all transactions
        $_->kept_alive(1) for @$p;

        # Connected
        $self->_connected($id);
    }

    # New connection
    else {

        # TLS/WebSocket proxy
        unless (($c->req->method || '') eq 'CONNECT') {

            # CONNECT request to proxy required
            return if $self->_proxy_connect($p, $cb);
        }

        # Connect
        $id = $loop->connect(
            address => $address,
            port    => $port,
            socket  => $id,
            tls     => $scheme eq 'https' ? 1 : 0,
            tls_ca_file => $self->tls_ca_file || $ENV{MOJO_CA_FILE},
            tls_verify_cb => $self->tls_verify_cb,
            connect_cb    => sub { $self->_connected($_[1]) },
            error_cb      => sub { $self->_error(@_) },
            hup_cb        => sub { $self->_error(@_) },
            read_cb       => sub { $self->_read(@_) },
            write_cb      => sub { $self->_write(@_) }
        );

        # Error
        unless (defined $id) {

            # Update all transactions
            $_->error(qq/Couldn't connect./, 500) for @$p;

            # Callback
            $self->$cb(@$p) if $cb;

            return;
        }

        # Add new connection
        $self->{_cs}->{$id} = {cb => $cb, p => $p};
    }

    return $id;
}

# I don't mind being called a liar when I'm lying, or about to lie,
# or just finished lying, but NOT WHEN I'M TELLING THE TRUTH.
sub _connected {
    my ($self, $id) = @_;

    # Loop
    my $loop = $self->ioloop;

    # Prepare transactions
    for my $tx (@{$self->{_cs}->{$id}->{p}}) {

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

# Mrs. Simpson, bathroom is not for customers.
# Please use the crack house across the street.
sub _drop {
    my ($self, $id) = @_;

    # Keep alive
    if (my $p = $self->{_cs}->{$id}->{p}) {

        # Read only
        $self->ioloop->not_writing($id);

        # Keep connection alive
        my ($scheme, $address, $port) = $self->_pipeline_info($p);
        $self->_cache("$scheme:$address:$port", $id) if $p->[-1]->keep_alive;
    }

    # Connection close
    else {
        $self->_cache($id);
        $self->ioloop->drop($id);
    }

    # Drop connection
    delete $self->{_cs}->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Pipeline
    if (my $p = $self->{_cs}->{$id}->{p}) {

        # Add error message to all transactions
        for my $tx (@$p) { $tx->error($error, 500) unless $tx->is_finished }
    }

    # Log
    $self->log->error($error) if $error;

    # Finished
    $self->_handle_response($id);
}

sub _generate_key {
    my $self = shift;

    # Number of spaces
    my $spaces = int(rand 12) + 1;

    # Number
    my $number = int(rand 99999) + 10;

    # Key
    my $key = $number * $spaces;

    # Insert whitespace
    while ($spaces--) {

        # Random position
        my $pos = int(rand(length($key) - 2)) + 1;

        # Insert a space at $pos position
        substr($key, $pos, 0) = ' ';
    }

    return $key;
}

# No children have ever meddled with the Republican Party and lived to tell
# about it.
sub _handle_response {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Pipeline
    my $old = $c->{p};

    # Drop WebSocket
    my $new;
    if ($old && $old->[-1]->is_websocket) {
        $old->[-1]->client_close;
        $old = undef;
        $self->{_processing} -= 1;
        delete $self->{_cs}->{$id};
        $self->_drop($id);
    }

    # Upgrade connection to WebSocket
    else {

        # WebSocket upgrade
        $new = $self->_upgrade($id) if $old;

        # Drop old connection so we can reuse it
        $self->_drop($id) unless $new;
    }

    # Finish pipeline
    if ($old) {

        # Extract cookies
        if (my $jar = $self->cookie_jar) { $jar->extract(@$old) }

        # Counter
        $self->{_processing} -= 1 unless $new;

        # Redirect
        unless ($self->_redirect($c, $old)) {

            # Callback
            my $cb = $c->{cb};
            my $p = $new ? [$new] : $old;
            local $self->{tx} = $p->[-1];
            $self->$cb(@$p) if $cb;
        }
    }

    # Stop ioloop
    $self->ioloop->stop if !$self->{_is_async} && !$self->{_processing};
}

sub _pipeline_info {
    my ($self, $p) = @_;

    # First transaction
    my $c = $p->[-1];

    # Info
    my $req    = $c->req;
    my $url    = $req->url;
    my $scheme = $url->scheme || 'http';
    my $host   = $url->ihost;
    my $port   = $url->port;

    # Check for connect transaction
    my $connect;
    my $method = $req->method  || '';
    my $code   = $c->res->code || '';
    $connect = 1
      if ($method eq 'CONNECT' && $code eq '200')
      || ($method ne 'CONNECT' && $scheme eq 'https');

    # Proxy
    if ((my $proxy = $req->proxy) && !$connect) {
        $scheme = $proxy->scheme;
        $host   = $proxy->ihost;
        $port   = $proxy->port;
    }

    # Default port
    $port ||= $scheme eq 'https' ? 443 : 80;

    return ($scheme, $host, $port);
}

# It's greeat! We can do *anything* now that Science has invented Magic.
sub _prepare_pipeline {
    my ($self, $p, $cb) = @_;

    # Prepare all transactions
    for my $tx (@$p) {

        # Embedded server
        if ($self->app) {
            my $url = $tx->req->url->to_abs;
            next if $url->host;
            $url->scheme('http');
            $url->host('localhost');
            $url->port($self->test_server);
            $tx->req->url($url);
        }

        # Request
        my $req = $tx->req;

        # Scheme
        my $scheme = $req->url->scheme || '';

        # Detect proxy
        $self->detect_proxy if $ENV{MOJO_PROXY};

        # HTTP proxy
        if (my $proxy = $self->http_proxy) {
            $req->proxy($proxy) if !$req->proxy && $scheme eq 'http';
        }

        # HTTPS proxy
        if (my $proxy = $self->https_proxy) {
            $req->proxy($proxy) if !$req->proxy && $scheme eq 'https';
        }

        # Make sure WebSocket requests have an origin header
        my $headers = $req->headers;
        $headers->origin($req->url)
          if $headers->upgrade && !$headers->origin;

        # We identify ourself
        $headers->user_agent('Mozilla/5.0 (compatible; Mojolicious; Perl)')
          unless $headers->user_agent;
    }

    # Inject cookies
    if (my $jar = $self->cookie_jar) { $jar->inject(@$p) }

    # Connect
    return unless my $id = $self->_connect($p, $cb);

    # Connection
    my $c = $self->{_cs}->{$id};
    $c->{writer} = 0;
    $c->{reader} = 0;

    # Weaken
    weaken $self;

    # Callbacks
    for my $tx (@$p) {

        # State change callback
        $tx->state_cb(sub { $self->_state($id, @_) });
    }

    # Counter
    $self->{_processing} ||= 0;
    $self->{_processing} += 1;

    return $id;
}

# Hey, Weener Boy... where do you think you're going?
sub _proxy_connect {
    my ($self, $p, $cb) = @_;

    # First transaction
    my $c = $p->[0];

    # Request
    my $req = $c->req;

    # Proxy
    return
      unless ($req->headers->upgrade || '') eq 'WebSocket'
      || ($req->proxy && ($req->url->scheme || '') eq 'https');
    return unless my $proxy = $c->req->proxy;

    # CONNECT request
    my $new = $self->build_tx(CONNECT => $c->req->url->clone);
    $new->req->proxy($proxy);

    # Prepare
    $self->_prepare_pipeline(
        [$new] => sub {
            my ($self, $tx) = @_;

            # Failed
            unless (($tx->res->code || '') eq '200') {
                $_->error('Proxy connection failed.', 500) for @$p;
                $self->$cb(@$p) if $cb;
                return;
            }

            # TLS upgrade
            if ($tx->req->url->scheme eq 'https') {

                # Connection from keep alive cache
                return unless my $old = $tx->connection;

                # Start TLS
                my $new = $self->ioloop->start_tls(
                    $old,
                    tls_ca_file => $self->tls_ca_file || $ENV{MOJO_CA_FILE},
                    tls_verify_cb => $self->tls_verify_cb
                );

                # Cleanup
                $p->[0]->req->proxy(undef);
                delete $self->{_cs}->{$old};
                $tx->connection($new);
            }

            # Share connection
            $c->connection($tx->connection);

            # Queue real pipeline
            $self->_prepare_pipeline($p, $cb);
        }
    );

    return 1;
}

sub _queue_or_process_tx {
    my ($self, $tx, $cb) = @_;

    # Quick process
    if (!$cb && !$self->{_is_async}) {
        $self->process($tx, sub { $tx = $_[1] });
        return $tx;
    }

    # Queue transaction with callback
    $self->queue($tx, $cb);
}

# Have you ever seen that Blue Man Group? Total ripoff of the Smurfs.
# And the Smurfs, well, they SUCK.
sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Pipeline
    if (my $p = $c->{p}) {

        # Read
        $p->[$c->{reader}]->client_read($chunk);
    }

    # Corrupted connection
    else { $self->_drop($id) }
}

sub _redirect {
    my ($self, $c, $p) = @_;

    # Transaction
    my $tx = $p->[-1];

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
    $new->previous($p);

    # Queue redirected request
    my $nid = $self->_prepare_pipeline([$new], $c->{cb});

    # Create new connection
    $self->{_cs}->{$nid}->{redirects} = $r + 1;

    # Redirecting
    return 1;
}

# Oh, I'm in no condition to drive. Wait a minute.
# I don't have to listen to myself. I'm drunk.
sub _state {
    my ($self, $id, $tx) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Reader
    my $reader = $c->{p}->[$c->{reader}];
    if ($reader && $reader->is_finished) {
        $c->{reader}++;

        # Leftovers
        if (defined(my $leftovers = $reader->client_leftovers)) {
            $reader = $c->{p}->[$c->{reader}];
            $reader->client_read($leftovers);
        }
    }

    # Finished
    return $self->_handle_response($id) unless $c->{p}->[$c->{reader}];

    # Writer
    my $writer = $c->{p}->[$c->{writer}];
    $c->{writer}++
      if $writer && $writer->is_state('read_response');

    # Current
    my $current = $c->{writer};
    $current = $c->{reader} unless $c->{p}->[$c->{writer}];

    return $c->{p}->[$current]->is_writing
      ? $self->ioloop->writing($id)
      : $self->ioloop->not_writing($id);
}

# Once the government approves something, it's no longer immoral!
sub _upgrade {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Last transaction
    my $old = $c->{p}->[-1];

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

    # WebSocket challenge
    my $solution =
      $self->websocket_challenge(scalar $headers->sec_websocket_key1,
        scalar $headers->sec_websocket_key2, $req->body);
    $old->error('WebSocket challenge failed.') and return
      unless $solution eq $res->body;

    # Upgrade to WebSocket transaction
    my $new = Mojo::Transaction::WebSocket->new(handshake => $old);
    $c->{p} = [$new];
    $new->kept_alive($old->kept_alive);

    # Cleanup connection
    $c->{reader} = 0;
    $c->{writer} = 0;

    # Upgrade connection timeout
    $self->ioloop->connection_timeout($id, $self->websocket_timeout);

    # Weaken
    weaken $self;

    # State change callback
    $new->state_cb(
        sub {
            my $tx = shift;

            # Finished
            return $self->_handle_response($id) if $tx->is_finished;

            # Writing
            $tx->is_writing
              ? $self->ioloop->writing($id)
              : $self->ioloop->not_writing($id);
        }
    );

    return $new;
}

# Oh well. At least we'll die doing what we love: inhaling molten rock.
sub _write {
    my ($self, $loop, $id) = @_;

    # Connection
    my $c = $self->{_cs}->{$id};

    # Pipeline
    if (my $p = $c->{p}) {

        # Get chunk
        return $p->[$c->{writer}]->client_write;
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

    # Grab the latest Mojolicious release :)
    my $latest = 'http://mojolicious.org/Mojolicious-latest.tar.gz';
    print $client->get($latest)->res->body;

    # Quick JSON request
    my $trends = 'http://search.twitter.com/trends.json';
    print $client->get($trends)->res->json->{trends}->[0]->{name};

    # Extract data from HTML and XML resources
    print $client->get('http://mojolicious.org')->res->dom->at('title')->text;

    # Scrape the latest headlines from a news site
    my $news = 'http://digg.com';
    $client->get($news)->res->dom->search("h3 > a.offsite")->each(sub {
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

    # Parallel requests
    my $callback = sub { print shift->res->body };
    $client->get('http://mojolicious.org' => $callback);
    $client->get('http://search.cpan.org' => $callback);
    $client->process;

    # Async request
    $client->async->get(
        'http://kraih.com' => sub {
            my $client = shift;
            print $client->res->code;
        }
    )->process;

    # Websocket request
    $client->websocket(
        'ws://websockets.org:8787' => sub {
            my $client = shift;
            $client->receive_message(
                sub {
                    my ($client, $message) = @_;
                    print "$message\n";
                    $client->finish;
                }
            );
            $client->send_message('hi there!');
        }
    )->process;

=head1 DESCRIPTION

L<Mojo::Client> is a full featured async io HTTP 1.1 and WebSocket client
with C<IPv6>, C<TLS>, C<epoll> and C<kqueue> support.

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
to C<0>.

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
Use C<singleton> if you want to share keep alive connections with other
clients.

=head2 C<async>

    my $async = $client->async;

Clone client instance and start using the global shared L<Mojo::IOLoop>
singleton.
Note that parallel requests are always handled asynchronous, this only
affects shared L<Mojo::IOLoop> instances.

    $client->async->get('http://mojolicious.org' => sub {
        my $client = shift;
        print $client->res->body;
    })->process;

=head2 C<build_form_tx>

    my $tx = $client->build_form_tx('http://kraih.com/foo' => {test => 123});
    my $tx = $client->build_form_tx(
        'http://kraih.com/foo'
        'UTF-8',
        {test => 123}
    );
    my $tx = $client->build_form_tx(
        'http://kraih.com/foo',
        {test => 123},
        {Expect => '100-continue'}
    );
    my $tx = $client->build_form_tx(
        'http://kraih.com/foo',
        'UTF-8',
        {test => 123},
        {Expect => '100-continue'}
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

Versatile transaction builder for forms.

    my $tx = $client->build_form_tx('http://kraih.com/foo' => {test => 123});
    $tx->res->body(sub { print $_[1] });
    $client->process($tx);

=head2 C<build_tx>

    my $tx = $client->build_tx(GET => 'http://mojolicious.org');
    my $tx = $client->build_tx(
        GET => 'http://kraih.com' => {Connection => 'close'}
    );
    my $tx = $client->build_tx(
        POST => 'http://kraih.com' => {Connection => 'close'} => 'Hi!'
    );

Versatile general purpose transaction builder.

    my $tx = $client->build_tx(GET => 'http://mojolicious.org');
    $tx->res->body(sub { print $_[1] });
    $client->process($tx);

=head2 C<build_websocket_tx>

    my $tx = $client->build_websocket_tx('ws://localhost:3000' => sub {...});
    my $tx = $client->build_websocket_tx(
        'ws://localhost:3000' => {'User-Agent' => 'Agent 1.0'} => sub {...}
    );

Versatile WebSocket transaction builder.

=head2 C<clone>

    my $clone = $client->clone;

Clone client the instance.
Note that cloned clients don't share the same keep alive queue, so you could
easily run out of file descriptors with too many active clients.

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

=head2 C<detect_proxy>

    $client = $client->detect_proxy;

Check environment variables for proxy information.

=head2 C<finish>

    $client->finish;

Finish the WebSocket connection, only available from callbacks.

=head2 C<finished>

    $client->finished(sub {...});

Callback signaling that peer finished the WebSocket connection, only
available from callbacks.

    $client->finished(sub {
        my $client = shift;
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
        my ($client, $p) = @_;
    });

=head2 C<receive_message>

    $client->receive_message(sub {...});

Receive messages via WebSocket, only available from callbacks.

    $client->receive_message(sub {
        my ($client, $message) = @_;
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

=head2 C<test_server>

    my $port = $client->test_server;

Starts a test server for C<app> if neccessary and returns the port number.
Note that this method is EXPERIMENTAL and might change without warning!

=head2 C<websocket>

    $client = $client->websocket('ws://localhost:3000' => sub {...});
    $client = $client->websocket(
        'ws://localhost:3000' => {'User-Agent' => 'Agent 1.0'} => sub {...}
    );

Open a WebSocket connection with transparent handshake.

=head2 C<websocket_challenge>

    my $solution = $client->websocket_challenge($key1, $key2, $key3);

Calculate the solution for a websocket challenge.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
