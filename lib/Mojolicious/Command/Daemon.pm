package Mojolicious::Command::Daemon;
use Mojo::Base 'Mojo::Command';

use Mojo::Server::Daemon;

use Getopt::Long 'GetOptions';

has description => <<'EOF';
Start application with HTTP 1.1 and WebSocket server.
EOF
has usage => <<"EOF";
usage: $0 daemon [OPTIONS]

These options are available:
  --backlog <size>        Set listen backlog size, defaults to SOMAXCONN.
  --clients <number>      Set maximum number of concurrent clients, defaults
                          to 1000.
  --group <name>          Set group name for process.
  --keepalive <seconds>   Set keep-alive timeout, defaults to 15.
  --listen <location>     Set one or more locations you want to listen on,
                          defaults to http://*:3000.
  --proxy                 Activate reverse proxy support, defaults to the
                          value of MOJO_REVERSE_PROXY.
  --reload                Automatically reload application when the source
                          code changes.
  --requests <number>     Set maximum number of requests per keep-alive
                          connection, defaults to 100.
  --user <name>           Set user name for process.
  --websocket <seconds>   Set WebSocket timeout, defaults to 300.
EOF

# "This is the worst thing you've ever done.
#  You say that so often that it lost its meaning."
sub run {
  my $self   = shift;
  my $daemon = Mojo::Server::Daemon->new;

  local @ARGV = @_ if @_;
  my @listen;
  GetOptions(
    'backlog=i'   => sub { $daemon->backlog($_[1]) },
    'clients=i'   => sub { $daemon->max_clients($_[1]) },
    'group=s'     => sub { $daemon->group($_[1]) },
    'keepalive=i' => sub { $daemon->keep_alive_timeout($_[1]) },
    'listen=s'    => \@listen,
    'proxy' => sub { $ENV{MOJO_REVERSE_PROXY} = 1 },
    reload  => sub { $ENV{MOJO_RELOAD}        = 1 },
    'requests=i'  => sub { $daemon->max_requests($_[1]) },
    'user=s'      => sub { $daemon->user($_[1]) },
    'websocket=i' => sub { $daemon->websocket_timeout($_[1]) }
  );

  $daemon->listen(\@listen) if @listen;
  $daemon->run;

  return $self;
}

1;
__END__

=head1 NAME

Mojolicious::Command::Daemon - Daemon Command

=head1 SYNOPSIS

  use Mojolicious::Command::Daemon;

  my $daemon = Mojolicious::Command::Daemon->new;
  $daemon->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Command::Daemon> is a command interface to
L<Mojo::Server::Daemon>.

=head1 ATTRIBUTES

L<Mojolicious::Command::Daemon> inherits all attributes from L<Mojo::Command>
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

L<Mojolicious::Command::Daemon> inherits all methods from L<Mojo::Command>
and implements the following new ones.

=head2 C<run>

  $daemon = $daemon->run(@ARGV);

Run this command.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
