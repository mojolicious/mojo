package Mojolicious::Commands;
use Mojo::Base 'Mojo::Command';

use Getopt::Long
  qw/GetOptions :config no_auto_abbrev no_ignore_case pass_through/;

# "One day a man has everything, the next day he blows up a $400 billion
#  space station, and the next day he has nothing. It makes you think."
has hint => <<"EOF";

These options are available for all commands:
    -h, --help          Get more information on a specific command.
        --home <path>   Path to your applications home directory, defaults to
                        the value of MOJO_HOME or auto detection.
    -m, --mode <name>   Run mode of your application, defaults to the value
                        of MOJO_MODE or "development".

See '$0 help COMMAND' for more information on a specific command.
EOF
has namespaces => sub { [qw/Mojolicious::Command Mojo::Command/] };

# Command line options for MOJO_HELP, MOJO_HOME and MOJO_MODE
BEGIN {
  GetOptions(
    'h|help'   => sub { $ENV{MOJO_HELP} = 1 },
    'home=s'   => sub { $ENV{MOJO_HOME} = $_[1] },
    'm|mode=s' => sub { $ENV{MOJO_MODE} = $_[1] }
  ) unless Mojo::Command->detect;
}

1;
__END__

=head1 NAME

Mojolicious::Commands - Commands

=head1 SYNOPSIS

  use Mojolicious::Commands;

  # Command line interface
  my $commands = Mojolicious::Commands->new;
  $commands->run(@ARGV);

=head1 DESCRIPTION

L<Mojolicious::Commands> is the interactive command line interface to the
L<Mojolicious> framework. It will automatically detect available commands in
the C<Mojolicious::Command> namespace.

=head1 COMMANDS

These commands are available by default.

=head2 C<help>

  $ mojo
  $ mojo help
  $ ./myapp.pl help

List available commands with short descriptions.

  $ mojo help <command>
  $ ./myapp.pl help <command>

List available options for the command with short descriptions.

=head2 C<cgi>

  $ ./myapp.pl cgi

Start application with CGI backend.

=head2 C<cpanify>

  $ mojo cpanify -u sri -p secr3t Mojolicious-Plugin-Fun-0.1.tar.gz

Upload files to CPAN.

=head2 C<daemon>

  $ ./myapp.pl daemon

Start application with standalone HTTP 1.1 server backend.

=head2 C<eval>

  $ ./myapp.pl eval 'say app->home'

Run code against application.

=head2 C<generate>

  $ mojo generate
  $ mojo generate help
  $ ./myapp.pl generate help

List available generator commands with short descriptions.

  $ mojo generate help <generator>
  $ ./myapp.pl generate help <generator>

List available options for generator command with short descriptions.

=head2 C<generate app>

  $ mojo generate app <AppName>

Generate application directory structure for a fully functional
L<Mojolicious> application.

=head2 C<generate lite_app>

  $ mojo generate lite_app

Generate a fully functional L<Mojolicious::Lite> application.

=head2 C<generate makefile>

  $ mojo generate makefile
  $ ./myapp.pl generate makefile

Generate C<Makefile.PL> file for application.

=head2 C<generate plugin>

  $ mojo generate plugin <PluginName>

Generate directory structure for a fully functional L<Mojolicious> plugin.

=head2 C<get>

  $ mojo get http://mojolicio.us
  $ ./myapp.pl get /foo

Perform requests to remote host or local application.

=head2 C<inflate>

  $ ./myapp.pl inflate

Turn templates and static files embedded in the C<DATA> sections of your
application into real files.

=head2 C<psgi>

  $ ./myapp.pl psgi

Start application with PSGI backend.

=head2 C<routes>

  $ ./myapp.pl routes

List application routes.

=head2 C<test>

  $ mojo test
  $ ./myapp.pl test
  $ ./myapp.pl test t/fun.t

Runs application tests from the C<t> directory.

=head2 C<version>

  $ mojo version
  $ ./myapp.pl version

Show version information for installed core and optional modules, very useful
for debugging.

=head1 ATTRIBUTES

L<Mojolicious::Commands> inherits all attributes from L<Mojo::Command> and
implements the following new ones.

=head2 C<hint>

  my $hint  = $commands->hint;
  $commands = $commands->hint('Foo!');

Short hint shown after listing available commands.

=head2 C<namespaces>

  my $namespaces = $commands->namespaces;
  $commands      = $commands->namespaces(['Mojolicious::Commands']);

Namespaces to search for available commands, defaults to
C<Mojolicious::Command> and C<Mojo::Command>.

=head1 METHODS

L<Mojolicious::Commands> inherits all methods from L<Mojo::Command>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
