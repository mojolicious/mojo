# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojo::Client;

use strict;
use warnings;

use base 'Mojo::Base';
use bytes;

use Carp 'croak';
use Mojo::ByteStream 'b';
use Mojo::Content::MultiPart;
use Mojo::Content::Single;
use Mojo::CookieJar;
use Mojo::IOLoop;
use Mojo::Parameters;
use Mojo::Server::Daemon;
use Mojo::Transaction::Pipeline;
use Mojo::Transaction::Single;
use Mojo::Transaction::WebSocket;
use Scalar::Util 'weaken';

__PACKAGE__->attr([qw/app default_cb tls_ca_file tls_verify_cb/]);
__PACKAGE__->attr([qw/continue_timeout max_keep_alive_connections/] => 5);
__PACKAGE__->attr(cookie_jar => sub { Mojo::CookieJar->new });
__PACKAGE__->attr(ioloop     => sub { Mojo::IOLoop->singleton });
__PACKAGE__->attr(keep_alive_timeout => 15);
__PACKAGE__->attr(max_redirects      => 0);
__PACKAGE__->attr('tx');

__PACKAGE__->attr(_cache       => sub { [] });
__PACKAGE__->attr(_connections => sub { {} });
__PACKAGE__->attr([qw/_finite _queued/] => 0);
__PACKAGE__->attr('_port');

# Make sure we leave a clean ioloop behind
sub DESTROY {
    my $self = shift;

    # Shortcut
    return unless $self->ioloop;

    # Cleanup active connections
    for my $id (keys %{$self->_connections}) {
        $self->ioloop->drop($id);
    }

    # Cleanup keep alive connections
    for my $cached (@{$self->_cache}) {
        my $id = $cached->[1];
        $self->ioloop->drop($id);
    }
}

sub delete { shift->_build_tx('DELETE', @_) }

sub finish {
    my $self = shift;

    # WebSocket?
    croak 'No WebSocket connection to finish.' unless $self->tx->is_websocket;

    # Finish
    $self->tx->finish;
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
    for my $name (sort keys %$form) {

        # Array
        if (ref $form->{$name} eq 'ARRAY') {
            for my $value (@{$form->{$name}}) {
                $params->append($name,
                    $encoding
                    ? b($value)->encode($encoding)->to_string
                    : $value);
            }
        }

        # Single value
        else {
            my $value = $form->{$name};
            $params->append($name,
                $encoding
                ? b($value)->encode($encoding)->to_string
                : $value);
        }
    }

    # Transaction
    my $tx = Mojo::Transaction::Single->new;
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

    # Queue transaction with callback
    $self->queue($tx, $cb);
}

sub process {
    my $self = shift;

    # Queue transactions
    $self->queue(@_) if @_;

    # Already running
    return $self if $self->_finite;

    # Loop is finite
    $self->_finite(1);

    # Start ioloop
    $self->ioloop->start;

    # Loop is not finite if it's still running
    $self->_finite(undef);

    return $self;
}

sub put { shift->_build_tx('PUT', @_) }

sub queue {
    my $self = shift;

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Embedded server
    $self->_prepare_server if $self->app;

    # Queue transactions
    $self->_queue($_, $cb) for @_;

    return $self;
}

