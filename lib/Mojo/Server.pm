package Mojo::Server;
use Mojo::Base 'Mojo::EventEmitter';

use Carp 'croak';
use Mojo::Loader;
use Mojo::Util 'md5_sum';
use Scalar::Util 'blessed';

has app => sub {
  my $self = shift;
  return $ENV{MOJO_APP} if ref $ENV{MOJO_APP};
  if (my $e = Mojo::Loader->load($self->app_class)) { die $e if ref $e }
  return $self->app_class->new;
};
has app_class =>
  sub { ref $ENV{MOJO_APP} || $ENV{MOJO_APP} || 'Mojo::HelloWorld' };

sub new {
  my $self = shift->SUPER::new(@_);

  # Events
  $self->on_request(sub { shift->app->handler(shift) });
  $self->on_transaction(
    sub {
      my ($self, $txref) = @_;
      $$txref = $self->app->build_tx;
    }
  );
  $self->on_upgrade(
    sub {
      my ($self, $txref) = @_;
      $$txref = $self->app->upgrade_tx($$txref);
      $$txref->server_handshake;
    }
  );

  return $self;
}

sub load_app {
  my ($self, $file) = @_;

  # Clean up environment
  local $ENV{MOJO_APP_LOADER} = 1;
  local $ENV{MOJO_APP};
  local $ENV{MOJO_EXE};

  # Try to load application from script into sandbox
  my $class = 'Mojo::Server::SandBox::' . md5_sum($file . $$);
  my $app;
  die $@ unless eval <<EOF;
package $class;
{
  unless (\$app = do \$file) {
    die qq/Can't load application "\$file": \$@/ if \$@;
    die qq/Can't load application "\$file": \$!/ unless defined \$app;
    die qq/Can't load application' "\$file".\n/ unless \$app;
  }
}
1;
EOF
  die qq/"$file" is not a valid application.\n/
    unless blessed $app && $app->isa('Mojo');
  $self->app($app);
  return $app;
}

sub on_request     { shift->on(request     => shift) }
sub on_transaction { shift->on(transaction => shift) }
sub on_upgrade     { shift->on(upgrade     => shift) }

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
__END__

=head1 NAME

Mojo::Server - HTTP server base class

=head1 SYNOPSIS

  use Mojo::Base 'Mojo::Server';

  sub run {
    my $self = shift;

    # Get a transaction
    $self->emit(transaction => \(my $tx));

    # Emit request
    $self->emit(request => $tx);
  }

=head1 DESCRIPTION

L<Mojo::Server> is an abstract HTTP server base class.

=head1 EVENTS

L<Mojo::Server> can emit the following events.

=head2 C<request>

  $server->on(request => sub {
    my ($server, $tx) = @_;
  });

Emitted for requests that need a response.

=head2 C<transaction>

  $server->on(request => sub {
    my ($server, $txref) = @_;
  });

Emitted when a new transaction is needed.

=head2 C<upgrade>

  $server->on(upgrade => sub {
    my ($server, $txref) = @_;
  });

Emitted when a transaction needs to be upgraded.

=head1 ATTRIBUTES

L<Mojo::Server> implements the following attributes.

=head2 C<app>

  my $app = $server->app;
  $server = $server->app(MojoSubclass->new);

Application this server handles, defaults to a L<Mojo::HelloWorld> object.

=head2 C<app_class>

  my $app_class = $server->app_class;
  $server       = $server->app_class('MojoSubclass');

Class of the application this server handles, defaults to
L<Mojo::HelloWorld>.

=head1 METHODS

L<Mojo::Server> inherits all methods from L<Mojo::EventEmitter> and
implements the following new ones.

=head2 C<new>

  my $server = Mojo::Server->new;

Construct a new L<Mojo::Server> object.

=head2 C<load_app>

  my $app = $server->load_app('./myapp.pl');

Load application from script.
Note that this method is EXPERIMENTAL and might change without warning!

  say Mojo::Server->new->load_app('./myapp.pl')->home;

=head2 C<on_request>

  $server->on_request(sub {...});

Register C<request> event.

=head2 C<on_transaction>

  $server->on_transaction(sub {...});

Register C<transaction> event.

=head2 C<on_upgrade>

  $server->on_upgrade(sub {...});

Register C<upgrade> event.

=head2 C<run>

  $server->run;

Start server.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
