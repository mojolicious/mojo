package Mojo::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp qw(croak);
use Mojo::File qw(path);
use Mojo::Loader qw(load_class);
use Mojo::Util qw(md5_sum);
use POSIX ();
use Scalar::Util qw(blessed);

has app           => sub { shift->build_app('Mojo::HelloWorld') };
has reverse_proxy => sub { $ENV{MOJO_REVERSE_PROXY} };

sub build_app {
  my ($self, $app) = (shift, shift);
  local $ENV{MOJO_EXE};
  return $self->app($app->new(@_))->app unless my $e = load_class $app;
  die ref $e ? $e : qq{Can't find application class "$app" in \@INC. (@INC)\n};
}

sub build_tx {
  my $self = shift;
  my $tx   = $self->app->build_tx;
  $tx->req->reverse_proxy(1) if $self->reverse_proxy;
  return $tx;
}

sub daemonize {

  # Fork and kill parent
  die "Can't fork: $!" unless defined(my $pid = fork);
  exit 0 if $pid;
  POSIX::setsid == -1 and die "Can't start a new session: $!";

  # Close filehandles
  open STDIN,  '<',  '/dev/null';
  open STDOUT, '>',  '/dev/null';
  open STDERR, '>&', STDOUT;
}

sub load_app {
  my ($self, $path) = @_;

  # Clean environment (reset FindBin defensively)
  {
    local $0 = $path = path($path)->to_abs->to_string;
    require FindBin;
    FindBin->again;
    local $ENV{MOJO_APP_LOADER} = 1;
    local $ENV{MOJO_EXE};

    # Try to load application from script into sandbox
    delete $INC{$path};
    my $app = eval "package Mojo::Server::Sandbox::@{[md5_sum $path]}; require \$path";
    die qq{Can't load application from file "$path": $@} if $@;
    die qq{File "$path" did not return an application object.\n} unless blessed $app && $app->can('handler');
    $self->app($app);
  };
  FindBin->again;

  return $self->app;
}

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(request => sub { shift->app->handler(shift) });
  return $self;
}

sub run { croak 'Method "run" not implemented by subclass' }

1;

=encoding utf8

=head1 NAME

Mojo::Server - HTTP/WebSocket server base class

=head1 SYNOPSIS

  package Mojo::Server::MyServer;
  use Mojo::Base 'Mojo::Server', -signatures;

  sub run ($self) {

    # Get a transaction
    my $tx = $self->build_tx;

    # Emit "request" event
    $self->emit(request => $tx);
  }

=head1 DESCRIPTION

L<Mojo::Server> is an abstract base class for HTTP/WebSocket servers and server interfaces, like L<Mojo::Server::CGI>,
L<Mojo::Server::Daemon>, L<Mojo::Server::Hypnotoad>, L<Mojo::Server::Morbo>, L<Mojo::Server::Prefork> and
L<Mojo::Server::PSGI>.

=head1 EVENTS

L<Mojo::Server> inherits all events from L<Mojo::EventEmitter> and can emit the following new ones.

=head2 request

  $server->on(request => sub ($server, $tx) {...});

Emitted when a request is ready and needs to be handled.

  $server->on(request => sub ($server, $tx) {
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

=head2 reverse_proxy

  my $bool = $server->reverse_proxy;
  $server  = $server->reverse_proxy($bool);

This server operates behind a reverse proxy, defaults to the value of the C<MOJO_REVERSE_PROXY> environment variable.

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::EventEmitter> and implements the following new ones.

=head2 build_app

  my $app = $server->build_app('MyApp');
  my $app = $server->build_app('MyApp', log => Mojo::Log->new);
  my $app = $server->build_app('MyApp', {log => Mojo::Log->new});

Build application from class and assign it to L</"app">.

=head2 build_tx

  my $tx = $server->build_tx;

Let application build a transaction.

=head2 daemonize

  $server->daemonize;

Daemonize server process.

=head2 load_app

  my $app = $server->load_app('/home/sri/myapp.pl');

Load application from script and assign it to L</"app">.

  say Mojo::Server->new->load_app('./myapp.pl')->home;

=head2 new

  my $server = Mojo::Server->new;
  my $server = Mojo::Server->new(reverse_proxy => 1);
  my $server = Mojo::Server->new({reverse_proxy => 1});

Construct a new L<Mojo::Server> object and subscribe to L</"request"> event with default request handling.

=head2 run

  $server->run;

Run server. Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