sub receive_message {
    my $self = shift;

    # WebSocket?
    croak 'No WebSocket connection to receive messages from.'
      unless $self->tx->is_websocket;

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

sub req { shift->tx->req(@_) }
sub res { shift->tx->res(@_) }

sub send_message {
    my $self = shift;

    # WebSocket?
    croak 'No WebSocket connection to send message to.'
      unless $self->tx->is_websocket;

    # Send
    $self->tx->send_message(@_);
}

sub websocket {
    my $self = shift;

    # New WebSocket
    my $tx = Mojo::Transaction::Single->new;

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
        $part->headers->content_disposition(qq/form-data; name="$name"/);

        # Content-Type
        my $type = 'text/plain';
        $type .= qq/;charset=$encoding/ if $encoding;
        $part->headers->content_type($type);

        # Value
        my $value =
          ref $form->{$name} eq 'ARRAY'
          ? join ',', @{$form->{$name}}
          : $form->{$name};
        $part->asset->add_chunk($value);

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
    my $tx = Mojo::Transaction::Single->new;

    # Request
    my $req = $tx->req;

    # Method
    $req->method(shift);

    # URL
    $req->url->parse(shift);

    # Callback
    my $cb = pop @_ if ref $_[-1] && ref $_[-1] eq 'CODE';

    # Headers
    $req->headers->from_hash(ref $_[0] eq 'HASH' ? $_[0] : {@_});

    # Queue transaction with callback
    $self->queue($tx, $cb);
}

sub _connect {
    my ($self, $id) = @_;

    # Transaction
    my $tx = $self->_connections->{$id}->{tx};

    # Connected
    $tx->client_connected;

    # Store connection information in transaction
    my $local = $self->ioloop->local_info($id);
    $tx->local_address($local->{address});
    $tx->local_port($local->{port});
    my $remote = $self->ioloop->remote_info($id);
    $tx->remote_address($remote->{address});
    $tx->remote_port($remote->{port});

    # Keep alive timeout
    $self->ioloop->connection_timeout($id => $self->keep_alive_timeout);
}

sub _deposit {
    my ($self, $name, $id) = @_;

    # Limit keep alive connections
    while (@{$self->_cache} >= $self->max_keep_alive_connections) {
        my $cached = shift @{$self->_cache};
        $self->_drop($cached->[1]);
    }

    # Deposit
    push @{$self->_cache}, [$name, $id];
}

sub _drop {
    my ($self, $id) = @_;

    # Keep connection alive
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Read only
        $self->ioloop->not_writing($id);

        # Deposit
        my $info    = $tx->client_info;
        my $address = $info->{address};
        my $port    = $info->{port};
        my $scheme  = $info->{scheme};
        $self->_deposit("$scheme:$address:$port", $id) if $tx->keep_alive;
    }

    # Connection close
    else {
        $self->ioloop->finish($id);
        $self->_withdraw($id);
    }

    # Drop connection
    delete $self->_connections->{$id};
}

sub _error {
    my ($self, $loop, $id, $error) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Add error message
        $tx->error($error);
    }

    # Finish
    $self->_finish($id);
}

sub _fetch_cookies {
    my ($self, $p) = @_;

    # Shortcut
    return unless $self->cookie_jar;

    # Pipeline
    if ($p->is_pipeline) {

        # Find cookies for all transactions
        for my $tx (@{$p->active}) {

            # URL
            my $url = $tx->req->url->clone;
            if (my $host = $tx->req->headers->host) { $url->host($host) }

            # Find
            $tx->req->cookies($self->cookie_jar->find($url));
        }
    }

    # Single
    else {

        # URL
        my $url = $p->req->url->clone;
        if (my $host = $p->req->headers->host) { $url->host($host) }

        # Find
        $p->req->cookies($self->cookie_jar->find($p->req->url));
    }
}

sub _finish {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->_connections->{$id};

    # Transaction
    my $tx = $c->{tx};

    # Just drop WebSockets
    if ($tx && $tx->is_websocket) {
        $tx = undef;
        $self->_queued($self->_queued - 1);
        delete $self->_connections->{$id};
        $self->_drop($id);
    }

    # Normal transaction
    else {

        # WebSocket upgrade?
        $self->_upgrade($id) if $tx;

        # Drop old connection so we can reuse it
        $self->_drop($id) unless $tx && $c->{tx}->is_websocket;
    }

    # Redirects
    my $r = $c->{redirects} || 0;

    # History
    my $h = $c->{history} || [];

    # Transaction still in progress
    if ($tx) {

        # Cookies to the jar
        $self->_store_cookies($tx);

        # Counter
        $self->_queued($self->_queued - 1) unless $c->{tx}->is_websocket;

        # Redirect?
        my $max = $self->max_redirects;
        if ($r < $max && (my $new = $self->_redirect($tx))) {

            # Queue redirected request
            my $nid = $self->_queue($new, $c->{cb});

            # Create new conenction
            my $nc = $self->_connections->{$nid};
            push @$h, $tx;
            $nc->{history}   = $h;
            $nc->{redirects} = $r + 1;

            # Done
            return;
        }

        # Callback
        else {

            # Get callback
            my $cb = $c->{cb} || $self->default_cb;

            # Callback
            $tx = $c->{tx};
            local $self->{tx} = $tx;
            $self->$cb($tx, $c->{history}) if $cb;
        }
    }

    # Stop ioloop
    $self->ioloop->stop if $self->_finite && !$self->_queued;
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

sub _hup {
    my ($self, $loop, $id) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Add error message
        $tx->error('Connection closed.');
    }

    # Finish
    $self->_finish($id);
}

