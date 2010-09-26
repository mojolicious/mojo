package Mojo;

use strict;
use warnings;

use base 'Mojo::Base';

use Carp 'croak';
use Mojo::Client;
use Mojo::Commands;
use Mojo::Home;
use Mojo::Log;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;

__PACKAGE__->attr(client => sub { Mojo::Client->singleton });
__PACKAGE__->attr(home   => sub { Mojo::Home->new });
__PACKAGE__->attr(log    => sub { Mojo::Log->new });
__PACKAGE__->attr(
    on_build_tx => sub {
        sub { return Mojo::Transaction::HTTP->new }
    }
);
__PACKAGE__->attr(
    on_websocket_handshake => sub {
        sub {
            return Mojo::Transaction::WebSocket->new(handshake => pop)
              ->server_handshake;
          }
    }
);

# DEPRECATED in Comet!
*build_tx_cb            = \&on_build_tx;
*websocket_handshake_cb = \&on_websocket_handshake;

# Oh, so they have internet on computers now!
sub new {
    my $self = shift->SUPER::new(@_);

    # Home
    $self->home->detect(ref $self);

    # Client logger
    $self->client->log($self->log);

    # Log directory
    $self->log->path($self->home->rel_file('log/mojo.log'))
      if -w $self->home->rel_file('log');

    return $self;
}

# Bart, stop pestering Satan!
sub handler { croak 'Method "handler" not implemented in subclass' }

# Start command system
sub start {
    my $class = shift;

    # We can be called on class or instance
    $class = ref $class || $class;

    # We are the application
    $ENV{MOJO_APP} ||= $class;

    # Start!
    return Mojo::Commands->start(@_);
}

1;
__END__

=head1 NAME

Mojo - The Box!

=head1 SYNOPSIS

    use base 'Mojo';

    # All the complexities of CGI, FastCGI, PSGI, HTTP and WebSockets get
    # reduced to a single method call!
    sub handler {
        my ($self, $tx) = @_;

        # Request
        my $method = $tx->req->method;
        my $path   = $tx->req->url->path;

        # Response
        $tx->res->code(200);
        $tx->res->headers->content_type('text/plain');
        $tx->res->body("$method request for $path!");
        $tx->resume;
    }

=head1 DESCRIPTION

Mojo provides a flexible runtime environment for Perl web frameworks.
It provides all the basic tools and helpers needed to write simple web
applications and higher level web frameworks such as L<Mojolicious>.

See L<Mojolicious> for more!

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

=head2 C<client>

    my $client = $app->client;
    $app       = $app->client(Mojo::Client->new);

A full featured HTTP 1.1 client for use in your applications, by default a
L<Mojo::Client> object.

=head2 C<home>

    my $home = $app->home;
    $app     = $app->home(Mojo::Home->new);

The home directory of your application, by default a L<Mojo::Home> object
which stringifies to the actual path.

=head2 C<log>

    my $log = $app->log;
    $app    = $app->log(Mojo::Log->new);
    
The logging layer of your application, by default a L<Mojo::Log> object.

=head2 C<on_build_tx>

    my $cb = $app->on_build_tx;
    $app   = $app->on_build_tx(sub { ... });

The transaction builder callback, by default it builds a
L<Mojo::Transaction::HTTP> object.

=head2 C<on_websocket_handshake>

    my $cb = $app->on_websocket_handshake;
    $app   = $app->on_websocket_handshake(sub { ... });

The websocket handshake callback, by default it builds a
L<Mojo::Transaction::WebSocket> object and handles the response for the
handshake request.

=head1 METHODS

L<Mojo> inherits all methods from L<Mojo::Base> and implements the following
new ones.

=head2 C<new>

    my $app = Mojo->new;

Construct a new L<Mojo> application.
Will automatically detect your home directory and set up logging to
C<log/mojo.log> if there's a log directory.

=head2 C<handler>

    $tx = $app->handler($tx);

The handler is the main entry point to your application or framework and
will be called for each new transaction, usually a L<Mojo::Transaction::HTTP>
or L<Mojo::Transaction::WebSocket> object.

    sub handler {
        my ($self, $tx) = @_;
    }

=head2 C<start>

    Mojo->start;
    Mojo->start('daemon');

Start the L<Mojo::Commands> command line interface for your application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
