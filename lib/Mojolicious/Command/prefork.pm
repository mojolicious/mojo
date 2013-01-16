package Mojolicious::Command::prefork;
use Mojo::Base 'Mojolicious::Command';

use Getopt::Long qw(GetOptionsFromArray :config no_auto_abbrev no_ignore_case);
use Mojo::Server::Prefork;

has description =>
  "Start application with preforking HTTP and WebSocket server.\n";
has usage => <<"EOF";
usage: $0 prefork [OPTIONS]

These options are available:
  -B <seconds>                 Set heartbeat interval, defaults to 5.
  -b, --backlog <size>         Set listen backlog size, defaults to
                               SOMAXCONN.
  -c, --clients <number>       Set maximum number of concurrent clients,
                               defaults to 1000.
  -f <path>                    Set lock file path, defaults to a random file.
  -G, --graceful <seconds>     Set graceful timeout, defaults to 20.
  -g, --group <name>           Set group name for process.
  -H <seconds>                 Set heartbeat timeout, defaults to 20.
  -i, --inactivity <seconds>   Set inactivity timeout, defaults to the value
                               of MOJO_INACTIVITY_TIMEOUT or 15.
  -L <seconds>                 Set lock timeout, defaults to 0.5.
  -l, --listen <location>      Set one or more locations you want to listen
                               on, defaults to the value of MOJO_LISTEN or
                               "http://*:3000".
  -P, --pid <path>             Set path to process id file, defaults to a
                               random file.
  -p, --proxy                  Activate reverse proxy support, defaults to
                               the value of MOJO_REVERSE_PROXY.
  -r, --requests <number>      Set maximum number of requests per keep-alive
                               connection, defaults to 25.
  -u, --user <name>            Set username for process.
  -w, --workers <number>       Set number of worker processes.
EOF

sub run {
  my ($self, @args) = @_;

  # Options
  my $prefork = Mojo::Server::Prefork->new(app => $self->app);
  GetOptionsFromArray \@args,
    'B=i'            => sub { $prefork->heartbeat_interval($_[1]) },
    'b|backlog=i'    => sub { $prefork->backlog($_[1]) },
    'c|clients=i'    => sub { $prefork->max_clients($_[1]) },
    'f=i'            => sub { $prefork->lock_file($_[1]) },
    'G|graceful=i'   => sub { $prefork->graceful_timeout($_[1]) },
    'g|group=s'      => sub { $prefork->group($_[1]) },
    'H=i'            => sub { $prefork->heartbeat_timeout($_[1]) },
    'i|inactivity=i' => sub { $prefork->inactivity_timeout($_[1]) },
    'L=i'            => sub { $prefork->lock_timeout($_[1]) },
    'l|listen=s'     => \my @listen,
    'P|pid=i'        => sub { $prefork->pid_file($_[1]) },
    'p|proxy' => sub { $ENV{MOJO_REVERSE_PROXY} = 1 },
    'r|requests=i' => sub { $prefork->max_requests($_[1]) },
    'u|user=s'     => sub { $prefork->user($_[1]) },
    'w|workers=i'  => sub { $prefork->workers($_[1]) };

  # Start
  $prefork->listen(\@listen) if @listen;
  $prefork->run;
}

1;

=head1 NAME

Mojolicious::Command::prefork - Prefork command

=head1 SYNOPSIS

  use Mojolicious::Command::prefork;

  my $prefork = Mojolicious::Command::prefork->new;
  $prefork->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::prefork> starts applications with
L<Mojo::Server::Prefork> backend.

This is a core command, that means it is always enabled and its code a good
example for learning to build new commands, you're welcome to fork it.

=head1 ATTRIBUTES

L<Mojolicious::Command::prefork> inherits all attributes from
L<Mojolicious::Command> and implements the following new ones.

=head2 description

  my $description = $prefork->description;
  $prefork        = $prefork->description('Foo!');

Short description of this command, used for the command list.

=head2 usage

  my $usage = $prefork->usage;
  $prefork  = $prefork->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::prefork> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.

=head2 run

  $prefork->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