sub _prepare_server {
    my $self = shift;

    # Server already prepared
    return if $self->_port;

    # Server
    my $server = Mojo::Server::Daemon->new;
    my $port   = $self->ioloop->generate_port;
    die "Couldn't find a free TCP port for testing.\n" unless $port;
    $self->_port($port);
    $server->listen("http://*:$port");
    ref $self->app
      ? $server->app($self->app)
      : $server->app_class($self->app);
    $server->app->client->app($server->app);
    $server->lock_file($server->lock_file . '.test');
    $server->prepare_lock_file;
    $server->prepare_ioloop;
}

sub _queue {
    my ($self, $tx, $cb) = @_;

    # Embedded server
    if ($self->app) {
        my @active = $tx->is_pipeline ? @{$tx->active} : $tx;
        for my $active (@active) {
            my $url = $active->req->url->to_abs;
            next if $url->host;
            $url->scheme('http');
            $url->host('localhost');
            $url->port($self->_port);
            $active->req->url($url);
        }
        $tx->client_info(
            {scheme => 'http', address => 'localhost', port => $self->_port})
          if $tx->is_pipeline && !$tx->client_info->{address};
    }

    # Make sure WebSocket requests have an origin header
    unless ($tx->is_pipeline) {
        my $req = $tx->req;
        $req->headers->origin($req->url)
          if $req->headers->upgrade && !$req->headers->origin;
    }

    # Cookies from the jar
    $self->_fetch_cookies($tx);

    # Info
    my $info    = $tx->client_info;
    my $address = $info->{address};
    my $port    = $info->{port};
    my $scheme  = $info->{scheme};

    # Weaken
    weaken $self;

    # Connect callback
    my $connected = sub {
        my ($loop, $id) = @_;

        # Connected
        $self->_connect($id);
    };

    # Cached connection
    my $id;
    if ($id = $self->_withdraw("$scheme:$address:$port")) {

        # Writing
        $self->ioloop->writing($id);

        # Kept alive
        $tx->kept_alive(1);

        # Add new connection
        $self->_connections->{$id} = {cb => $cb, tx => $tx};

        # Connected
        $self->_connect($id);
    }

    # New connection
    else {

        # Connect
        $id = $self->ioloop->connect(
            cb      => $connected,
            address => $address,
            port    => $port,
            tls     => $scheme eq 'https' ? 1 : 0,
            tls_ca_file => $self->tls_ca_file || $ENV{MOJO_CA_FILE},
            tls_verify_cb => $self->tls_verify_cb
        );

        # Error
        unless (defined $id) {
            $tx->error("Couldn't create connection.");
            $cb ||= $self->default_cb;
            $self->$cb($tx) if $cb;
            return;
        }

        # Callbacks
        $self->ioloop->error_cb($id => sub { $self->_error(@_) });
        $self->ioloop->hup_cb($id => sub { $self->_hup(@_) });
        $self->ioloop->read_cb($id => sub { $self->_read(@_) });
        $self->ioloop->write_cb($id => sub { $self->_write(@_) });

        # Add new connection
        $self->_connections->{$id} = {cb => $cb, tx => $tx};
    }

    # State change callback
    $tx->state_cb(
        sub {
            my $tx = shift;

            # Finished?
            return $self->_finish($id) if $tx->is_finished;

            # Writing?
            $tx->client_is_writing
              ? $self->ioloop->writing($id)
              : $self->ioloop->not_writing($id);
        }
    );

    # Counter
    $self->_queued($self->_queued + 1);

    return $id;
}

