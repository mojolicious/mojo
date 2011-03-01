package Mojolicious::Commands;
use Mojo::Base 'Mojo::Command';

use Getopt::Long qw/GetOptions :config pass_through/;

# "One day a man has everything, the next day he blows up a $400 billion
#  space station, and the next day he has nothing. It makes you think."
has hint => <<"EOF";

These options are available for all commands:
    --home <path>   Path to your applications home directory, defaults to
                    the value of MOJO_HOME or auto detection.
    --mode <name>   Run mode of your application, defaults to the value of
                    MOJO_MODE or development.

See '$0 help COMMAND' for more information on a specific command.
EOF
has namespaces => sub { [qw/Mojolicious::Command Mojo::Command/] };

# Command line options for MOJO_HOME and MOJO_MODE
BEGIN {
  GetOptions(
    'home=s' => sub { $ENV{MOJO_HOME} = $_[1] },
    'mode=s' => sub { $ENV{MOJO_MODE} = $_[1] }
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
L<Mojolicious> framework.
It will automatically detect available commands in the
L<Mojolicious::Command> namespace.

=head1 COMMANDS

These commands are available by default.

=head2 C<help>

  mojo
  mojo help

List available commands with short descriptions.

  mojo help <command>

List available options for the command with short descriptions.

=head2 C<cgi>

  mojo cgi
  script/myapp cgi

Start application with CGI backend.

=head2 C<daemon>

  mojo daemon
  script/myapp daemon

Start application with standalone HTTP 1.1 server backend.

=head2 C<fastcgi>

  mojo fastcgi
  script/myapp fastcgi

Start application with FastCGI backend.

=head2 C<generate>

  mojo generate
  mojo generate help

List available generator commands with short descriptions.

  mojo generate help <generator>

List available options for generator command with short descriptions.

=head2 C<generate app>

  mojo generate app <AppName>

Generate application directory structure for a fully functional
L<Mojolicious> application.

=head2 C<generate gitignore>

  mojo generate gitignore

Generate C<.gitignore> file.

=head2 C<generate hypnotoad>

  mojo generate hypnotoad

Generate C<hypnotoad.conf> file.

=head2 C<generate lite_app>

  mojo generate lite_app

Generate a fully functional L<Mojolicious::Lite> application.

=head2 C<generate makefile>

  mojo generate makefile

Generate C<Makefile.PL> file for application.

=head2 C<get>

  mojo get http://mojolicio.us
  script/myapp get /foo

Perform GET request to remote host or local application.

=head2 C<inflate>

  myapp.pl inflate

Turn embedded files from the C<DATA> section into real files.

=head2 C<routes>

  myapp.pl routes
  script/myapp routes

List application routes.

=head2 C<test>

  mojo test
  script/myapp test
  script/myapp test t/foo.t

Runs application tests from the C<t> directory.

=head2 C<version>

  mojo version

List version information for installed core and optional modules, very useful
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

Namespaces to search for available commands, defaults to L<Mojo::Command> and
L<Mojolicious::Command>.

=head1 METHODS

L<Mojolicious::Commands> inherits all methods from L<Mojo::Command>.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicio.us>.

=cut
