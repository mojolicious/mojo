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

__PACKAGE__->attr(
    build_tx_cb => sub {
        sub { return Mojo::Transaction::HTTP->new }
    }
);
__PACKAGE__->attr(client => sub { Mojo::Client->singleton });
__PACKAGE__->attr(home   => sub { Mojo::Home->new });
__PACKAGE__->attr(log    => sub { Mojo::Log->new });
__PACKAGE__->attr(
    websocket_handshake_cb => sub {
        sub {
            return Mojo::Transaction::WebSocket->new(handshake => pop)
              ->server_handshake;
          }
    }
);

# DEPRECATED in Snowman!
# Use $Mojolicious::VERSION instead
our $VERSION = '0.999929';

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

    # All the complexities of CGI, FastCGI, PSGI, HTTP and WebSocket get
    # reduced to a single method call!
    sub handler {
        my ($self, $tx) = @_;

        # Request
        my $method = $tx->req->method;
        my $path   = $tx->req->url->path;

        # Response
        $tx->res->headers->content_type('text/plain');
        $tx->res->body("$method request for $path!");
    }

=head1 DESCRIPTION

Mojo provides a flexible runtime environment for Perl web frameworks.
It provides all the basic tools and helpers needed to write simple web
applications and higher level web frameworks such as L<Mojolicious>.

See L<Mojolicious> for more!

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

=head2 C<build_tx_cb>

    my $cb = $mojo->build_tx_cb;
    $mojo  = $mojo->build_tx_cb(sub { ... });

The transaction builder callback, by default it builds a
L<Mojo::Transaction::HTTP> object.

=head2 C<client>

    my $client = $mojo->client;
    $mojo      = $mojo->client(Mojo::Client->new);

A full featured HTTP 1.1 client for use in your applications, by default a
L<Mojo::Client> object.

=head2 C<home>

    my $home = $mojo->home;
    $mojo    = $mojo->home(Mojo::Home->new);

The home directory of your application, by default a L<Mojo::Home> object
which stringifies to the actual path.

=head2 C<log>

    my $log = $mojo->log;
    $mojo   = $mojo->log(Mojo::Log->new);
    
The logging layer of your application, by default a L<Mojo::Log> object.

=head2 C<websocket_handshake_cb>

    my $cb = $mojo->websocket_handshake_cb;
    $mojo  = $mojo->websocket_handshake_cb(sub { ... });

The websocket handshake callback, by default it builds a
L<Mojo::Transaction::WebSocket> object and handles the response for the
handshake request.

=head1 METHODS

L<Mojo> inherits all methods from L<Mojo::Base> and implements the following
new ones.

=head2 C<new>

    my $mojo = Mojo->new;

Construct a new L<Mojo> application.
Will automatically detect your home directory and set up logging to
C<log/mojo.log> if there's a log directory.

=head2 C<handler>

    $tx = $mojo->handler($tx);

The handler is the main entry point to your application or framework and
will be called for each new transaction.

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
