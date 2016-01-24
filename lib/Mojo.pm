package Mojo;
use Mojo::Base -base;

# "Professor: These old Doomsday devices are dangerously unstable. I'll rest
#             easier not knowing where they are."
use Carp ();
use Mojo::Home;
use Mojo::Log;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Mojo::Util;
use Scalar::Util ();

has home => sub { Mojo::Home->new->detect(ref shift) };
has log  => sub { Mojo::Log->new };
has ua   => sub {
  my $ua = Mojo::UserAgent->new;
  Scalar::Util::weaken $ua->server->app(shift)->{app};
  return $ua;
};

sub build_tx { Mojo::Transaction::HTTP->new }

sub config { Mojo::Util::_stash(config => @_) }

sub handler { Carp::croak 'Method "handler" not implemented in subclass' }

1;

=encoding utf8

=head1 NAME

Mojo - Web development toolkit

=head1 SYNOPSIS

  package MyApp;
  use Mojo::Base 'Mojo';

  # All the complexities of CGI, PSGI, HTTP and WebSockets get reduced to a
  # single method call!
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

A powerful web development toolkit, with all the basic tools and helpers needed
to write simple web applications and higher level web frameworks, such as
L<Mojolicious>. Some of the most commonly used tools are L<Mojo::UserAgent>,
L<Mojo::DOM>, L<Mojo::JSON>, L<Mojo::Server::Daemon>, L<Mojo::Server::Prefork>,
L<Mojo::IOLoop> and L<Mojo::Template>.

See L<Mojolicious::Guides> for more!

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

=head2 home

  my $home = $app->home;
  $app     = $app->home(Mojo::Home->new);

The home directory of your application, defaults to a L<Mojo::Home> object
which stringifies to the actual path.

  # Generate portable path relative to home directory
  my $path = $app->home->rel_file('data/important.txt');

=head2 log

  my $log = $app->log;
  $app    = $app->log(Mojo::Log->new);

The logging layer of your application, defaults to a L<Mojo::Log> object.

  # Log debug message
  $app->log->debug('It works');

=head2 ua

  my $ua = $app->ua;
  $app   = $app->ua(Mojo::UserAgent->new);

A full featured HTTP user agent for use in your applications, defaults to a
L<Mojo::UserAgent> object.

  # Perform blocking request
  say $app->ua->get('example.com')->res->body;

=head1 METHODS

L<Mojo> inherits all methods from L<Mojo::Base> and implements the following
new ones.

=head2 build_tx

  my $tx = $app->build_tx;

Transaction builder, defaults to building a L<Mojo::Transaction::HTTP> object.

=head2 config

  my $hash = $app->config;
  my $foo  = $app->config('foo');
  $app     = $app->config({foo => 'bar', baz => 23});
  $app     = $app->config(foo => 'bar', baz => 23);

Application configuration.

  # Remove value
  my $foo = delete $app->config->{foo};

  # Assign multiple values at once
  $app->config(foo => 'test', bar => 23);

=head2 handler

  $app->handler(Mojo::Transaction::HTTP->new);

The handler is the main entry point to your application or framework and will
be called for each new transaction, which will usually be a
L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket> object. Meant to
be overloaded in a subclass.

  sub handler {
    my ($self, $tx) = @_;
    ...
  }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
