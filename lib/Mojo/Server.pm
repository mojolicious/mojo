package Mojo::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Loader;
use Mojo::Util 'md5_sum';
use Scalar::Util 'blessed';

has app => sub {

  # Already initialized application
  my $app = $ENV{MOJO_APP} || 'Mojo::HelloWorld';
  return $app if ref $app;

  # Load and initialize application
  if (my $e = Mojo::Loader->new->load($app)) { die $e if ref $e }
  return $ENV{MOJO_APP} = $app->new;
};

sub new {
  my $self = shift->SUPER::new(@_);
  $self->on(request => sub { shift->app->handler(shift) });
  return $self;
}

sub build_tx { shift->app->build_tx }

sub load_app {
  my ($self, $file) = @_;

  # Clean up environment
  local $ENV{MOJO_APP_LOADER} = 1;
  local ($ENV{MOJO_APP}, $ENV{MOJO_EXE});

  # Try to load application from script into sandbox
  my $app = eval <<EOF;
package Mojo::Server::SandBox::@{[md5_sum($file . $$)]};
my \$app = do \$file;
if (!\$app && (my \$e = \$@ || \$!)) { die \$e }
\$app;
EOF
  die qq{Couldn't load application from file "$file": $@} if !$app && $@;
  die qq{File "$file" did not return an application object.\n}
    unless blessed $app && $app->isa('Mojo');
  return $self->app($app)->app;
}

# "Are you saying you're never going to eat any animal again? What about
#  bacon?
#  No.
#  Ham?
#  No.
#  Pork chops?
#  Dad, those all come from the same animal.
#  Heh heh heh. Ooh, yeah, right, Lisa. A wonderful, magical animal."
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

L<Mojo::Server> can emit the following events.

=head2 C<request>

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

=head2 C<app>

  my $app = $server->app;
  $server = $server->app(MojoSubclass->new);

Application this server handles, defaults to the value of the C<MOJO_APP>
environment variable or a L<Mojo::HelloWorld> object.

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::EventEmitter> and implements
the following new ones.

=head2 C<new>

  my $server = Mojo::Server->new;

Construct a new L<Mojo::Server> object and subscribe to C<request> event with
default request handling.

=head2 C<build_tx>

  my $tx = $server->build_tx;

Let application build a transaction.

=head2 C<load_app>

  my $app = $server->load_app('./myapp.pl');

Load application from script.

  say Mojo::Server->new->load_app('./myapp.pl')->home;

=head2 C<run>

  $server->run;

Run server. Meant to be overloaded in a subclass.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
