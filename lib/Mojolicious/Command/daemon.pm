package Mojolicious::Command::daemon;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Server::Daemon;
use Mojo::Util qw(getopt);

has description => 'Start application with HTTP and WebSocket server';
has usage       => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  my $daemon = Mojo::Server::Daemon->new(app => $self->app);
  die $self->usage
    unless getopt \@args,
    'b|backlog=i'            => sub { $daemon->backlog($_[1]) },
    'c|clients=i'            => sub { $daemon->max_clients($_[1]) },
    'i|inactivity-timeout=i' => sub { $daemon->inactivity_timeout($_[1]) },
    'k|keep-alive-timeout=i' => sub { $daemon->keep_alive_timeout($_[1]) },
    'l|listen=s'             => \my @listen,
    'p|proxy'                => sub { $daemon->reverse_proxy(1) },
    'r|requests=i'           => sub { $daemon->max_requests($_[1]) };

  $daemon->listen(\@listen) if @listen;
  $daemon->run;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::daemon - Daemon command

=head1 SYNOPSIS

  Usage: APPLICATION daemon [OPTIONS]

    ./myapp.pl daemon
    ./myapp.pl daemon -m production -l http://*:8080
    ./myapp.pl daemon -l http://127.0.0.1:8080 -l https://[::]:8081
    ./myapp.pl daemon -l 'https://*:443?cert=./server.crt&key=./server.key'
    ./myapp.pl daemon -l http+unix://%2Ftmp%2Fmyapp.sock

  Options:
    -b, --backlog <size>                 Listen backlog size, defaults to
                                         SOMAXCONN
    -c, --clients <number>               Maximum number of concurrent
                                         connections, defaults to 1000
    -h, --help                           Show this summary of available options
        --home <path>                    Path to home directory of your
                                         application, defaults to the value of
                                         MOJO_HOME or auto-detection
    -i, --inactivity-timeout <seconds>   Inactivity timeout, defaults to the
                                         value of MOJO_INACTIVITY_TIMEOUT or 30
    -k, --keep-alive-timeout <seconds>   Keep-alive timeout, defaults to the
                                         value of MOJO_KEEP_ALIVE_TIMEOUT or 5
    -l, --listen <location>              One or more locations you want to
                                         listen on, defaults to the value of
                                         MOJO_LISTEN or "http://*:3000"
    -m, --mode <name>                    Operating mode for your application,
                                         defaults to the value of
                                         MOJO_MODE/PLACK_ENV or "development"
    -p, --proxy                          Activate reverse proxy support,
                                         defaults to the value of
                                         MOJO_REVERSE_PROXY
    -r, --requests <number>              Maximum number of requests per
                                         keep-alive connection, defaults to 100

=head1 DESCRIPTION

L<Mojolicious::Command::daemon> starts applications with the L<Mojo::Server::Daemon> backend.

This is a core command, that means it is always enabled and its code a good example for learning to build new commands,
you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::daemon> inherits all attributes from L<Mojolicious::Command> and implements the following new
ones.

=head2 description

  my $description = $daemon->description;
  $daemon         = $daemon->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $daemon->usage;
  $daemon   = $daemon->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::daemon> inherits all methods from L<Mojolicious::Command> and implements the following new
ones.

=head2 run

  $daemon->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
