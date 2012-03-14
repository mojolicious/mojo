package Mojo;
use Mojo::Base -base;

use Carp 'croak';
use Mojo::Home;
use Mojo::IOLoop;
use Mojo::Log;
use Mojo::Transaction::HTTP;
use Mojo::UserAgent;
use Scalar::Util 'weaken';

has home => sub { Mojo::Home->new };
has log  => sub { Mojo::Log->new };
has ua   => sub {
  my $self = shift;

  # Fresh user agent
  my $ua = Mojo::UserAgent->new->app($self);
  weaken $self;
  $ua->on(error => sub { $self->log->error(pop) });
  weaken $ua->{app};

  return $ua;
};

# "Oh, so they have internet on computers now!"
sub new {
  my $self = shift->SUPER::new(@_);

  # Detect home directory
  $self->home->detect(ref $self);

  # Log directory
  $self->log->path($self->home->rel_file('log/mojo.log'))
    if -w $self->home->rel_file('log');

  return $self;
}

sub build_tx { Mojo::Transaction::HTTP->new }

sub config { shift->_dict(config => @_) }

# "D’oh."
sub handler { croak 'Method "handler" not implemented in subclass' }

sub _dict {
  my ($self, $name) = (shift, shift);

  # Hash
  $self->{$name} ||= {};
  return $self->{$name} unless @_;

  # Get
  return $self->{$name}->{$_[0]} unless @_ > 1 || ref $_[0];

  # Set
  my $values = ref $_[0] ? $_[0] : {@_};
  $self->{$name} = {%{$self->{$name}}, %$values};

  return $self;
}

1;
__END__

=head1 NAME

Mojo - Duct tape for the HTML5 web!

=head1 SYNOPSIS

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

Mojo provides a flexible runtime environment for Perl real-time web
frameworks. It provides all the basic tools and helpers needed to write
simple web applications and higher level web frameworks such as
L<Mojolicious>.

See L<Mojolicious> for more!

=head1 ATTRIBUTES

L<Mojo> implements the following attributes.

=head2 C<home>

  my $home = $app->home;
  $app     = $app->home(Mojo::Home->new);

The home directory of your application, defaults to a L<Mojo::Home> object
which stringifies to the actual path.

  # Generate portable path relative to home directory
  my $path = $app->home->rel_file('data/important.txt');

=head2 C<log>

  my $log = $app->log;
  $app    = $app->log(Mojo::Log->new);

The logging layer of your application, defaults to a L<Mojo::Log> object.

  # Log debug message
  $app->log->debug('It works!');

=head2 C<ua>

  my $ua = $app->ua;
  $app   = $app->ua(Mojo::UserAgent->new);

A full featured HTTP 1.1 user agent for use in your applications, defaults to
a L<Mojo::UserAgent> object.

  # Perform blocking request
  my $body = $app->ua->get('mojolicio.us')->res->body;

=head1 METHODS

L<Mojo> inherits all methods from L<Mojo::Base> and implements the following
new ones.

=head2 C<new>

  my $app = Mojo->new;

Construct a new L<Mojo> application. Will automatically detect your home
directory and set up logging to C<log/mojo.log> if there's a C<log>
directory.

=head2 C<build_tx>

  my $tx = $app->build_tx;

Transaction builder, defaults to building a L<Mojo::Transaction::HTTP>
object.

=head2 C<config>

  my $config = $app->config;
  my $foo    = $app->config('foo');
  $app       = $app->config({foo => 'bar'});
  $app       = $app->config(foo => 'bar');

Application configuration.

  # Manipulate configuration
  $app->config->{foo} = 'bar';
  my $foo = $app->config->{foo};
  delete $app->config->{foo};

=head2 C<handler>

  $app->handler($tx);

The handler is the main entry point to your application or framework and
will be called for each new transaction, which will usually be a
L<Mojo::Transaction::HTTP> or L<Mojo::Transaction::WebSocket> object.

  sub handler {
    my ($self, $tx) = @_;
    ...
  }

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