sub _read {
    my ($self, $loop, $id, $chunk) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Read
        $tx->client_read($chunk);

        # WebSocket?
        return if $tx->is_websocket;

        # State machine
        $tx->client_spin;
    }

    # Corrupted connection
    else { $self->_drop($id) }
}

sub _redirect {
    my ($self, $tx) = @_;

    # Code
    return unless $tx->res->is_status_class('300');
    return if $tx->res->code == 305;

    # Location
    return unless my $location = $tx->res->headers->location;

    # Method
    my $method = $tx->req->method;
    $method = 'GET' unless $method =~ /^GET|HEAD$/i;

    # New transaction
    my $new = Mojo::Transaction::Single->new;
    $new->req->method($method);
    $new->req->url->parse($location);

    return $new;
}

sub _store_cookies {
    my ($self, $tx) = @_;

    # Shortcut
    return unless $self->cookie_jar;

    # Pipeline
    if ($tx->is_pipeline) {
        $self->cookie_jar->add($self->_fix_cookies($_, @{$_->res->cookies}))
          for @{$tx->finished};
    }

    # Single
    else {
        $self->cookie_jar->add(
            $self->_fix_cookies($tx, @{$tx->res->cookies}));
    }
}

sub _upgrade {
    my ($self, $id) = @_;

    # Connection
    my $c = $self->_connections->{$id};

    # Transaction
    my $tx = $c->{tx};

    # Pipeline?
    return if $tx->is_pipeline;

    # No handshake
    return unless $tx->req->headers->upgrade;

    # Handshake failed?
    return unless $tx->res->code == 101;

    # Start new WebSocket
    $c->{tx} = Mojo::Transaction::WebSocket->new(handshake => $tx);

    # Weaken
    weaken $self;

    # State change callback
    $c->{tx}->state_cb(
        sub {
            my $tx = shift;

            # Finished?
            return $self->_finish($id) if $tx->is_finished;

            # Writing?
            $tx->client_is_writing
              ? $self->ioloop->writing($id)
              : $self->ioloop->not_writing($id);
        }
    );
}

sub _withdraw {
    my ($self, $name) = @_;

    # Withdraw
    my $found;
    my @cache;
    for my $cached (@{$self->_cache}) {

        # Search for name or id
        $found = $cached->[1] and next
          if $cached->[1] eq $name || $cached->[0] eq $name;

        # Cache again
        push @cache, $cached;
    }
    $self->_cache(\@cache);

    return $found;
}

sub _write {
    my ($self, $loop, $id) = @_;

    # Transaction
    if (my $tx = $self->_connections->{$id}->{tx}) {

        # Get chunk
        my $chunk = $tx->client_get_chunk;

        # WebSocket?
        return $chunk if $tx->is_websocket;

        # State machine
        $tx->client_spin;

        return $chunk;
    }

    # Corrupted connection
    else { $self->_drop($id) }

    return;
}

1;
__END__

=head1 NAME

Mojo::Client - Client

=head1 SYNOPSIS

    use Mojo::Client;

    my $client = Mojo::Client->new;
    $client->get(
        'http://kraih.com' => sub {
            my $self = shift;
            print $self->res->code;
        }
    )->process;

=head1 DESCRIPTION

L<Mojo::Client> is a full featured async io HTTP 1.1 client.

It implements the most common HTTP verbs.
If you need something more custom you can create your own
L<Mojo::Transaction::Single> or L<Mojo::Trasaction::Pipeline> objects and
C<queue> them.
All of the verbs take an optional set of headers as a hash or hash reference,
as well as an optional callback sub reference.

=head1 ATTRIBUTES

