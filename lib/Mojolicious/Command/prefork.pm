package Mojolicious::Command::prefork;
use Mojo::Base 'Mojolicious::Command';

use Mojo::Server::Prefork;
use Mojo::Util 'getopt';

has description =>
  'Start application with pre-forking HTTP and WebSocket server';
has usage => sub { shift->extract_usage };

sub run {
  my ($self, @args) = @_;

  my $prefork = Mojo::Server::Prefork->new(app => $self->app);
  getopt \@args,
    'a|accepts=i'            => sub { $prefork->accepts($_[1]) },
    'b|backlog=i'            => sub { $prefork->backlog($_[1]) },
    'c|clients=i'            => sub { $prefork->max_clients($_[1]) },
    'G|graceful-timeout=i'   => sub { $prefork->graceful_timeout($_[1]) },
    'I|heartbeat-interval=i' => sub { $prefork->heartbeat_interval($_[1]) },
    'H|heartbeat-timeout=i'  => sub { $prefork->heartbeat_timeout($_[1]) },
    'i|inactivity-timeout=i' => sub { $prefork->inactivity_timeout($_[1]) },
    'l|listen=s'   => \my @listen,
    'P|pid-file=s' => sub { $prefork->pid_file($_[1]) },
    'p|proxy'      => sub { $prefork->reverse_proxy(1) },
    'r|requests=i' => sub { $prefork->max_requests($_[1]) },
    'w|workers=i'  => sub { $prefork->workers($_[1]) };

  $prefork->listen(\@listen) if @listen;
  $prefork->run;
}

1;

=encoding utf8

=head1 NAME

Mojolicious::Command::prefork - Pre-fork command

=head1 SYNOPSIS

  Usage: APPLICATION prefork [OPTIONS]

    ./myapp.pl prefork
    ./myapp.pl prefork -m production -l http://*:8080
    ./myapp.pl prefork -l http://127.0.0.1:8080 -l https://[::]:8081
    ./myapp.pl prefork -l 'https://*:443?cert=./server.crt&key=./server.key'

  Options:
    -a, --accepts <number>               Number of connections for workers to
                                         accept, defaults to 10000
    -b, --backlog <size>                 Listen backlog size, defaults to
                                         SOMAXCONN
    -c, --clients <number>               Maximum number of concurrent
                                         connections, defaults to 1000
    -G, --graceful-timeout <seconds>     Graceful timeout, defaults to 20.
    -I, --heartbeat-interval <seconds>   Heartbeat interval, defaults to 5
    -H, --heartbeat-timeout <seconds>    Heartbeat timeout, defaults to 20
    -h, --help                           Show this summary of available options
        --home <path>                    Path to home directory of your
                                         application, defaults to the value of
                                         MOJO_HOME or auto-detection
    -i, --inactivity-timeout <seconds>   Inactivity timeout, defaults to the
                                         value of MOJO_INACTIVITY_TIMEOUT or 15
    -l, --listen <location>              One or more locations you want to
                                         listen on, defaults to the value of
                                         MOJO_LISTEN or "http://*:3000"
    -m, --mode <name>                    Operating mode for your application,
                                         defaults to the value of
                                         MOJO_MODE/PLACK_ENV or "development"
    -P, --pid-file <path>                Path to process id file, defaults to
                                         "prefork.pid" in a temporary diretory
    -p, --proxy                          Activate reverse proxy support,
                                         defaults to the value of
                                         MOJO_REVERSE_PROXY
    -r, --requests <number>              Maximum number of requests per
                                         keep-alive connection, defaults to 100
    -w, --workers <number>               Number of workers, defaults to 4

=head1 DESCRIPTION

L<Mojolicious::Command::prefork> starts applications with the
L<Mojo::Server::Prefork> backend.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

See L<Mojolicious::Commands/"COMMANDS"> for a list of commands that are
available by default.

=head1 ATTRIBUTES

L<Mojolicious::Command::prefork> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $prefork->description;
  $prefork        = $prefork->description('Foo');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $prefork->usage;
  $prefork  = $prefork->usage('Foo');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::prefork> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $prefork->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
