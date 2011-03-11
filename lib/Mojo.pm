package Mojo;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Home;
use Mojo::Log;
use Mojo::Transaction::HTTP;
use Mojo::Transaction::WebSocket;

has home => sub { Mojo::Home->new };
has log  => sub { Mojo::Log->new };
has on_build_tx => sub {
  sub { Mojo::Transaction::HTTP->new }
};
has on_websocket => sub {
  sub { Mojo::Transaction::WebSocket->new(handshake => pop) }
};
has ua => sub {
  my $self = shift;

  # Singleton user agent
  require Mojo::UserAgent;
  my $ua = Mojo::UserAgent->new(app => $self, log => $self->log);

  return $ua;
};

# DEPRECATED in Smiling Cat Face With Heart-Shaped Eyes!
*client = sub {
  warn <<EOF;
Mojo->client is DEPRECATED in favor of Mojo->us!!!
EOF

  # Singleton client
  require Mojo::Client;
  my $client = Mojo::Client->singleton;

  # Inherit logger
  $client->log(shift->log);

  return $client;
};

# "Oh, so they have internet on computers now!"
sub new {
  my $self = shift->SUPER::new(@_);

  # Home
  $self->home->detect(ref $self);

  # Log directory
  $self->log->path($self->home->rel_file('log/mojo.log'))
    if -w $self->home->rel_file('log');

  return $self;
}

sub handler { croak 'Method "handler" not implemented in subclass' }

1;
__END__

=head1 NAME

Mojo - The Box!

=head1 SYNOPSIS

  use Mojo::Base 'Mojo';

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

    # Resume transaction
    $tx->resume;
  }

=head1 DESCRIPTION

Mojo provides a flexible runtime environment for Perl web frameworks.
It provides all the basic tools and helpers needed to write simple web
applications and higher level web frameworks such as L<Mojolicious>.

See L<Mojolicious> for more!

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

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

=head2 C<on_websocket>

  my $cb = $app->on_websocket;
  $app   = $app->on_websocket(sub { ... });

The websocket handshake callback, by default it builds a
L<Mojo::Transaction::WebSocket> object and handles the response for the
handshake request.

=head2 C<ua>

  my $ua = $app->ua;
  $app   = $app->ua(Mojo::UserAgent->new);

A full featured HTTP 1.1 user agent for use in your applications, by default
a L<Mojo::UserAgent> object.

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

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