L<Mojo::Client> implements the following attributes.

=head2 C<app>

    my $app = $client->app;
    $client = $client->app(MyApp->new);

A Mojo application to associate this client with.
If set, requests will be processed in this application.

=head2 C<continue_timeout>

    my $timeout = $client->continue_timeout;
    $client     = $client->continue_timeout(5);

Time to wait for a 100 continue in seconds, defaults to C<5>.

=head2 C<cookie_jar>

    my $cookie_jar = $client->cookie_jar;
    $client        = $client->cookie_jar(Mojo::CookieJar->new);

Cookie jar to use for this clients requests, by default a L<Mojo::CookieJar>
object.

=head2 C<default_cb>

    my $cb  = $client->default_cb;
    $client = $client->default_cb(sub {...});

A default callback to use if your request does not specify a callback.

    $client->default_cb(sub {
        my ($self, $tx) = @_;
    });

=head2 C<ioloop>

    my $loop = $client->ioloop;
    $client  = $client->ioloop(Mojo::IOLoop->new);

Loop object to use for io operations, by default it will use the global
L<Mojo::IOLoop> singleton.
You can force the client to block on C<process> by creating a new loop
object.

=head2 C<keep_alive_timeout>

    my $keep_alive_timeout = $client->keep_alive_timeout;
    $client                = $client->keep_alive_timeout(15);

Timeout in seconds for keep alive between requests, defaults to C<15>.

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

TLS certificate authority file to use, defaults to the MOJO_CA_FILE
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

=head1 METHODS

L<Mojo::Client> inherits all methods from L<Mojo::Base> and implements the
following new ones.

=head2 C<new>

    my $client = Mojo::Client->new;

Construct a new L<Mojo::Client> object.
As usual, you can pass any of the attributes above to the constructor.

=head2 C<delete>

    $client = $client->delete('http://kraih.com' => sub {...});
    $client = $client->delete(
        'http://kraih.com' => (Connection => 'close') => sub {...}
    );

Send a HTTP C<DELETE> request.

=head2 C<finish>

    $client->finish;

Finish the WebSocket connection, only available from callbacks.

=head2 C<get>

    $client = $client->get('http://kraih.com' => sub {...});
    $client = $client->get(
        'http://kraih.com' => (Connection => 'close') => sub {...}
    );

Send a HTTP C<GET> request.

=head2 C<head>

    $client = $client->head('http://kraih.com' => sub {...});
    $client = $client->head(
        'http://kraih.com' => (Connection => 'close') => sub {...}
    );

Send a HTTP C<HEAD> request.

=head2 C<post>

    $client = $client->post('http://kraih.com' => sub {...});
    $client = $client->post(
        'http://kraih.com' => (Connection => 'close') => sub {...}
    );

Send a HTTP C<POST> request.

=head2 C<post_form>

    $client = $client->post_form('/foo' => {test => 123}, sub {...});
    $client = $client->post_form(
        '/foo',
        'UTF-8',
        {test => 123},
        sub {...}
    );
    $client = $client->post_form(
        '/foo',
        {test => 123},
        {Expect => '100-continue'},
        sub {...}
    );
    $client = $client->post_form(
        '/foo',
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
Will be blocking unless you have a global shared ioloop.

=head2 C<put>

    $client = $client->put('http://kraih.com' => sub {...});
    $client = $client->put(
        'http://kraih.com' => (Connection => 'close') => sub {...}
    );

Send a HTTP C<PUT> request.

=head2 C<queue>

    $client = $client->queue(@transactions);
    $client = $client->queue(@transactions => sub {...});

Queue a list of transactions for processing.

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

=head2 C<send_message>

    $client->send_message('Hi there!');

Send a message via WebSocket, only available from callbacks.

=head2 C<websocket>

    $client = $client->websocket('ws://localhost:3000' => sub {...});
    $client = $client->websocket(
        'ws://localhost:3000' => ('User-Agent' => 'Agent 1.0') => sub {...}
    );

Open a WebSocket connection with transparent handshake.

=cut
