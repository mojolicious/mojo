package Mojolicious::Command::daemon;
use Mojo::Base 'Mojo::Command';

use Getopt::Long qw(GetOptions :config no_auto_abbrev no_ignore_case);
use Mojo::Server::Daemon;

has description => "Start application with HTTP 1.1 and WebSocket server.\n";
has usage       => <<"EOF";
usage: $0 daemon [OPTIONS]

These options are available:
  -b, --backlog <size>         Set listen backlog size, defaults to
                               SOMAXCONN.
  -c, --clients <number>       Set maximum number of concurrent clients,
                               defaults to 1000.
  -g, --group <name>           Set group name for process.
  -i, --inactivity <seconds>   Set inactivity timeout, defaults to the value
                               of MOJO_INACTIVITY_TIMEOUT or 15.
  -l, --listen <location>      Set one or more locations you want to listen
                               on, defaults to the value of MOJO_LISTEN or
                               "http://*:3000".
  -p, --proxy                  Activate reverse proxy support, defaults to
                               the value of MOJO_REVERSE_PROXY.
  -r, --requests <number>      Set maximum number of requests per keep-alive
                               connection, defaults to 25.
  -u, --user <name>            Set username for process.
EOF

# "It's an albino humping worm!
#  Why do they call it that?
#  Cause it has no pigment."
sub run {
  my $self   = shift;
  my $daemon = Mojo::Server::Daemon->new;

  # Options
  local @ARGV = @_;
  my @listen;
  GetOptions(
    'b|backlog=i'    => sub { $daemon->backlog($_[1]) },
    'c|clients=i'    => sub { $daemon->max_clients($_[1]) },
    'g|group=s'      => sub { $daemon->group($_[1]) },
    'i|inactivity=i' => sub { $daemon->inactivity_timeout($_[1]) },
    'l|listen=s'     => \@listen,
    'p|proxy' => sub { $ENV{MOJO_REVERSE_PROXY} = 1 },
    'r|requests=i' => sub { $daemon->max_requests($_[1]) },
    'u|user=s'     => sub { $daemon->user($_[1]) }
  );

  # Start
  $daemon->listen(\@listen) if @listen;
  $daemon->run;
}

1;

=head1 NAME

Mojolicious::Command::daemon - Daemon command

=head1 SYNOPSIS

  use Mojolicious::Command::daemon;

  my $daemon = Mojolicious::Command::daemon->new;
  $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::daemon> starts applications with
L<Mojo::Server::Daemon> backend.

=head1 ATTRIBUTES

L<Mojolicious::Command::daemon> inherits all attributes from L<Mojo::Command>
and implements the following new ones.

=head2 C<description>

  my $description = $daemon->description;
  $daemon         = $daemon->description('Foo!');

Short description of this command, used for the command list.

=head2 C<usage>

  my $usage = $daemon->usage;
  $daemon   = $daemon->usage('Foo!');

Usage information for this command, used for the help screen.

=head1 METHODS

L<Mojolicious::Command::daemon> inherits all methods from L<Mojo::Command> and
implements the following new ones.

=head2 C<run>

  $daemon->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
