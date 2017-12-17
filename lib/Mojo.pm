package Mojo;
use Mojo::Base -base;

# "Professor: These old Doomsday devices are dangerously unstable. I'll rest
#             easier not knowing where they are."
use Carp ();
use Mojo::Log;
use Mojo::Transaction::HTTP;
use Mojo::Util;

has log => sub { Mojo::Log->new };

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

The class L<Mojo> serves as an abstract base class for web frameworks like
L<Mojolicious> and L<Mojolicious::Lite>. It provides essentials like the
L</"log"> attribute, which web servers like L<Mojo::Server::Daemon> depend on.

See L<Mojolicious::Guides> for more!

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

=head2 log

  my $log = $app->log;
  $app    = $app->log(Mojo::Log->new);

The logging layer of your application, defaults to a L<Mojo::Log> object.

  # Log debug message
  $app->log->debug('It works');

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
