package Mojo::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use FindBin;
use Mojo::Loader;
use Mojo::Util 'md5_sum';
use Scalar::Util 'blessed';

has app => sub { shift->build_app('Mojo::HelloWorld') };

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(request => sub { shift->app->handler(shift) });
  return $self;
}

sub build_app {
  my ($self, $app) = @_;
  local $ENV{MOJO_EXE};
  return $app->new unless my $e = Mojo::Loader->new->load($app);
  die ref $e ? $e : qq{Couldn't find application class "$app".\n};
}

sub build_tx { shift->app->build_tx }

sub load_app {
  my ($self, $path) = @_;

  # Clean environment (reset FindBin)
  {
    local $0 = $path;
    FindBin->again;
    local $ENV{MOJO_APP_LOADER} = 1;
    local $ENV{MOJO_EXE};

    # Try to load application from script into sandbox
    my $app = eval sprintf <<'EOF', md5_sum($path . $$);
package Mojo::Server::SandBox::%s;
my $app = do $path;
if (!$app && (my $e = $@ || $!)) { die $e }
$app;
EOF
    die qq{Couldn't load application from file "$path": $@} if !$app && $@;
    die qq{File "$path" did not return an application object.\n}
      unless blessed $app && $app->isa('Mojo');
    $self->app($app);
  };
  FindBin->again;

  return $self->app;
}

sub run { croak 'Method "run" not implemented by subclass' }

1;

=head1 NAME

Mojo::Server - HTTP server base class

=head1 SYNOPSIS

  package Mojo::Server::MyServer;
  use Mojo::Base 'Mojo::Server';

  sub run {
    my $self = shift;

    # Get a transaction
    my $tx = $self->build_tx;

    # Emit "request" event
    $self->emit(request => $tx);
  }

=head1 DESCRIPTION

L<Mojo::Server> is an abstract HTTP server base class.

=head1 EVENTS

L<Mojo::Server> inherits all events from L<Mojo::EventEmitter> and can emit
the following new ones.

=head2 request

  $server->on(request => sub {
    my ($server, $tx) = @_;
    ...
  });

Emitted when a request is ready and needs to be handled.

  $server->unsubscribe('request');
  $server->on(request => sub {
    my ($server, $tx) = @_;
    $tx->res->code(200);
    $tx->res->headers->content_type('text/plain');
    $tx->res->body('Hello World!');
    $tx->resume;
  });

=head1 ATTRIBUTES

L<Mojo::Server> implements the following attributes.

=head2 app

  my $app = $server->app;
  $server = $server->app(MojoSubclass->new);

Application this server handles, defaults to a L<Mojo::HelloWorld> object.

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 new

  my $server = Mojo::Server->new;

Construct a new L<Mojo::Server> object and subscribe to C<request> event with
default request handling.

=head2 build_app

  my $app = $server->build_app('Mojo::HelloWorld');

Build application from class.

=head2 build_tx

  my $tx = $server->build_tx;

Let application build a transaction.

=head2 load_app

  my $app = $server->load_app('/home/sri/myapp.pl');

Load application from script.

  say Mojo::Server->new->load_app('./myapp.pl')->home;

=head2 run

  $server->run;

Run server. Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
